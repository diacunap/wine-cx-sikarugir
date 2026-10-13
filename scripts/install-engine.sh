#!/bin/bash
# Copies dist/<ENGINE_NAME>.tar.xz into Sikarugir's engines folder so Creator/Configure list it.
set -euo pipefail
source "$(dirname "$0")/../config.sh"

SRC_ENGINE="$DIST/$ENGINE_NAME.tar.xz"
[ -f "$SRC_ENGINE" ] || { echo "no $SRC_ENGINE, run ./build.sh first" >&2; exit 1; }

ENGINES="${SIKARUGIR_ENGINES:-$HOME/Library/Application Support/Sikarugir/Engines}"
if [ ! -d "$ENGINES" ]; then
    echo "Engines folder not found: $ENGINES" >&2
    echo "Open Sikarugir Creator once (it creates it), or set SIKARUGIR_ENGINES=/path." >&2
    exit 1
fi
echo "existing engines in $ENGINES:"
ls -1 "$ENGINES" | sed 's/^/  /'
cp "$SRC_ENGINE" "$ENGINES/"
xattr -c "$ENGINES/$ENGINE_NAME.tar.xz" 2>/dev/null || true
echo "installed $ENGINE_NAME -> $ENGINES"
echo "Next: Sikarugir Creator -> Change engine -> $ENGINE_NAME (or Configure -> Tools -> Change Engine)."
