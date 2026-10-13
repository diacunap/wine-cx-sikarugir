#!/bin/bash
# Downloads the official CrossOver source drop (LGPL, published by CodeWeavers), verifies it,
# and extracts only what we build: wine, gnutls (+gmp), freetype. Then applies patches/*.patch
# to the wine tree (see patches/ for why each one exists).
set -euo pipefail
source "$(dirname "$0")/../config.sh"

fetch "$CX_URL" "$CX_SHA256" "crossover-sources-${CX_VERSION}.tar.gz"

if [ -f "$SOURCES/.extracted-$CX_VERSION" ]; then
    echo "sources for CX $CX_VERSION already extracted"
    exit 0
fi
rm -rf "$SOURCES"
mkdir -p "$SOURCES"
tar -xzf "$DL/crossover-sources-${CX_VERSION}.tar.gz" -C "$SOURCES" \
    sources/wine sources/gnutls sources/freetype
grep -q "Wine version" "$SOURCES/sources/wine/VERSION"
for p in "$ROOT"/patches/*.patch; do
    [ -e "$p" ] || continue
    echo "applying $(basename "$p")"
    patch -d "$SOURCES/sources/wine" -p1 -N -f -s -i "$p" < /dev/null
done
touch "$SOURCES/.extracted-$CX_VERSION"
echo "extracted: $(cat "$SOURCES/sources/wine/VERSION") from CrossOver $CX_VERSION"
