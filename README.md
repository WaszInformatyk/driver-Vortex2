# Vortex 2 AU8830 — naprawiony sterownik Linux/DKMS

Stabilny, dynamicznie ładowany sterownik dla **Aureal Vortex 2 AU8830**
(PCI `12eb:0002`), w tym Diamond Monster Sound II / Monster Sound MX300.
Pakiet zabezpiecza odczyt poza bufor DMA przy zawinięciu pierścienia i domyślnie
wyłącza niedziałający, eksperymentalny PCM WT.

## Co zostało przetestowane

- Linux Mint 22.2, x86_64, jądro `7.0.0-42-generic`, AMD IOMMU włączone.
- Odtwarzanie analogowe ADB przez ALSA i PipeWire, jeden i dwa strumienie.
- 244 dwustreamowe iteracje przez 1803 s bez błędów procesów i jądra.
- 22050/32000/44100/48000 Hz, mono i stereo, różne rozmiary okresów.
- Automatyczne załadowanie DKMS i ponowne testy po pełnym restarcie.
- Kompilacja dla nagłówków `7.0.0-31/-34/-38/-42` oraz
  `6.8.0-124/-139/-142/-146/-149`.

Nie jest to sterownik dla AU8810 ani AU8820. WT pozostaje wyłączone. S/PDIF,
A3D i nagrywanie nie przeszły tak szerokiej macierzy jak analogowe odtwarzanie.

## Szybka instalacja (Debian, Ubuntu, Linux Mint)

Najpierw wykonaj kopię ważnych danych i sprawdź wykrycie:

```bash
./scripts/install.sh --check
```

Następnie:

```bash
sudo ./scripts/install.sh --install-deps
sudo systemctl reboot
```

`--install-deps` jest opcjonalne i wykonuje `apt-get update/install`. Jeśli
zależności już istnieją, użyj samego `sudo ./scripts/install.sh`.
Domyślnie instalator **nie przeładowuje sterownika ani nie zatrzymuje audio**;
restart jest najprostszym sposobem aktywacji DKMS.

## Po aktualizacji jądra

DKMS ma `AUTOINSTALL=yes` i powinien przebudować moduł automatycznie. Sprawdź:

```bash
dkms status vortex2-au8830/0.1.0
./scripts/install.sh --check
```

Jeśli aktualizacja zmieniła ABI albo build nie powiódł się:

```bash
# Napraw tylko dla uruchomionego jądra:
sudo ./scripts/install.sh --reinstall

# Albo dla wszystkich znalezionych nagłówków:
sudo ./scripts/install.sh --reinstall --all-kernels
```

Reinstall odświeża źródło w DKMS, wymusza build/install i nie wyładowuje modułu
z pamięci. Nie nadpisuje oryginalnego sterownika in-tree.

## Bezpieczne przeładowanie bez restartu

Zakończ odtwarzanie i zatrzymaj usługi audio użytkownika:

```bash
systemctl --user stop pipewire-pulse.socket pipewire.socket \
  wireplumber.service pipewire-pulse.service pipewire.service
sudo ./scripts/install.sh --load
systemctl --user start pipewire.socket pipewire-pulse.socket \
  pipewire.service pipewire-pulse.service wireplumber.service
```

`--load` jest odrzucane przy aktywnym PCM, OBS lub działających usługach audio.
Pełna instrukcja: **[docs/INSTALL.md](docs/INSTALL.md)**.

## Test po instalacji

Po włączeniu profilu analogowego karty:

```bash
./scripts/run-pipewire-test.sh single
./scripts/run-pipewire-test.sh dual
```

Testy same wykrywają kartę `12eb:0002` i sink. Można nadpisać sink przez
`PIPEWIRE_SINK`. Test długi (domyślnie wyciszony):

```bash
DURATION=300 VOLUME=0 ./scripts/stress-pipewire.sh dual
```

Szczegóły i test bezpośredniej ALSA: **[docs/TESTING.md](docs/TESTING.md)**.

## Odinstalowanie

```bash
sudo ./scripts/uninstall.sh
# Po zatrzymaniu audio można też od razu przywrócić in-tree:
sudo ./scripts/uninstall.sh --load
```

Oryginalny moduł w `kernel/sound/pci/au88x0` nie jest usuwany.

## Zawartość

- `driver/` — źródła AU8830 i zewnętrzny Makefile.
- `dkms.conf` — budowa i automatyczna rekompilacja DKMS.
- `scripts/install.sh` — wykrywanie, instalacja i naprawa.
- `scripts/uninstall.sh` — rollback.
- `scripts/common.sh` — kontrola sprzętu, PCM, Secure Boot i ładowania.
- `scripts/test-common.sh` — wykrywanie karty ALSA i sink PipeWire.
- `tests/` — niezależny, 5-sekundowy ton testowy i generator.
- `docs/` — instalacja i testowanie.

## Licencja

Kod sterownika: **GPL-2.0-only**; zobacz `LICENSE` i `NOTICE.md`.
Nie zawiera binariów Windows ani innych materiałów zastrzeżonych. Ton testowy
jest oznaczony jako CC0.
