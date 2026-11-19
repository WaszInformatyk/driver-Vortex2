#!/usr/bin/env bash
# Install or repair the AU8830 DKMS module for current or all installed kernels.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ACTION=install
INSTALL_DEPS=0
DO_LOAD=0
ALL_KERNELS=0
KERNEL=$(uname -r)
DKMS_OPTS=()

usage() {
    cat <<'EOF'
Użycie:
  ./scripts/install.sh --check
  sudo ./scripts/install.sh [--install-deps] [--load]
  sudo ./scripts/install.sh --reinstall [--kernel WERSJA | --all-kernels]

Opcje:
  --check          Sprawdź sprzęt, zależności, jądra i moduł bez zmian.
  --reinstall      Usuń i odbuduj moduł dla wybranych jąder.
  --install-deps   Zainstaluj brakujące zależności przez APT.
  --kernel WERSJA  Wybierz jądro (domyślnie uname -r).
  --all-kernels    Zbuduj dla wszystkich /lib/modules/*/build.
  --load           Przeładuj moduł tylko przy zamkniętym PCM i bez usług audio.
EOF
}

while (($#)); do
    case "$1" in
        --check) ACTION=check ;;
        --reinstall) ACTION=reinstall ;;
        --install-deps) INSTALL_DEPS=1 ;;
        --load) DO_LOAD=1 ;;
        --all-kernels) ALL_KERNELS=1 ;;
        --kernel)
            [[ $# -ge 2 ]] || die "--kernel wymaga wersji."
            KERNEL=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "Nieznana opcja: $1" ;;
    esac
    shift
done

if [[ -n ${VORTEX_DKMS_TREE:-} ]]; then
    DKMS_OPTS+=(--dkmstree="$VORTEX_DKMS_TREE")
fi
if [[ -n ${VORTEX_SOURCE_TREE:-} ]]; then
    DKMS_OPTS+=(--sourcetree="$VORTEX_SOURCE_TREE")
fi
if [[ -n ${VORTEX_INSTALL_TREE:-} ]]; then
    DKMS_OPTS+=(--installtree="$VORTEX_INSTALL_TREE")
fi

check_commands() {
    local missing=()
    local cmd
    for cmd in dkms make gcc modprobe modinfo lspci; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ((${#missing[@]})) && ((INSTALL_DEPS)); then
        install_apt_dependencies
        missing=()
        for cmd in dkms make gcc modprobe modinfo lspci; do
            command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
        done
    fi
    ((${#missing[@]} == 0)) || {
        printf '[vortex2] Brak narzędzi: %s\n' "${missing[*]}" >&2
        die "Debian/Mint/Ubuntu: apt-get install build-essential dkms kmod pciutils linux-headers-$(uname -r)"
    }
    log "Wymagane narzędzia są dostępne."
}

install_apt_dependencies() {
    command -v apt-get >/dev/null 2>&1 ||
        die "Automatyczna instalacja zależności jest obsługiwana tylko przez APT."
    log "Instaluję zależności APT (tylko na żądanie --install-deps)."
    apt-get update
    apt-get install -y build-essential dkms kmod pciutils "linux-headers-$(uname -r)"
}

get_kernels() {
    if ((ALL_KERNELS)); then
        local build
        for build in /lib/modules/*/build; do
            [[ -d "$build" ]] || continue
            basename "$(dirname "$build")"
        done | sort -V
    else
        printf '%s\n' "$KERNEL"
    fi
}

check_source() {
    [[ -f "$ROOT_DIR/dkms.conf" && -f "$ROOT_DIR/driver/au8830.c" &&
       -f "$ROOT_DIR/driver/au88x0.h" && -f "$ROOT_DIR/driver/au88x0_pcm.c" ]] ||
        die "Niekompletne źródła w $ROOT_DIR."
}

dkms_add_source() {
    if dkms "${DKMS_OPTS[@]}" status "$PACKAGE_NAME/$PACKAGE_VERSION" 2>/dev/null | grep -q .; then
        dkms "${DKMS_OPTS[@]}" add --force "$ROOT_DIR"
    else
        dkms "${DKMS_OPTS[@]}" add "$ROOT_DIR"
    fi
}

build_kernel() {
    local kernel=$1
    log "Buduję $PACKAGE_NAME/$PACKAGE_VERSION dla $kernel."
    dkms "${DKMS_OPTS[@]}" build "$PACKAGE_NAME/$PACKAGE_VERSION" -k "$kernel" --force
    dkms "${DKMS_OPTS[@]}" install "$PACKAGE_NAME/$PACKAGE_VERSION" -k "$kernel" --force
    depmod -a "$kernel"
}

print_status() {
    log "System: $(uname -m), uruchomione jądro: $(uname -r)"
    require_hardware
    check_commands
    check_secure_boot
    local kernel
    while IFS= read -r kernel; do
        [[ -n "$kernel" ]] && check_kernel "$kernel"
    done < <(get_kernels)
    dkms "${DKMS_OPTS[@]}" status "$PACKAGE_NAME/$PACKAGE_VERSION" 2>/dev/null || true
    if [[ -d /sys/module/$MODULE_NAME ]]; then
        log "Załadowany moduł: $(modinfo -F filename "$MODULE_NAME")"
        [[ ! -r /sys/module/$MODULE_NAME/parameters/debug ]] ||
            log "debug=$(</sys/module/"$MODULE_NAME"/parameters/debug)"
        [[ ! -r /sys/module/$MODULE_NAME/parameters/enable_wt ]] ||
            log "enable_wt=$(</sys/module/"$MODULE_NAME"/parameters/enable_wt)"
    else
        log "Moduł $MODULE_NAME nie jest obecnie załadowany."
    fi
}

# ACTIONS
if [[ "$ACTION" == check ]]; then
    ((DO_LOAD == 0)) || die "--load nie ma sensu z --check."
    check_source
    print_status
    exit 0
fi

require_root
check_source
if ((INSTALL_DEPS)) && [[ ! -d "/lib/modules/$KERNEL/build" ]]; then
    install_apt_dependencies
fi
print_status

kernels=()
mapfile -t kernels < <(get_kernels)
((${#kernels[@]})) || die "Nie znaleziono jąder z nagłówkami."

for kernel in "${kernels[@]}"; do
    [[ -n "$kernel" ]] || continue
    if [[ "$ACTION" == reinstall ]]; then
        if dkms "${DKMS_OPTS[@]}" status "$PACKAGE_NAME/$PACKAGE_VERSION" -k "$kernel" 2>/dev/null | grep -q .; then
            log "Usuwam poprzedni build dla $kernel (moduł w pamięci pozostaje nietknięty)."
            dkms "${DKMS_OPTS[@]}" remove "$PACKAGE_NAME/$PACKAGE_VERSION" -k "$kernel"
        fi
    fi
    dkms_add_source
    build_kernel "$kernel"
done

if ((DO_LOAD)); then
    load_module
else
    log "Instalacja zakończona. Nie przeładowano modułu; wybierz restart lub --load po zatrzymaniu audio."
fi
modinfo -F filename "$MODULE_NAME"
log "Gotowe."
