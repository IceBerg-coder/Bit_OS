#!/bin/bash
# Build real statically-linked packages for BitOS v2.0
# Uses the musl cross-compile toolchain built by build_musl_toolchain.sh
#
# Produces binaries in pkgs/ and updates pkgs/packages.list
# Runtime: 30-60 min first build; incremental rebuilds are fast
set -euo pipefail
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TOOLCHAIN_DIR="${MUSL_TOOLCHAIN_DIR:-$HOME/musl-cross}"
TARGET="x86_64-linux-musl"
CC="$TOOLCHAIN_DIR/bin/$TARGET-gcc"
AR="$TOOLCHAIN_DIR/bin/$TARGET-ar"
RANLIB="$TOOLCHAIN_DIR/bin/$TARGET-ranlib"
STRIP="$TOOLCHAIN_DIR/bin/$TARGET-strip"

SYSROOT="$BUILD_DIR/musl-sysroot"     # static libs built here
PKG_BUILD="$BUILD_DIR/musl-pkgs"      # source unpacked + built here
MUSL_SRC="$SRC_DIR/musl-packages"     # downloaded tarballs

# Version pinning
ZLIB_VER="1.3.1"
OPENSSL_VER="3.3.2"
NCURSES_VER="6.4"
READLINE_VER="8.2"
CURL_VER="8.9.1"
NANO_VER="7.2"
RSYNC_VER="3.3.0"
HTOP_VER="3.3.0"
JQ_VER="1.7.1"
NMAP_VER="7.95"

ZLIB_SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
OPENSSL_SHA256="a9f8f43c77f5b2e28c6b2fddd36b57a0b38cd54e3a4d6a6f36c3d857bc9c1d4"
NCURSES_SHA256="6931283d9ac87c5073f30b6290c4c75f21632bb4fc3603ac8100812bed248159"
READLINE_SHA256="3feb7171f16a84ee82ca18a36d7b9be109a52c04f492a053331d7d1095007c35"
CURL_SHA256="291124a007ee5111997825940b3b2884b8952ee28ae2b05a7f93b9d9aacbf553"
NANO_SHA256="6c8e6c8a04c66b1b6b0ef41c9200bc5b42723db19b468ebf49a0d39abf16de0e"
RSYNC_SHA256="7399e9a6708c32d678a72a63219e96f23be0be2336e50fd1348498d07041df90"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
export MAKEFLAGS="-j$(nproc)"

_fetch() {
    local NAME="$1" URL="$2" EXPECTED_SHA="$3" TARBALL
    TARBALL="$MUSL_SRC/$(basename "$URL")"
    mkdir -p "$MUSL_SRC"
    if [ ! -f "$TARBALL" ]; then
        log_info "Downloading $NAME..."
        wget -q --show-progress "$URL" -O "$TARBALL" || {
            log_err "Download failed: $URL"; rm -f "$TARBALL"; exit 1
        }
    fi
    if [ -n "$EXPECTED_SHA" ]; then
        local ACTUAL; ACTUAL=$(sha256sum "$TARBALL" | awk '{print $1}')
        if [ "$ACTUAL" != "$EXPECTED_SHA" ]; then
            log_err "SHA256 mismatch for $NAME"
            log_err "  expected: $EXPECTED_SHA"
            log_err "  got:      $ACTUAL"
            rm -f "$TARBALL"; exit 1
        fi
        log_info "  SHA256 verified: $NAME"
    fi
    echo "$TARBALL"
}

_unpack() {
    local TARBALL="$1" DEST="$2"
    if [ -d "$DEST" ]; then
        log_info "  Already unpacked: $(basename "$DEST")"
        return
    fi
    log_info "  Unpacking $(basename "$TARBALL")..."
    mkdir -p "$(dirname "$DEST")"
    tar xf "$TARBALL" -C "$(dirname "$DEST")"
}

_package() {
    # Strip binary, sha256 it, copy to pkgs/, update packages.list
    local PKG="$1" BIN="$2" VER="$3" DEPS="$4" DESC="$5"
    STRIP_BIN="$PKG_BUILD/_stripped/$PKG"
    mkdir -p "$PKG_BUILD/_stripped"
    cp "$BIN" "$STRIP_BIN"
    "$STRIP" --strip-all "$STRIP_BIN" 2>/dev/null || true
    local SHA; SHA=$(sha256sum "$STRIP_BIN" | awk '{print $1}')
    cp "$STRIP_BIN" "$WORKSPACE_ROOT/pkgs/$PKG"
    # Update or insert line in packages.list
    if grep -q "^$PKG " "$WORKSPACE_ROOT/pkgs/packages.list"; then
        sed -i "/^$PKG /d" "$WORKSPACE_ROOT/pkgs/packages.list"
    fi
    printf "%-16s %-6s %s  %-16s %s\n" "$PKG" "$VER" "$SHA" "$DEPS" "$DESC" \
        >> "$WORKSPACE_ROOT/pkgs/packages.list"
    log_info "[+] Packaged: $PKG v$VER  ($SHA)"
}

# ---------------------------------------------------------------------------
# Sysroot: zlib
# ---------------------------------------------------------------------------
build_zlib() {
    local TB; TB=$(_fetch zlib "https://zlib.net/zlib-$ZLIB_VER.tar.gz" "$ZLIB_SHA256")
    local SRC="$PKG_BUILD/zlib-$ZLIB_VER"
    _unpack "$TB" "$SRC"
    if [ -f "$SYSROOT/lib/libz.a" ]; then log_info "zlib already built"; return; fi
    log_info "Building zlib..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        ./configure --prefix="$SYSROOT" --static
    make; make install
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Sysroot: openssl
# ---------------------------------------------------------------------------
build_openssl() {
    local TB; TB=$(_fetch openssl \
        "https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz" "$OPENSSL_SHA256")
    local SRC="$PKG_BUILD/openssl-$OPENSSL_VER"
    _unpack "$TB" "$SRC"
    if [ -f "$SYSROOT/lib/libssl.a" ]; then log_info "openssl already built"; return; fi
    log_info "Building openssl (static)..."
    cd "$SRC"
    CC="$CC" \
    ./Configure linux-x86_64 no-shared no-tests \
        --prefix="$SYSROOT" --openssldir="$SYSROOT/ssl" \
        -static -fPIC
    make -j"$(nproc)"; make install_sw
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Sysroot: ncurses
# ---------------------------------------------------------------------------
build_ncurses() {
    local TB; TB=$(_fetch ncurses \
        "https://ftp.gnu.org/gnu/ncurses/ncurses-$NCURSES_VER.tar.gz" "$NCURSES_SHA256")
    local SRC="$PKG_BUILD/ncurses-$NCURSES_VER"
    _unpack "$TB" "$SRC"
    if [ -f "$SYSROOT/lib/libncurses.a" ]; then log_info "ncurses already built"; return; fi
    log_info "Building ncurses (static)..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    ./configure --host="$TARGET" --prefix="$SYSROOT" \
        --without-shared --without-tests --without-progs \
        --without-manpages --without-debug --without-cxx-binding \
        --enable-widec --with-default-terminfo-dir=/usr/share/terminfo
    make; make install
    # Compatibility symlink
    ln -sf libncursesw.a "$SYSROOT/lib/libncurses.a" 2>/dev/null || true
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Sysroot: readline
# ---------------------------------------------------------------------------
build_readline() {
    local TB; TB=$(_fetch readline \
        "https://ftp.gnu.org/gnu/readline/readline-$READLINE_VER.tar.gz" "$READLINE_SHA256")
    local SRC="$PKG_BUILD/readline-$READLINE_VER"
    _unpack "$TB" "$SRC"
    if [ -f "$SYSROOT/lib/libreadline.a" ]; then log_info "readline already built"; return; fi
    log_info "Building readline (static)..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    ./configure --host="$TARGET" --prefix="$SYSROOT" \
        --disable-shared --enable-static
    make; make install
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Package: curl (static, with openssl + zlib)
# ---------------------------------------------------------------------------
build_curl() {
    local TB; TB=$(_fetch curl \
        "https://curl.se/download/curl-$CURL_VER.tar.gz" "$CURL_SHA256")
    local SRC="$PKG_BUILD/curl-$CURL_VER"
    _unpack "$TB" "$SRC"
    log_info "Building curl (static + openssl)..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig" \
    CFLAGS="-I$SYSROOT/include" LDFLAGS="-L$SYSROOT/lib -static" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-shared --enable-static \
        --with-openssl="$SYSROOT" \
        --with-zlib="$SYSROOT" \
        --disable-ldap --disable-sspi --disable-manual \
        --without-libidn2 --without-libpsl \
        --disable-rtsp --disable-dict --disable-telnet \
        --disable-tftp --disable-pop3 --disable-imap \
        --disable-smb --disable-smtp --disable-gopher \
        LIBS="-lssl -lcrypto -lz -ldl -lpthread"
    make; make install
    _package "curl" "$SRC/_install/bin/curl" "$CURL_VER" "-" \
        "Static curl with TLS - HTTP/HTTPS downloads, REST API, file transfers"
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Package: nano (static, with ncurses)
# ---------------------------------------------------------------------------
build_nano() {
    local TB; TB=$(_fetch nano \
        "https://www.nano-editor.org/dist/v7/nano-$NANO_VER.tar.gz" "$NANO_SHA256")
    local SRC="$PKG_BUILD/nano-$NANO_VER"
    _unpack "$TB" "$SRC"
    log_info "Building nano (static + ncurses)..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CFLAGS="-I$SYSROOT/include -I$SYSROOT/include/ncurses" \
    LDFLAGS="-L$SYSROOT/lib -static" LIBS="-lncurses -ltinfo" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-nls --disable-utf8 \
        NCURSES_CFLAGS="-I$SYSROOT/include/ncurses" \
        NCURSES_LIBS="-L$SYSROOT/lib -lncurses"
    make; make install
    _package "nano" "$SRC/_install/bin/nano" "$NANO_VER" "-" \
        "GNU nano text editor - static build with full ncurses TUI"
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Package: rsync (static, no SSL — uses ssh transport)
# ---------------------------------------------------------------------------
build_rsync() {
    local TB; TB=$(_fetch rsync \
        "https://download.samba.org/pub/rsync/rsync-$RSYNC_VER.tar.gz" "$RSYNC_SHA256")
    local SRC="$PKG_BUILD/rsync-$RSYNC_VER"
    _unpack "$TB" "$SRC"
    log_info "Building rsync (static)..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CFLAGS="-I$SYSROOT/include" LDFLAGS="-L$SYSROOT/lib -static" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-openssl --disable-locale --disable-lz4 \
        --disable-xxhash --disable-zstd --disable-md2man
    make; make install
    _package "rsync" "$SRC/_install/bin/rsync" "$RSYNC_VER" "-" \
        "rsync - static file sync over SSH, local, or rsync:// protocol"
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Package: htop (static, ncurses)
# ---------------------------------------------------------------------------
build_htop() {
    local URL="https://github.com/htop-dev/htop/releases/download/$HTOP_VER/htop-$HTOP_VER.tar.xz"
    local TB; TB=$(_fetch htop "$URL" "")
    local SRC="$PKG_BUILD/htop-$HTOP_VER"
    _unpack "$TB" "$SRC"
    log_info "Building htop (static + ncurses)..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CFLAGS="-I$SYSROOT/include -I$SYSROOT/include/ncurses" \
    LDFLAGS="-L$SYSROOT/lib -static" \
    LIBS="-lncurses -ltinfo -lm" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --enable-static --disable-unicode \
        NCURSES_CFLAGS="-I$SYSROOT/include/ncurses" \
        NCURSES_LIBS="-L$SYSROOT/lib -lncurses"
    make; make install
    _package "htop" "$SRC/_install/bin/htop" "$HTOP_VER" "-" \
        "htop - interactive process viewer with CPU/mem bars, static ncurses TUI"
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Package: jq (static — pure C, minimal deps)
# ---------------------------------------------------------------------------
build_jq() {
    local URL="https://github.com/jqlang/jq/releases/download/jq-$JQ_VER/jq-$JQ_VER.tar.gz"
    local TB; TB=$(_fetch jq "$URL" "")
    local SRC="$PKG_BUILD/jq-$JQ_VER"
    _unpack "$TB" "$SRC"
    log_info "Building jq (static)..."
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    LDFLAGS="-static" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-shared --enable-static \
        --disable-docs --disable-maintainer-mode \
        --with-oniguruma=builtin
    make; make install
    _package "jq" "$SRC/_install/bin/jq" "$JQ_VER" "-" \
        "jq - lightweight JSON processor - slice, filter, map, transform JSON"
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Sign packages.list after all builds
# ---------------------------------------------------------------------------
sign_list() {
    if [ -f "$WORKSPACE_ROOT/pkgs/keys/signing_key.pem" ]; then
        log_info "Re-signing packages.list..."
        bash "$WORKSPACE_ROOT/scripts/sign_packages.sh"
    else
        log_info "Skipping signing — pkgs/keys/signing_key.pem not present on this machine"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [all | sysroot | curl | nano | rsync | htop | jq]"
    echo ""
    echo "  all      Build sysroot libs + all packages (default)"
    echo "  sysroot  Build static sysroot libs only (zlib, openssl, ncurses, readline)"
    echo "  curl     Build sysroot + curl only"
    echo "  nano     Build sysroot + nano only"
    echo "  rsync    Build sysroot + rsync only"
    echo "  htop     Build sysroot + htop only"
    echo "  jq       Build jq only (no sysroot needed)"
}

build_sysroot() {
    log_info "--- Building static sysroot libs ---"
    mkdir -p "$SYSROOT" "$PKG_BUILD"
    build_zlib
    build_openssl
    build_ncurses
    build_readline
    log_info "--- Sysroot complete: $SYSROOT ---"
}

main() {
    if [ ! -x "$CC" ]; then
        log_err "musl toolchain not found at $TOOLCHAIN_DIR"
        log_err "Run first: bash scripts/build_musl_toolchain.sh"
        exit 1
    fi

    log_info "=== BitOS v2.0: Static Package Builder ==="
    log_info "Toolchain: $CC"
    log_info "Sysroot:   $SYSROOT"
    log_info "Output:    $WORKSPACE_ROOT/pkgs/"
    echo ""

    local TARGET_PKG="${1:-all}"
    case "$TARGET_PKG" in
        sysroot) build_sysroot ;;
        curl)    build_sysroot; build_curl;  sign_list ;;
        nano)    build_sysroot; build_nano;  sign_list ;;
        rsync)   build_sysroot; build_rsync; sign_list ;;
        htop)    build_sysroot; build_htop;  sign_list ;;
        jq)      build_jq;                   sign_list ;;
        all)
            build_sysroot
            build_curl
            build_nano
            build_rsync
            build_htop
            build_jq
            sign_list
            ;;
        --help|-h) usage; exit 0 ;;
        *) log_err "Unknown target: $TARGET_PKG"; usage; exit 1 ;;
    esac

    log_info "=== Package build complete ==="
    log_info "Install on running BitOS:"
    log_info "  bpm install curl   # or nano, rsync, htop, jq"
}

main "$@"
