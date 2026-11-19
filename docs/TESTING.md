# Testowanie AU8830

## Bezpieczeństwo

Zapisz pracę, zakończ OBS i inne odtwarzanie. Testy zapisują konfigurację,
hash modułu, IRQ i `dmesg` w `results/`. Przy nowym `IO_PAGE_FAULT`, błędzie
FIFO/DMA, oops lub zawieszeniu przerwij test; nie zwiększaj czasu ani liczby
strumieni.

## PipeWire

Włącz profil `output:analog-stereo` dla karty i wykonaj:

```bash
./scripts/run-pipewire-test.sh single
./scripts/run-pipewire-test.sh dual
```

Skrypt wykrywa AU8830 po `12eb:0002` i znajduje sink automatycznie. Można go
nadpisać:

```bash
PIPEWIRE_SINK=alsa_output.pci-XXXX_XX_XX_X.analog-stereo \
  ./scripts/run-pipewire-test.sh dual
```

Oczekiwane są kody `paplay0=0`, `paplay1=0` i pusty `dmesg.diff`.

## Test długi

```bash
DURATION=1800 VOLUME=0 ./scripts/stress-pipewire.sh dual
```

`VOLUME=0` wycisza odsłuch, ale DMA nadal pracuje. Test zatrzymuje się przy
błędzie procesu lub nowym błędzie jądra. Zakres czasu to 1..86400 s.

## Bezpośrednia ALSA

Najpierw zatrzymaj PipeWire/WirePlumber, aby zwolnić urządzenie:

```bash
systemctl --user stop pipewire-pulse.socket pipewire.socket \
  wireplumber.service pipewire-pulse.service pipewire.service
./scripts/run-pcm-test.sh single
```

Skrypt sam znajduje indeks karty AU8830. Domyślnie używa S16_LE, stereo, 48 kHz,
okresu 1024 ramek i czterech okresów. Test dwóch subdevice:

```bash
./scripts/run-pcm-test.sh dual
```

Parametry można zmienić przez `PERIOD_FRAMES`, `BUFFER_FRAMES`, `SAMPLE_RATE`,
`CHANNELS` i `WAV_PATH`, np.:

```bash
PERIOD_FRAMES=256 BUFFER_FRAMES=16384 ./scripts/run-pcm-test.sh single
```

Po testach przywróć usługi:

```bash
systemctl --user start pipewire.socket pipewire-pulse.socket \
  pipewire.service pipewire-pulse.service wireplumber.service
```

## Ton testowy

`tests/test-tone.wav` to 5 s stereo 48 kHz/16-bit, dwa tony 440/660 Hz z
obwiednią 20 ms i poziomem około −20 dBFS. Można go odtworzyć przez
`tests/generate-tone.py`; wymaga tylko Pythona 3 z biblioteką standardową.
