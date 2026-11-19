#!/usr/bin/env bash
# Test one or two application streams through PipeWire/PulseAudio compatibility.
set -uo pipefail
export LC_ALL=C

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test-common.sh
source "$SCRIPT_DIR/test-common.sh"
MODE=${1:-single}
SINK=${PIPEWIRE_SINK:-$(vortex_default_sink || true)}
WAV="$ROOT_DIR/tests/test-tone.wav"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$ROOT_DIR/results/pipewire-$MODE-$STAMP"
PIDS=()

if [[ "$MODE" != single && "$MODE" != dual ]]; then
    echo "Użycie: $0 single|dual" >&2
    exit 2
fi
command -v paplay >/dev/null || { echo "Brak paplay" >&2; exit 1; }
[[ -r "$WAV" ]] || { echo "Brak $WAV" >&2; exit 1; }
if pgrep -x obs >/dev/null; then
    echo "OBS działa. Zakończ nagrywanie przed testem." >&2
    exit 1
fi
if ! pactl info >/dev/null 2>&1; then
    echo "Serwer PipeWire-Pulse nie odpowiada." >&2
    exit 1
fi
if ! pactl list short sinks | awk '{print $2}' | grep -Fxq "$SINK"; then
    echo "Sink nie istnieje: $SINK" >&2
    pactl list short sinks >&2
    exit 1
fi

mkdir -p -- "$OUT"
uname -a >"$OUT/uname.txt"
pactl info >"$OUT/server-info.txt" 2>&1
pactl list cards >"$OUT/cards.txt" 2>&1
pactl list short sinks >"$OUT/sinks.txt" 2>&1
modinfo snd_au8830 >"$OUT/module.txt" 2>&1
MODULE_PATH=$(modinfo -F filename snd_au8830)
printf 'mode=%s\nsink=%s\n' "$MODE" "$SINK" >"$OUT/test-config.txt"
sha256sum -- "$MODULE_PATH" >"$OUT/module.sha256" 2>&1
cat /proc/interrupts >"$OUT/interrupts-before.txt"
dmesg >"$OUT/dmesg-before.txt" 2>&1

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

run_paplay() {
    local log=$1
    timeout --signal=TERM --kill-after=2s 15s \
        paplay --device="$SINK" "$WAV" >"$log" 2>&1 &
    PIDS+=("$!")
}

run_paplay "$OUT/paplay-0.log"
RC0=0
if [[ "$MODE" == dual ]]; then
    sleep 1
    run_paplay "$OUT/paplay-1.log"
    wait "${PIDS[1]}"
    RC1=$?
else
    RC1=0
fi
wait "${PIDS[0]}" || RC0=$?
printf 'paplay0=%s\npaplay1=%s\n' "$RC0" "${RC1:-0}" >"$OUT/results.txt"
cat "$OUT/results.txt"
echo "Wyniki: $OUT"
[[ $RC0 -eq 0 && ${RC1:-0} -eq 0 ]]
