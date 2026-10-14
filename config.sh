# shellcheck shell=bash disable=SC2034
# Single place to bump versions. Sourced by every script.
# To move to a new CrossOver release: change CX_VERSION and CX_SHA256, bump ENGINE_REV to 1.

CX_VERSION=26.3.0
CX_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VERSION}.tar.gz"

# Engine revision for this CX_VERSION (bump when you rebuild with changes, same CX version).
ENGINE_REV=4

# Sikarugir engine naming: WS12Wine<Name>.tar.xz (WS12 = Wineskin 12 wrapper format).
ENGINE_NAME="WS12WineCX${CX_VERSION%.0}_${ENGINE_REV}"

# Wine Mono / Gecko versions the CX 26.3 tree expects (dlls/appwiz.cpl/addons.c).
MONO_VERSION=10.4.1
MONO_SHA256=a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb
GECKO_VERSION=2.47.4
GECKO_X86_SHA256=2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6
GECKO_X64_SHA256=fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814

export MACOSX_DEPLOYMENT_TARGET=14.0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DL="$ROOT/downloads"
SOURCES="$ROOT/sources"          # extracted CX drop: $SOURCES/sources/{wine,gnutls,freetype}
DEPS="$ROOT/build/deps"          # x86_64 host libraries
TOOLS="$ROOT/build/wine-tools"   # native arm64 winebuild/widl/wrc...
WBUILD="$ROOT/build/wine-x86_64"
INSTALL="$ROOT/build/wine-install"
DIST="$ROOT/dist"
LOGS="$ROOT/build/logs"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}"

fetch() { # url sha256 out-file-name
    local url="$1" sum="$2" out="$DL/$3"
    mkdir -p "$DL"
    if [ ! -f "$out" ]; then
        curl -fSL --retry 3 -o "$out.part" "$url"
        mv "$out.part" "$out"
    fi
    echo "$sum  $out" | shasum -a 256 -c - >/dev/null || { echo "checksum mismatch: $out" >&2; rm -f "$out"; return 1; }
}
