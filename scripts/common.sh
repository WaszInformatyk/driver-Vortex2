#!/usr/bin/env bash
# Shared checks for the Vortex 2 AU8830 installer. No changes on source.

export PACKAGE_NAME=vortex2-au8830
export PACKAGE_VERSION=0.1.0
export MODULE_NAME=snd_au8830

log()  { printf '[vortex2] %s\n' "$*"; }
warn() { printf '[vortex2] UWAGA: %s\n' "$*" >&2; }
die()  { printf '[vortex2] BŁĄD: %s\n' "$*" >&2; exit 1; }

require_root() {
    if [[ $EUID -ne 0 && ${VORTEX_TEST_MODE:-0} != 1 ]]; then
        die "Ta operacja wymaga uprawnień root. Użyj sudo."
    fi
}

vortex_cards() {
    lspci -Dnn -d 12eb:0002 2>/dev/null | awk '{print $1}'
}

require_hardware() {
    command -v lspci >/dev/null 2>&1 || die "Brak lspci (pakiet pciutils)."
    local cards=()
    mapfile -t cards < <(vortex_cards)
    if [[ ${#cards[@]} -eq 0 && ${VORTEX_ALLOW_NO_HARDWARE:-0} != 1 ]]; then
        die "Nie wykryto Aureal Vortex 2 [12eb:0002]. Dla samej kompilacji bez karty: VORTEX_ALLOW_NO_HARDWARE=1."
    fi
    if [[ $(uname -m) != x86_64 && ${VORTEX_ALLOW_UNSUPPORTED_ARCH:-0} != 1 ]]; then
        die "Ten pakiet został przetestowany tylko na x86_64, nie na $(uname -m)."
    fi
    if ((${#cards[@]})); then
        log "Wykryto AU8830: ${cards[*]}"
        local bdf driver
        for bdf in "${cards[@]}"; do
            driver=$(basename "$(readlink -f "/sys/bus/pci/devices/$bdf/driver" 2>/dev/null)" 2>/dev/null || true)
            [[ -z "$driver" || "$driver" == "$MODULE_NAME" ]] ||
                die "Karta $bdf używa nieoczekiwanego sterownika: $driver"
        done
    else
        warn "Tryb bez sprzętu: dozwolona jest tylko kompilacja/instalacja."
    fi
}

check_kernel() {
    local kernel=$1 build release_file target config symbol missing=()
    build="/lib/modules/$kernel/build"
    [[ -d "$build" ]] || die "Brak nagłówków dla $kernel: $build"

    release_file="$build/include/config/kernel.release"
    if [[ -r "$release_file" ]]; then
        target=$(<"$release_file")
        [[ "$target" == "$kernel" ]] ||
            die "Nagłówki $build raportują $target zamiast $kernel."
    else
        warn "Brak $release_file; DKMS zweryfikuje wersję podczas kompilacji."
    fi

    config="/boot/config-$kernel"
    if [[ -r "$config" ]]; then
        for symbol in CONFIG_SND CONFIG_SND_PCM CONFIG_SND_AC97_CODEC \
                      CONFIG_SND_MPU401_UART CONFIG_GAMEPORT; do
            grep -q "^$symbol=[ym]" "$config" || missing+=("$symbol")
        done
        ((${#missing[@]} == 0)) ||
            die "Jądro $kernel nie ma wymaganych opcji: ${missing[*]}"
    else
        warn "Brak $config; zależności zostaną sprawdzone przez modpost/modprobe."
    fi
    log "Nagłówki i konfiguracja jądra są dostępne: $kernel"
}

check_secure_boot() {
    local state='' key=0
    command -v mokutil >/dev/null 2>&1 || return 0
    state=$(mokutil --sb-state 2>/dev/null || true)
    if grep -qiE 'enabled|włącz' <<<"$state"; then
        for key in /var/lib/shim-signed/mok/MOK.priv /var/lib/dkms/mok.key; do
            [[ -f "$key" ]] && return 0
        done
        warn "Secure Boot jest włączony, a nie znaleziono klucza DKMS/MOK. Nie wyłączamy Secure Boot; skonfiguruj podpis lub rejestrację MOK przed --load."
    else
        log "Secure Boot nie wymaga dodatkowych działań (${state:-nieznany stan})."
    fi
}

assert_no_audio_users() {
    if ps -eo comm= | grep -E -q '^(obs|pipewire|pipewire-pulse|wireplumber|pulseaudio)$'; then
        die "Zatrzymaj OBS oraz usługi PipeWire/WirePlumber/PulseAudio przed przeładowaniem."
    fi
}

assert_pcm_idle() {
    local bdf carddir card status
    mapfile -t cards < <(vortex_cards)
    for bdf in "${cards[@]}"; do
        for carddir in "/sys/bus/pci/devices/$bdf/sound"/card*; do
            [[ -d "$carddir" ]] || continue
            card=${carddir##*/}
            for status in "/proc/asound/$card"/pcm*/sub*/status; do
                [[ -r "$status" ]] || continue
                if [[ $(<"$status") != closed ]]; then
                    die "Aktywny PCM: $status. Zakończ odtwarzanie przed przeładowaniem."
                fi
            done
        done
    done
}

load_module() {
    local expected=${1:-updates/dkms}
    assert_no_audio_users
    assert_pcm_idle
    modprobe -r "$MODULE_NAME" || die "Nie można wyładować $MODULE_NAME."
    modprobe "$MODULE_NAME" || die "Nie można załadować $MODULE_NAME. Sprawdź dmesg."
    modinfo -F filename "$MODULE_NAME" | grep -F "$expected" >/dev/null ||
        die "Załadowany moduł nie pochodzi z oczekiwanej ścieżki: $expected"
    [[ ! -r /sys/module/$MODULE_NAME/parameters/debug ||
       $(</sys/module/"$MODULE_NAME"/parameters/debug) == 0 ]] ||
        die "Moduł ma włączone debugowanie."
    [[ ! -r /sys/module/$MODULE_NAME/parameters/enable_wt ||
       $(</sys/module/"$MODULE_NAME"/parameters/enable_wt) == N ]] ||
        die "WT powinno pozostać wyłączone."
    log "Moduł działa z $(modinfo -F filename "$MODULE_NAME")"
}
