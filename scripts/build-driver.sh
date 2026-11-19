#!/usr/bin/env bash
# Build the external AU8830 module without installing or loading it.
set -euo pipefail
export LC_ALL=C

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRIVER_DIR="$ROOT_DIR/driver"
KDIR=${KDIR:-/lib/modules/$(uname -r)/build}
JOBS=${JOBS:-$(nproc)}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RESULT_DIR="$ROOT_DIR/results/build-$STAMP"

[[ -d "$DRIVER_DIR" ]] || { echo "Brak katalogu: $DRIVER_DIR" >&2; exit 1; }
[[ -f "$DRIVER_DIR/au8830.c" ]] || { echo "Brak źródeł AU8830" >&2; exit 1; }
[[ -d "$KDIR" ]] || { echo "Brak nagłówków jądra: $KDIR" >&2; exit 1; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "JOBS musi być liczbą dodatnią" >&2; exit 1; }

mkdir -p -- "$RESULT_DIR"
exec > >(tee "$RESULT_DIR/build.log") 2>&1

# Ubuntu header packages can have a different SUBLEVEL in the top-level
# Makefile.  The generated release file is what controls module vermagic.
RELEASE_FILE="$KDIR/include/config/kernel.release"
if [[ -r "$RELEASE_FILE" ]]; then
    TARGET_RELEASE=$(<"$RELEASE_FILE")
else
    TARGET_RELEASE=$(make -s -C "$KDIR" kernelrelease)
fi
CURRENT_RELEASE=$(uname -r)
if [[ "$TARGET_RELEASE" != "$CURRENT_RELEASE" && ${ALLOW_OTHER_KERNEL:-0} != 1 ]]; then
    echo "KDIR dotyczy $TARGET_RELEASE, a uruchomione jest $CURRENT_RELEASE." >&2
    echo "Dla świadomej kompilacji na inne jądro ustaw ALLOW_OTHER_KERNEL=1." >&2
    exit 1
fi

echo "Katalog źródeł: $DRIVER_DIR"
echo "Nagłówki:       $KDIR"
echo "Jądro docelowe: $TARGET_RELEASE"
echo "Zadania make:   $JOBS"

make -C "$KDIR" M="$DRIVER_DIR" clean
make -C "$KDIR" M="$DRIVER_DIR" -j"$JOBS" W=1 modules

MODULE="$DRIVER_DIR/snd-au8830.ko"
[[ -s "$MODULE" ]] || { echo "Nie utworzono modułu $MODULE" >&2; exit 1; }

modinfo "$MODULE"
sha256sum -- "$MODULE" | tee "$RESULT_DIR/module.sha256"
cp -- "$MODULE" "$RESULT_DIR/snd-au8830.ko"

echo "Kompilacja zakończona. Moduł NIE został zainstalowany ani załadowany."
echo "Wynik: $RESULT_DIR"
