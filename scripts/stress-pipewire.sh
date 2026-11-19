#!/usr/bin/env bash
# Repeated PipeWire playback with new-kernel-log checks. Default audio is muted.
set -uo pipefail
export LC_ALL=C

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test-common.sh
source "$SCRIPT_DIR/test-common.sh"
MODE=${1:-dual}
DURATION=${DURATION:-300}
VOLUME=${VOLUME:-0}
SINK=${PIPEWIRE_SINK:-$(vortex_default_sink || true)}
WAV="$ROOT_DIR/tests/test-tone.wav"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$ROOT_DIR/results/pipewire-stress-$MODE-$STAMP"
PIDS=()
ITERATION=0
FAILURES=0
FINAL_RC=0

if [[ "$MODE" != single && "$MODE" != dual ]]; then
    echo "Użycie: DURATION=sekundy VOLUME=0..65536 $0 single|dual" >&2
    exit 2
fi
if [[ ! "$DURATION" =~ ^[0-9]+$ || $DURATION -lt 1 || $DURATION -gt 86400 ||
      ! "$VOLUME" =~ ^[0-9]+$ || $VOLUME -gt 65536 ]]; then
    echo "Nieprawidłowy DURATION (1..86400) lub VOLUME (0..65536)" >&2
    exit 2
fi
command -v paplay >/dev/null || { echo "Brak paplay" >&2; exit 1; }
[[ -r "$WAV" ]] || { echo "Brak $WAV" >&2; exit 1; }
if pgrep -x obs >/dev/null; then
    echo "OBS działa; przerwij test." >&2
    exit 1
fi
if ! pactl info >/dev/null 2>&1; then
    echo "Serwer PipeWire-Pulse nie odpowiada." >&2
    exit 1
fi
if ! pactl list short sinks | awk '{print $2}' | grep -Fxq "$SINK"; then
    echo "Sink nie istnieje: $SINK" >&2
    exit 1
fi
if pactl list short sink-inputs | grep -q .; then
    echo "Istnieją już strumienie; nie uruchamiam równoległego stress testu." >&2
    exit 1
fi

mkdir -p -- "$OUT"
START=$(date +%s)
START_ISO=$(date -Is)
printf 'start=%s\nduration=%s\nmode=%s\nvolume=%s\nsink=%s\n' \
    "$START_ISO" "$DURATION" "$MODE" "$VOLUME" "$SINK" >"$OUT/config.txt"
modinfo snd_au8830 >"$OUT/module.txt" 2>&1
MODULE_PATH=$(modinfo -F filename snd_au8830)
sha256sum -- "$MODULE_PATH" >"$OUT/module.sha256"
cat /proc/interrupts >"$OUT/interrupts-before.txt"
dmesg >"$OUT/dmesg-before.txt"
BASE_LINES=$(wc -l <"$OUT/dmesg-before.txt")

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
    END=$(date +%s)
    printf 'iterations=%s\nfailures=%s\nelapsed_seconds=%s\nresult=%s\n' \
        "$ITERATION" "$FAILURES" "$((END - START))" "$FINAL_RC" >"$OUT/results.txt"
}
trap cleanup EXIT
trap 'FINAL_RC=130; exit 130' INT
trap 'FINAL_RC=143; exit 143' TERM

while (( $(date +%s) - START < DURATION )); do
    ITERATION=$((ITERATION + 1))
    PIDS=()
    timeout --signal=TERM --kill-after=2s 15s \
        paplay --device="$SINK" --volume="$VOLUME" "$WAV" \
        >"$OUT/paplay-0.log" 2>&1 &
    PIDS+=("$!")
    if [[ "$MODE" == dual ]]; then
        sleep 1
        timeout --signal=TERM --kill-after=2s 15s \
            paplay --device="$SINK" --volume="$VOLUME" "$WAV" \
            >"$OUT/paplay-1.log" 2>&1 &
        PIDS+=("$!")
        wait "${PIDS[1]}"
        RC1=$?
    else
        RC1=0
    fi
    wait "${PIDS[0]}"
    RC0=$?
    printf 'iteration=%s paplay0=%s paplay1=%s\n' "$ITERATION" "$RC0" "$RC1" >>"$OUT/iterations.txt"
    if (( RC0 != 0 || RC1 != 0 )); then
        FAILURES=$((FAILURES + 1))
        FINAL_RC=1
        cp "$OUT/paplay-0.log" "$OUT/failure-0-$ITERATION.log"
        [[ "$MODE" == dual ]] && cp "$OUT/paplay-1.log" "$OUT/failure-1-$ITERATION.log"
        break
    fi

    dmesg >"$OUT/dmesg-current.txt"
    CURRENT_LINES=$(wc -l <"$OUT/dmesg-current.txt")
    if (( CURRENT_LINES < BASE_LINES )); then
        echo "Bufor dmesg został zawinięty; pomijam jedno porównanie." >>"$OUT/warnings.txt"
        BASE_LINES=$CURRENT_LINES
        continue
    fi
    tail -n "+$((BASE_LINES + 1))" "$OUT/dmesg-current.txt" >"$OUT/new-kernel-lines.txt"
    if grep -E -i 'IO_PAGE_FAULT|IRQ fifo|IRQ dma|BUG:|Oops|underrun|XRUN' \
        "$OUT/new-kernel-lines.txt" >>"$OUT/kernel-errors.txt"; then
        FAILURES=$((FAILURES + 1))
        FINAL_RC=98
        break
    fi
    BASE_LINES=$CURRENT_LINES
    if (( ITERATION % 10 == 0 )); then
        printf 'iteracja %s, czas %ss\n' "$ITERATION" "$(($(date +%s) - START))"
    fi
done

END=$(date +%s)
printf 'iterations=%s\nfailures=%s\nelapsed_seconds=%s\nresult=%s\n' \
    "$ITERATION" "$FAILURES" "$((END - START))" "$FINAL_RC" >"$OUT/results.txt"
cat "$OUT/results.txt"
echo "Wyniki: $OUT"
exit "$FINAL_RC"
