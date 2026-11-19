#!/usr/bin/env bash
# Locate the first AU8830 ALSA card and its PipeWire analog stereo sink.

vortex_alsa_card() {
    local bdf carddir
    bdf=$(lspci -Dnn -d 12eb:0002 2>/dev/null | awk 'NR == 1 {print $1}')
    [[ -n "$bdf" ]] || return 1
    for carddir in "/sys/bus/pci/devices/$bdf/sound"/card*; do
        [[ -d "$carddir" ]] || continue
        basename "$carddir"
        return 0
    done
    return 1
}

vortex_default_sink() {
    local card
    card=$(pactl list cards 2>/dev/null | awk '
        /^[[:space:]]*(Name|Nazwa):[[:space:]]+alsa_card\./ { name = $2 }
        /device\.vendor\.id[[:space:]]*=[[:space:]]*"0x12eb"/ {
            print name
            exit
        }')
    [[ -n "$card" ]] || return 1
    printf 'alsa_output.%s.analog-stereo\n' "${card#alsa_card.}"
}
