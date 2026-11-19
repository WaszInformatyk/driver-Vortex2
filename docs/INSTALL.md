# Instalacja, aktualizacje i rollback

## 1. Przed rozpoczęciem

- Wykonaj kopię ważnych danych i zapisz pracę.
- Karta musi być AU8830: PCI `12eb:0002`. Inne Vortex nie są obsługiwane.
- Pakiet jest testowany na x86_64. Nie zmienia IOMMU ani Secure Boot.
- Instalacja wymaga root; `--check` działa także bez root.
- Nie usuwaj modułu in-tree. Stanowi on zabezpieczenie przy rollbacku.

## 2. Kontrola przed instalacją

```bash
./scripts/install.sh --check
```

Kontrola obejmuje kartę i aktualny driver PCI, architekturę, narzędzia,
nagłówki jądra, wymagane opcje `CONFIG_SND*`, `CONFIG_GAMEPORT`, Secure Boot,
status DKMS oraz `debug`/`enable_wt` załadowanego modułu.

Brak karty przerywa instalację. Świadoma kompilacja na inną maszynę jest możliwa
przez `VORTEX_ALLOW_NO_HARDWARE=1`, ale nie daje możliwości testu audio.

## 3. Zależności

Podstawowe pakiety Debian/Mint/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install build-essential dkms kmod pciutils linux-headers-$(uname -r)
```

Można zastąpić to jedną opcją `--install-deps`; jest ona wykonywana tylko na
wyraźne żądanie. Dla innych dystrybucji instalator wypisuje brakujące narzędzia,
ale nie instaluje ich automatycznie. Wymagane są także `make`, GCC, `dkms`,
`modprobe`, `modinfo` i `lspci` oraz nagłówki dla każdego jądra docelowego.

## 4. Instalacja dla uruchomionego jądra

```bash
sudo ./scripts/install.sh
sudo systemctl reboot
```

Instalator wykonuje `dkms add` (z `--force` przy ponownym użyciu), wymusza build
i install, a następnie `depmod -a`. Moduł trafia do `updates/dkms`, które ma
pierwszeństwo przed `kernel/` w typowej konfiguracji Ubuntu/Mint.

Sprawdzenie:

```bash
dkms status vortex2-au8830/0.1.0
modinfo snd_au8830 | grep -E 'filename|vermagic|debug|enable_wt'
./scripts/install.sh --check
```

Po restarcie `filename` powinno wskazywać `updates/dkms`, `debug=0` i
`enable_wt=N`.

## 5. Bezpieczne `--load`

Przeładowanie nie jest wykonywane automatycznie. Przed `--load` zatrzymaj audio:

```bash
systemctl --user stop pipewire-pulse.socket pipewire.socket \
  wireplumber.service pipewire-pulse.service pipewire.service
sudo ./scripts/install.sh --load
systemctl --user start pipewire.socket pipewire-pulse.socket \
  pipewire.service pipewire-pulse.service wireplumber.service
```

Skrypt odmówi działania przy aktywnym PCM lub procesach audio. `modprobe`
rozwiązuje zależności automatycznie; nie używaj ręcznego `insmod` bez wcześniejszego
załadowania zależności.

## 6. Reinstalacja i aktualizacje jądra

Normalnie DKMS przebudowuje moduł po instalacji nowego jądra. Gdy trzeba
wymusić naprawę:

```bash
sudo ./scripts/install.sh --reinstall
```

Dla konkretnej wersji i dla wszystkich dostępnych nagłówków:

```bash
sudo ./scripts/install.sh --reinstall --kernel 7.0.0-42-generic
sudo ./scripts/install.sh --reinstall --all-kernels
```

`--all-kernels` przeszukuje `/lib/modules/*/build`; nie pobiera brakujących
nagłówków samodzielnie. `--install-deps` instaluje nagłówki tylko dla
uruchomionego jądra. Reinstall usuwa poprzedni build wybranego jądra, odświeża
źródło i wymusza kompilację. Moduł aktualnie znajdujący się w pamięci nie jest
przeładowywany bez `--load`.

Źródło ma warstwę zgodności dla API PCI i `strscpy` z serii 6.x i 7.x. W testach
przeszło kompilację dla wszystkich znalezionych nagłówków 6.8 i 7.0.

Logi DKMS znajdują się w:
`/var/lib/dkms/vortex2-au8830/0.1.0/build/make.log`.

## 7. Secure Boot

DKMS podpisuje moduł, jeśli ma skonfigurowany klucz MOK. Instalator nie wyłącza
Secure Boot. Jeśli jest on włączony i brakuje klucza, wyświetli ostrzeżenie.
Skonfiguruj podpis/rejestrację klucza zgodnie z dokumentacją dystrybucji przed
`--load` lub restartem. Nie omijaj walidacji podpisu.

## 8. Rollback

```bash
sudo ./scripts/uninstall.sh
sudo systemctl reboot
```

Alternatywnie, po zatrzymaniu audio:

```bash
sudo ./scripts/uninstall.sh --load
```

Usuwany jest tylko `vortex2-au8830/0.1.0`. Oryginalny moduł in-tree pozostaje
i jest ponownie wybierany przez `depmod`.

## 9. Typowe problemy

- **Brak nagłówków:** zainstaluj `linux-headers-$(uname -r)` i powtórz `--check`.
- **Unknown symbol:** używaj `modprobe`, nie samodzielnego `insmod`; sprawdź
  `CONFIG_SND_AC97_CODEC`, `CONFIG_SND_MPU401_UART` i `CONFIG_GAMEPORT`.
- **Różna wersja `make kernelrelease`:** pakiet używa
  `include/config/kernel.release`; nie zmieniaj jej ręcznie.
- **Moduł nie ładuje się po restarcie:** sprawdź `dkms status`, `modinfo` i
  `modprobe --show-depends snd_au8830`, a następnie wykonaj `--reinstall`.
- **Błędy `IO_PAGE_FAULT`/`IRQ fifo error`:** przerwij test, zachowaj `dmesg`
  i wyniki. Nie wyłączaj IOMMU jako „naprawy”.
- **Brak dźwięku:** wybierz profil `output:analog-stereo` karty i właściwy sink.
  Testy znajdują sink automatycznie lub przyjmują `PIPEWIRE_SINK`.
- **WT jest potrzebne:** ten pakiet go nie naprawia. `enable_wt=1` jest tylko dla
  eksperymentów i nie należy do konfiguracji produkcyjnej.
