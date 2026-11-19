#!/usr/bin/env bash
# Direct-ALSA playback test. Usage: run-pcm-test.sh single|dual
set -uo pipefail
export LC_ALL=C

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test-common.sh
source "$SCRIPT_DIR/test-common.sh"
ALSA_CARD=$(vortex_alsa_card) || {
    echo "Nie znaleziono karty ALSA AU8830" >&2
    exit 1
}
MODE=${1:-single}
PERIOD_FRAMES=${PERIOD_FRAMES:-1024}
BUFFER_FRAMES=${BUFFER_FRAMES:-4096}
WAV=${WAV_PATH:-$ROOT_DIR/tests/test-tone.wav}
SAMPLE_RATE=${SAMPLE_RATE:-48000}
CHANNELS=${CHANNELS:-2}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$ROOT_DIR/results/pcm-$MODE-$STAMP"
PIDS=()

if [[ "$MODE" != single && "$MODE" != dual ]]; then
    echo "Użycie: $0 single|dual" >&2
    exit 2
fi
if [[ ! "$PERIOD_FRAMES" =~ ^[1-9][0-9]*$ ||
      ! "$BUFFER_FRAMES" =~ ^[1-9][0-9]*$ ]]; then
    echo "PERIOD_FRAMES i BUFFER_FRAMES muszą być liczbami dodatnimi" >&2
    exit 2
fi
if (( (PERIOD_FRAMES & (PERIOD_FRAMES - 1)) != 0 ||
      BUFFER_FRAMES < PERIOD_FRAMES * 2 ||
      BUFFER_FRAMES % PERIOD_FRAMES != 0 ||
      BUFFER_FRAMES / PERIOD_FRAMES > 1024 )); then
    echo "Okres musi być potęgą 2; bufor: 2..1024 całkowite okresy" >&2
    exit 2
fi
PERIODS=$((BUFFER_FRAMES / PERIOD_FRAMES))
if [[ ! "$SAMPLE_RATE" =~ ^[0-9]+$ || $SAMPLE_RATE -lt 5000 || $SAMPLE_RATE -gt 48000 ]]; then
    echo "SAMPLE_RATE musi być w zakresie 5000..48000" >&2
    exit 2
fi
if [[ "$CHANNELS" != 1 && "$CHANNELS" != 2 ]]; then
    echo "CHANNELS musi wynosić 1 lub 2" >&2
    exit 2
fi
[[ -r "$WAV" ]] || { echo "Brak $WAV" >&2; exit 1; }
command -v aplay >/dev/null || { echo "Brak aplay" >&2; exit 1; }
if pgrep -x obs >/dev/null; then
    echo "OBS działa. Zakończ nagrywanie przed testem." >&2
    exit 1
fi
if ps -eo comm= | grep -E -q '^(pipewire|pipewire-pulse|wireplumber)$'; then
    echo "Test wymaga bezpośredniej ALSA; zatrzymaj PipeWire/WirePlumber." >&2
    exit 1
fi
for status in "/proc/asound/card$ALSA_CARD"/pcm*/sub*/status; do
    [[ -r "$status" ]] || continue
    if [[ $(<"$status") != closed ]]; then
        echo "Aktywny PCM: $status" >&2
        exit 1
    fi
done

mkdir -p -- "$OUT"
uname -a >"$OUT/uname.txt"
modinfo snd_au8830 >"$OUT/module.txt" 2>&1
MODULE_PATH=$(modinfo -F filename snd_au8830)
cat /proc/interrupts >"$OUT/interrupts-before.txt"
dmesg >"$OUT/dmesg-before.txt" 2>&1
cp /proc/asound/cards "$OUT/cards.txt"
printf 'mode=%s\nperiod_frames=%s\nbuffer_frames=%s\nperiods=%s\nsample_rate=%s\nchannels=%s\nwav=%s\n' \
    "$MODE" "$PERIOD_FRAMES" "$BUFFER_FRAMES" "$PERIODS" \
    "$SAMPLE_RATE" "$CHANNELS" "$WAV" >"$OUT/test-config.txt"
sha256sum -- "$MODULE_PATH" >"$OUT/module.sha256" 2>&1

cleanup() {
    local pid
    for pid in "${PIDS[@]:-}"; do
        [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
    done
    for pid in "${PIDS[@]:-}"; do
        [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
    done
    cat /proc/interrupts >"$OUT/interrupts-after.txt" 2>&1
    dmesg >"$OUT/dmesg-after.txt" 2>&1
    diff -u "$OUT/dmesg-before.txt" "$OUT/dmesg-after.txt" >"$OUT/dmesg.diff" || true
}
trap cleanup EXIT INT TERM

run_aplay() {
    local subdevice=$1
    local log=$2
    timeout --signal=TERM --kill-after=2s 15s \
        aplay -v -D "hw:$ALSA_CARD,0,$subdevice" \
        --format=S16_LE --channels="$CHANNELS" --rate="$SAMPLE_RATE" \
        --period-size="$PERIOD_FRAMES" --buffer-size="$BUFFER_FRAMES" "$WAV" \
        >"$log" 2>&1 &
    PIDS+=("$!")
}

run_aplay 0 "$OUT/aplay-0.log"
RC0=0
if [[ "$MODE" == dual ]]; then
    sleep 1
    run_aplay 1 "$OUT/aplay-1.log"
    wait "${PIDS[1]}"
    RC1=$?
else
    RC1=0
fi
wait "${PIDS[0]}" || RC0=$?
printf 'aplay0=%s\naplay1=%s\n' "$RC0" "${RC1:-0}" >"$OUT/results.txt"
cat "$OUT/results.txt"
echo "Wyniki: $OUT"
[[ $RC0 -eq 0 && ${RC1:-0} -eq 0 ]]
