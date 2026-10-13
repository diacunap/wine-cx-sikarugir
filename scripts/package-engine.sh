#!/bin/bash
# Packages $INSTALL as a Sikarugir engine: dist/<ENGINE_NAME>.tar.xz containing wswine.bundle/
# with the same layout as the official engines (bin/, lib/wine/, share/wine/{mono,gecko}, version).
# Graphics (D3DMetal, DXMT, DXVK) are NOT included: the Sikarugir wrapper provides them.
set -euo pipefail
source "$(dirname "$0")/../config.sh"

[ -x "$INSTALL/lib/wine/x86_64-unix/wine" ] || { echo "no Wine install, run scripts/build-wine.sh" >&2; exit 1; }

STAGE="$DIST/stage"
B="$STAGE/wswine.bundle"
rm -rf "$STAGE"
mkdir -p "$B/bin" "$B/lib" "$B/share"

# --- Wine ------------------------------------------------------------------------------------
cp -R "$INSTALL/lib/wine" "$B/lib/wine"
cp -R "$INSTALL/share/wine" "$B/share/wine"
# bin/wine must be a symlink: CrossOver's loader (loader/main.c try_dlopen) only looks for
# ntdll.so next to realpath(self), unlike upstream's bindir->libdir lookup the official
# Sikarugir engines rely on. A copied bin/wine fails with "could not load ntdll.so".
ln -s ../lib/wine/x86_64-unix/wine "$B/bin/wine"
for exe in wineserver; do
    for cand in "$INSTALL/bin/$exe" "$INSTALL/lib/wine/x86_64-unix/$exe"; do
        if [ -e "$cand" ]; then cp -L "$cand" "$B/bin/$exe"; break; fi
    done
    [ -x "$B/bin/$exe" ] || { echo "missing $exe in install" >&2; exit 1; }
done

# --- host libraries (rpath @loader_path/../.. from lib/wine/x86_64-unix = wswine.bundle/lib) ---
cp -a "$DEPS"/lib/*.dylib "$B/lib/"
for lib in libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libMoltenVK.dylib; do
    [ -e "$B/lib/$lib" ] || { echo "missing $lib" >&2; exit 1; }
done
if otool -L "$B"/lib/*.dylib "$B"/lib/wine/x86_64-unix/*.so | grep -q "$ROOT/build"; then
    otool -L "$B"/lib/*.dylib "$B"/lib/wine/x86_64-unix/*.so | grep -B3 "$ROOT/build" >&2
    echo "absolute build paths left in binaries" >&2; exit 1
fi

# --- Wine Mono / Gecko (unpacked, like the official engines) ----------------------------------
fetch "https://dl.winehq.org/wine/wine-mono/$MONO_VERSION/wine-mono-$MONO_VERSION-x86.tar.xz" \
    "$MONO_SHA256" "wine-mono-$MONO_VERSION-x86.tar.xz"
fetch "https://dl.winehq.org/wine/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86.tar.xz" \
    "$GECKO_X86_SHA256" "wine-gecko-$GECKO_VERSION-x86.tar.xz"
fetch "https://dl.winehq.org/wine/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86_64.tar.xz" \
    "$GECKO_X64_SHA256" "wine-gecko-$GECKO_VERSION-x86_64.tar.xz"
mkdir -p "$B/share/wine/mono" "$B/share/wine/gecko"
tar -xJf "$DL/wine-mono-$MONO_VERSION-x86.tar.xz" -C "$B/share/wine/mono"
tar -xJf "$DL/wine-gecko-$GECKO_VERSION-x86.tar.xz" -C "$B/share/wine/gecko"
tar -xJf "$DL/wine-gecko-$GECKO_VERSION-x86_64.tar.xz" -C "$B/share/wine/gecko"

# --- version + licences --------------------------------------------------------------------------
echo "WineCX $CX_VERSION (revision $ENGINE_REV)" > "$B/version"
cp "$SOURCES/sources/wine/COPYING.LIB" "$B/share/wine/COPYING.LIB" 2>/dev/null || true

# --- ad-hoc signatures (install_name_tool invalidates them; harmless on x86_64 otherwise) -----
find "$B" -type f \( -name '*.dylib' -o -name '*.so' \) -exec codesign -f -s - {} \; 2>/dev/null
codesign -f -s - "$B/bin/wine" "$B/bin/wineserver" 2>/dev/null || true

# --- sanity -------------------------------------------------------------------------------------
grep -qa WINE_SIMULATE_WRITECOPY "$B/lib/wine/x86_64-unix/ntdll.so"
if arch -x86_64 /usr/bin/true 2>/dev/null; then
    WINEDLLPATH="" "$B/bin/wine" --version || echo "warning: wine --version failed (check Rosetta)" >&2
fi

# --- archive ------------------------------------------------------------------------------------
mkdir -p "$DIST"
OUT="$DIST/$ENGINE_NAME.tar.xz"
rm -f "$OUT"
COPYFILE_DISABLE=1 tar -cJf "$OUT" -C "$STAGE" wswine.bundle
rm -rf "$STAGE"
shasum -a 256 "$OUT" | tee "$OUT.sha256"
du -h "$OUT"
echo "engine: $OUT"
