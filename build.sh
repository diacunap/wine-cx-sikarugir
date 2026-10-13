#!/bin/bash
# Builds a Sikarugir engine from the official CrossOver sources. Re-runnable: finished steps
# are skipped. Logs go to build/logs/.
#
# Usage: ./build.sh            full build -> dist/<engine>.tar.xz
#        ./build.sh --clean    remove build/ (keeps downloads/ and dist/)
set -euo pipefail
source "$(dirname "$0")/config.sh"

if [ "${1:-}" = "--clean" ]; then rm -rf "$ROOT/build" "$SOURCES"; echo "cleaned"; exit 0; fi

mkdir -p "$LOGS"
step() { printf '\n==> %s\n' "$*"; }
run() { # name command...
    local name="$1"; shift
    local t0=$SECONDS
    if ! "$@" > "$LOGS/$name.log" 2>&1; then
        echo "FAILED: $name (log: $LOGS/$name.log)" >&2
        tail -25 "$LOGS/$name.log" >&2
        exit 1
    fi
    echo "   ok ($(( (SECONDS - t0) / 60 )) min)"
}

step "checking prerequisites"
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || { echo "Apple Silicon Mac only" >&2; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "install Command Line Tools: xcode-select --install" >&2; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required (https://brew.sh)" >&2; exit 1; }
missing=""
for f in mingw-w64 bison flex ninja cmake pkgconf autoconf automake libtool llvm lld nasm freetype; do
    brew list --versions "$f" >/dev/null 2>&1 || missing="$missing $f"
done
[ -z "$missing" ] || { echo "missing Homebrew packages, run:  brew install$missing" >&2; exit 1; }
arch -x86_64 /usr/bin/true 2>/dev/null || echo "note: Rosetta not installed; build works, final test is skipped"
free_gb=$(df -g "$ROOT" | awk 'NR==2{print $4}')
echo "   free disk: ${free_gb} GB (build peaks around 12-15 GB)"
[ "$free_gb" -ge "${MIN_FREE_GB:-15}" ] || { echo "need at least ${MIN_FREE_GB:-15} GB free" >&2; exit 1; }
echo "   building $ENGINE_NAME from CrossOver $CX_VERSION with $JOBS jobs"

step "1/4 CrossOver $CX_VERSION sources (download + verify + extract)"
run sources "$ROOT/scripts/fetch-sources.sh"

step "2/4 x86_64 host libraries (gmp, nettle, gnutls, freetype, SDL2, MoltenVK, FFmpeg)"
if [ -f "$DEPS/lib/libavcodec.dylib" ] || ls "$DEPS"/lib/libavcodec.*.dylib >/dev/null 2>&1; then
    echo "   already built"
else
    run deps "$ROOT/scripts/build-deps.sh"
fi

step "3/4 Wine (the long one)"
run wine "$ROOT/scripts/build-wine.sh"

step "4/4 packaging Sikarugir engine"
run package "$ROOT/scripts/package-engine.sh"
tail -3 "$LOGS/package.log"

printf '\nDone. Install it with:  ./scripts/install-engine.sh\n'
