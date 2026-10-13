#!/bin/bash
# Configures and builds the CrossOver Wine tree for an x86_64 host (it runs under Rosetta),
# with new WoW64 (i386 PE on the 64-bit host), into $INSTALL.
# The build runs natively on arm64 and cross-compiles with -arch x86_64.
# Adapted from steamplay-mac (GPL-3.0); Steam bridge (lsteamclient) removed.
#
# Usage: scripts/build-wine.sh [--reconfigure]
set -euo pipefail
source "$(dirname "$0")/../config.sh"

SRC="$SOURCES/sources/wine"
[ -f "$SRC/configure" ] || { echo "no wine sources, run scripts/fetch-sources.sh" >&2; exit 1; }

export PATH="$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/opt/flex/bin:$BREW_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
export PKG_CONFIG_PATH=""

# ccache is optional: it speeds up rebuilds but costs a few GB of disk.
if command -v ccache >/dev/null && [ "${NO_CCACHE:-0}" != 1 ]; then
    CCACHE="ccache "; export CCACHE_DIR="$ROOT/build/ccache"
else
    CCACHE=""
fi

# Wine 11.0 needs native build tools (winebuild, winegcc, widl, wrc, makedep...) to cross
# compile; build them from the same tree for the arm64 build machine first.
if [ ! -x "$TOOLS/tools/winebuild/winebuild" ] || ! grep -q '#define SONAME_LIBFREETYPE' "$TOOLS/include/config.h"; then
    mkdir -p "$TOOLS"
    # An aarch64 build machine needs a PE compiler even for a tools-only tree: LLVM clang+lld.
    # sfnt2fon (bitmap fonts) needs FreeType at build time: the native arm64 Homebrew one.
    (cd "$TOOLS" && PATH="$BREW_PREFIX/opt/llvm/bin:$BREW_PREFIX/opt/lld/bin:$PATH" \
        "$SRC/configure" --enable-archs=aarch64 --with-mingw=clang --disable-tests \
        --without-x --with-freetype --without-gnutls --without-sdl --without-vulkan \
        --without-gstreamer --without-ffmpeg --without-coreaudio --without-opencl \
        CC="/usr/bin/clang" CXX="/usr/bin/clang++" CFLAGS="-O2 -g0" \
        FREETYPE_CFLAGS="-I$BREW_PREFIX/opt/freetype/include/freetype2" \
        FREETYPE_LIBS="-L$BREW_PREFIX/opt/freetype/lib -lfreetype")
    make -C "$TOOLS" -j"$JOBS" __tooldeps__
fi
# wrc looks for locale.nls and the codepage tables next to its own build tree.
for f in "$SRC"/nls/*.nls; do ln -sf "$f" "$TOOLS/nls/${f##*/}"; done

mkdir -p "$WBUILD"
cd "$WBUILD"

if [ ! -f Makefile ] || [ "${1:-}" = "--reconfigure" ]; then
    # Unix .so files live in lib/wine/x86_64-unix; @loader_path/../.. is wswine.bundle/lib,
    # where package-engine.sh puts the bundled dylibs.
    "$SRC/configure" \
        --prefix="$INSTALL" \
        --host=x86_64-apple-darwin --build=aarch64-apple-darwin --with-wine-tools="$TOOLS" \
        --enable-archs=i386,x86_64 \
        --with-mingw \
        --disable-tests \
        --without-alsa --without-capi --with-coreaudio --without-cups --without-dbus \
        --without-fontconfig --with-freetype --with-gnutls --without-gphoto --without-gstreamer \
        --without-krb5 --without-netapi --without-oss --without-pulse --without-sane --with-sdl \
        --without-udev --without-usb --without-v4l2 --with-vulkan --without-x --without-wayland \
        --with-ffmpeg --without-inotify --without-pcap \
        CC="${CCACHE}clang -arch x86_64" CXX="${CCACHE}clang++ -arch x86_64" \
        OBJC="${CCACHE}clang -arch x86_64" \
        i386_CC="${CCACHE}i686-w64-mingw32-gcc" x86_64_CC="${CCACHE}x86_64-w64-mingw32-gcc" \
        CFLAGS="-O2 -g0" CROSSCFLAGS="-O2 -g0" \
        CPPFLAGS="-I$DEPS/include" \
        LDFLAGS="-L$DEPS/lib -Wl,-rpath,@loader_path/../.. -Wl,-headerpad_max_install_names" \
        ac_cv_lib_soname_MoltenVK=libMoltenVK.dylib \
        PKG_CONFIG="$BREW_PREFIX/bin/pkg-config" \
        FREETYPE_CFLAGS="-I$DEPS/include/freetype2" FREETYPE_LIBS="-L$DEPS/lib -lfreetype" \
        SDL2_CFLAGS="-I$DEPS/include/SDL2 -D_THREAD_SAFE" SDL2_LIBS="-L$DEPS/lib -lSDL2" \
        GNUTLS_CFLAGS="-I$DEPS/include" GNUTLS_LIBS="-L$DEPS/lib -lgnutls" \
        FFMPEG_CFLAGS="-I$DEPS/include" FFMPEG_LIBS="-L$DEPS/lib -lavformat -lavcodec -lavutil"
fi

# configure turns optional features off silently; fail early if one we rely on is missing.
for need in SONAME_LIBFREETYPE SONAME_LIBGNUTLS SONAME_LIBSDL2 SONAME_LIBVULKAN; do
    grep -q "#define $need " include/config.h || { echo "missing $need in config.h" >&2; exit 1; }
done
grep -q '#define HAVE_FFMPEG 1' include/config.h || { echo "FFmpeg not enabled" >&2; exit 1; }

make -j"$JOBS"
rm -rf "$INSTALL"
make install-lib
ln -sf ../lib/wine/x86_64-unix/wine "$INSTALL/bin/wine"

# The point of this whole build: CodeWeavers' hacks must be in. Fail loudly if not.
for knob in WINE_SIMULATE_WRITECOPY CX_APPLEGPTK_LIBD3DSHARED_PATH; do
    grep -qa "$knob" "$INSTALL/lib/wine/x86_64-unix/ntdll.so" \
        || { echo "ntdll.so lacks $knob: not a CrossOver-patched build?" >&2; exit 1; }
done
echo "wine installed at $INSTALL"
