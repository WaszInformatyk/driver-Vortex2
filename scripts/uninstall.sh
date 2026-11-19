#!/usr/bin/env bash
# Remove only this DKMS package and optionally restore the in-tree driver.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

DO_LOAD=0
case ${1:-} in
    '') ;;
    --load) DO_LOAD=1 ;;
    -h|--help)
        echo "Użycie: sudo $0 [--load]"
        exit 0
        ;;
    *) die "Nieznana opcja: $1" ;;
esac

require_root
if dkms status "$PACKAGE_NAME/$PACKAGE_VERSION" 2>/dev/null | grep -q .; then
    dkms remove "$PACKAGE_NAME/$PACKAGE_VERSION" --all
else
    log "Pakiet $PACKAGE_NAME/$PACKAGE_VERSION nie jest zarejestrowany."
fi
depmod -a "$(uname -r)"

if ((DO_LOAD)); then
    load_module kernel/sound/pci/au88x0
else
    log "DKMS usunięty. Moduł in-tree pozostał; restart przywróci go po przeładowaniu."
fi
modinfo -F filename "$MODULE_NAME"
log "Gotowe."
