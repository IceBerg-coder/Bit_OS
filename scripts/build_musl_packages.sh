#!/bin/bash
# Build real statically-linked packages for BitOS v2.0
# Uses the musl cross-compile toolchain built by build_musl_toolchain.sh
set -euo pipefail
source "$(dirname "$0")/common.sh"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
TOOLCHAIN_DIR="${MUSL_TOOLCHAIN_DIR:-$HOME/musl-cross}"
TARGET="x86_64-linux-musl"
CC="$TOOLCHAIN_DIR/bin/$TARGET-gcc"
CXX="$TOOLCHAIN_DIR/bin/$TARGET-g++"
AR="$TOOLCHAIN_DIR/bin/$TARGET-ar"
RANLIB="$TOOLCHAIN_DIR/bin/$TARGET-ranlib"
STRIP="$TOOLCHAIN_DIR/bin/$TARGET-strip"
export MAKEFLAGS="-j$(nproc)"

SYSROOT="$BUILD_DIR/musl-sysroot"
PKG_BUILD="$BUILD_DIR/musl-pkgs"
MUSL_SRC="$SRC_DIR/musl-packages"

ZLIB_VER="1.3.1";       ZLIB_URL="https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz"
OPENSSL_VER="3.3.2";    OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz"
NCURSES_VER="6.4";      NCURSES_URL="https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VER}.tar.gz"
READLINE_VER="8.2";     READLINE_URL="https://ftp.gnu.org/gnu/readline/readline-${READLINE_VER}.tar.gz"
CURL_VER="8.9.1";       CURL_URL="https://github.com/curl/curl/releases/download/curl-8_9_1/curl-${CURL_VER}.tar.gz"
NANO_VER="7.2";         NANO_URL="https://ftp.gnu.org/gnu/nano/nano-${NANO_VER}.tar.gz"
RSYNC_VER="3.4.1";      RSYNC_URL="https://github.com/RsyncProject/rsync/releases/download/v${RSYNC_VER}/rsync-${RSYNC_VER}.tar.gz"
HTOP_VER="3.3.0";       HTOP_URL="https://github.com/htop-dev/htop/releases/download/${HTOP_VER}/htop-${HTOP_VER}.tar.xz"
JQ_VER="1.7.1";         JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VER}/jq-${JQ_VER}.tar.gz"
STRACE_VER="6.19";      STRACE_URL="https://github.com/strace/strace/releases/download/v${STRACE_VER}/strace-${STRACE_VER}.tar.xz"
LESS_VER="668";         LESS_URL="https://www.greenwoodsoftware.com/less/less-${LESS_VER}.tar.gz"
WGET_VER="1.24.5";      WGET_URL="https://ftp.gnu.org/gnu/wget/wget-${WGET_VER}.tar.gz"
TREE_VER="2.1.1";       TREE_URL="https://github.com/Old-Man-Programmer/tree/archive/refs/tags/${TREE_VER}.tar.gz"
VIM_VER="9.1.0000";     VIM_URL="https://github.com/vim/vim/archive/refs/tags/v${VIM_VER}.tar.gz"
FILE_VER="5.46";        FILE_URL="https://astron.com/pub/file/file-${FILE_VER}.tar.gz"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_dl() {   # _dl NAME URL -> downloads to $MUSL_SRC/, sets DL_OUT
    local NAME="$1" URL="$2"
    DL_OUT="$MUSL_SRC/$(basename "$URL")"
    mkdir -p "$MUSL_SRC"
    if [ -f "$DL_OUT" ]; then
        log_info "  Cached: $NAME"
    else
        log_info "  Downloading $NAME ..."
        wget -q --show-progress --tries=3 --timeout=30 "$URL" -O "$DL_OUT" || { rm -f "$DL_OUT"; log_err "Download failed: $URL"; exit 1; }
        log_info "  Downloaded: $NAME"
    fi
}

_unpack() {   # _unpack TARBALL DEST_DIR
    local TB="$1" DEST="$2"
    [ -d "$DEST" ] && return
    log_info "  Unpacking $(basename "$TB") ..."
    mkdir -p "$(dirname "$DEST")"
    tar xf "$TB" -C "$(dirname "$DEST")"
}

_package() {   # _package PKG_NAME BIN_PATH VERSION DEPS DESC
    local PKG="$1" BIN="$2" VER="$3" DEPS="$4" DESC="$5"
    local STRIP_BIN="$PKG_BUILD/_stripped/$PKG"
    mkdir -p "$PKG_BUILD/_stripped"
    cp "$BIN" "$STRIP_BIN"
    "$STRIP" --strip-all "$STRIP_BIN" 2>/dev/null || true
    local SHA; SHA=$(sha256sum "$STRIP_BIN" | awk '{print $1}')
    cp "$STRIP_BIN" "$WORKSPACE_ROOT/pkgs/$PKG"
    # Remove old entry, append new one
    sed -i "/^$PKG /d" "$WORKSPACE_ROOT/pkgs/packages.list" 2>/dev/null || true
    printf "%-16s %-6s %s  %-16s %s\n" "$PKG" "$VER" "$SHA" "$DEPS" "$DESC" \
        >> "$WORKSPACE_ROOT/pkgs/packages.list"
    local SZ; SZ=$(du -sh "$STRIP_BIN" | awk '{print $1}')
    log_info "[+] Packaged: $PKG v$VER  size=$SZ  sha256=${SHA:0:16}..."
}

# ---------------------------------------------------------------------------
# Sysroot libs
# ---------------------------------------------------------------------------
build_zlib() {
    [ -f "$SYSROOT/lib/libz.a" ] && log_info "zlib: already built" && return
    _dl zlib "$ZLIB_URL"; _unpack "$DL_OUT" "$PKG_BUILD/zlib-$ZLIB_VER"
    log_info "Building zlib $ZLIB_VER ..."
    cd "$PKG_BUILD/zlib-$ZLIB_VER"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure --prefix="$SYSROOT" --static
    make; make install
    cd "$WORKSPACE_ROOT"
    log_info "zlib: done"
}

build_openssl() {
    [ -f "$SYSROOT/lib/libssl.a" ] && log_info "openssl: already built" && return
    _dl openssl "$OPENSSL_URL"; _unpack "$DL_OUT" "$PKG_BUILD/openssl-$OPENSSL_VER"
    log_info "Building openssl $OPENSSL_VER (static) ..."
    cd "$PKG_BUILD/openssl-$OPENSSL_VER"
    CC="$CC" ./Configure linux-x86_64 no-shared no-tests \
        --prefix="$SYSROOT" --openssldir="$SYSROOT/ssl" --libdir=lib -static -fPIC
    make; make install_sw
    # OpenSSL may install to lib64 on x86_64 — create compat symlinks in lib/
    for lib in libssl.a libcrypto.a; do
        [ -f "$SYSROOT/lib/$lib" ] || ln -sf ../lib64/$lib "$SYSROOT/lib/$lib" 2>/dev/null || true
    done
    mkdir -p "$SYSROOT/lib/pkgconfig"
    for pc in openssl libssl libcrypto; do
        [ -f "$SYSROOT/lib/pkgconfig/$pc.pc" ] || \
            ln -sf ../../lib64/pkgconfig/$pc.pc "$SYSROOT/lib/pkgconfig/$pc.pc" 2>/dev/null || true
    done
    cd "$WORKSPACE_ROOT"
    log_info "openssl: done"
}

build_ncurses() {
    [ -f "$SYSROOT/lib/libncurses.a" ] && log_info "ncurses: already built" && return
    _dl ncurses "$NCURSES_URL"
    # clean partial build so _unpack recreates it
    rm -rf "$PKG_BUILD/ncurses-$NCURSES_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/ncurses-$NCURSES_VER"
    log_info "Building ncurses $NCURSES_VER (static) ..."
    cd "$PKG_BUILD/ncurses-$NCURSES_VER"
    mkdir -p "$SYSROOT/share/terminfo"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    ./configure --host="$TARGET" --prefix="$SYSROOT" \
        --without-shared --without-tests --without-progs --without-manpages \
        --without-debug --enable-widec \
        --with-default-terminfo-dir="/usr/share/terminfo" \
        --with-terminfo-dirs="/usr/share/terminfo:/etc/terminfo"
    make
    # Override ticdir so run_tic.sh writes terminfo to our sysroot, not /usr/share
    make install ticdir="$SYSROOT/share/terminfo"
    ln -sf libncursesw.a "$SYSROOT/lib/libncurses.a" 2>/dev/null || true
    ln -sf libncursesw.a "$SYSROOT/lib/libtinfo.a"   2>/dev/null || true
    # Create ncurses -> ncursesw compat symlink in include/
    ln -sf ncursesw "$SYSROOT/include/ncurses" 2>/dev/null || true
    cd "$WORKSPACE_ROOT"
    log_info "ncurses: done"
}

build_readline() {
    [ -f "$SYSROOT/lib/libreadline.a" ] && log_info "readline: already built" && return
    _dl readline "$READLINE_URL"; _unpack "$DL_OUT" "$PKG_BUILD/readline-$READLINE_VER"
    log_info "Building readline $READLINE_VER (static) ..."
    cd "$PKG_BUILD/readline-$READLINE_VER"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    ./configure --host="$TARGET" --prefix="$SYSROOT" --disable-shared --enable-static
    make; make install
    cd "$WORKSPACE_ROOT"
    log_info "readline: done"
}

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
build_curl() {
    _dl curl "$CURL_URL"
    rm -rf "$PKG_BUILD/curl-$CURL_VER"  # always clean to avoid stale configure cache
    _unpack "$DL_OUT" "$PKG_BUILD/curl-$CURL_VER"
    log_info "Building curl $CURL_VER (static + openssl + zlib) ..."
    local SRC="$PKG_BUILD/curl-$CURL_VER"
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig:$SYSROOT/lib64/pkgconfig" \
    CPPFLAGS="-I$SYSROOT/include" \
    LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -static" \
    LIBS="-lssl -lcrypto -lz -ldl -lpthread" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-shared --enable-static --with-openssl="$SYSROOT" --with-zlib="$SYSROOT" \
        --disable-ldap --disable-sspi --disable-manual --without-libidn2 --without-libpsl \
        --disable-rtsp --disable-dict --disable-telnet --disable-tftp \
        --disable-pop3 --disable-imap --disable-smb --disable-smtp --disable-gopher
    make; make install
    _package "curl" "$SRC/_install/bin/curl" "$CURL_VER" "musl-libc" \
        "Static curl with TLS - HTTP/HTTPS downloads REST API file transfers"
    cd "$WORKSPACE_ROOT"
}

build_nano() {
    _dl nano "$NANO_URL"
    rm -rf "$PKG_BUILD/nano-$NANO_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/nano-$NANO_VER"
    log_info "Building nano $NANO_VER (static + ncurses) ..."
    local SRC="$PKG_BUILD/nano-$NANO_VER"
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CPPFLAGS="-I$SYSROOT/include -I$SYSROOT/include/ncursesw" \
    LDFLAGS="-L$SYSROOT/lib -static" \
    LIBS="-lncursesw -ltinfo" \
    NCURSES_CFLAGS="-I$SYSROOT/include/ncursesw" \
    NCURSES_LIBS="-L$SYSROOT/lib -lncursesw" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" --disable-nls
    make; make install
    _package "nano" "$SRC/_install/bin/nano" "$NANO_VER" "-" \
        "GNU nano text editor - static build with full ncurses TUI"
    cd "$WORKSPACE_ROOT"
}

build_rsync() {
    _dl rsync "$RSYNC_URL"
    rm -rf "$PKG_BUILD/rsync-$RSYNC_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/rsync-$RSYNC_VER"
    log_info "Building rsync $RSYNC_VER (static) ..."
    local SRC="$PKG_BUILD/rsync-$RSYNC_VER"
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CPPFLAGS="-I$SYSROOT/include" \
    LDFLAGS="-L$SYSROOT/lib -static" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-openssl --disable-locale --disable-lz4 \
        --disable-xxhash --disable-zstd --disable-md2man
    make; make install
    _package "rsync" "$SRC/_install/bin/rsync" "$RSYNC_VER" "-" \
        "rsync - static file sync over SSH local or rsync protocol"
    cd "$WORKSPACE_ROOT"
}

build_htop() {
    _dl htop "$HTOP_URL"
    rm -rf "$PKG_BUILD/htop-$HTOP_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/htop-$HTOP_VER"
    log_info "Building htop $HTOP_VER (static + ncurses) ..."
    local SRC="$PKG_BUILD/htop-$HTOP_VER"
    cd "$SRC"
    [ -f configure ] || { autoreconf -fi 2>/dev/null || true; }
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CPPFLAGS="-I$SYSROOT/include -I$SYSROOT/include/ncursesw" \
    LDFLAGS="-L$SYSROOT/lib -static" \
    LIBS="-lm" \
    NCURSES_CFLAGS="-I$SYSROOT/include/ncursesw" \
    NCURSES_LIBS="-L$SYSROOT/lib -lncursesw -ltinfo" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" --disable-unicode
    make; make install
    _package "htop" "$SRC/_install/bin/htop" "$HTOP_VER" "-" \
        "htop - interactive process viewer with CPU mem bars ncurses TUI"
    cd "$WORKSPACE_ROOT"
}

build_jq() {
    _dl jq "$JQ_URL"
    rm -rf "$PKG_BUILD/jq-$JQ_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/jq-$JQ_VER"
    log_info "Building jq $JQ_VER (static) ..."
    local SRC="$PKG_BUILD/jq-$JQ_VER"
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    LDFLAGS="-static" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-shared --enable-static --disable-docs --with-oniguruma=builtin
    make; make install
    _package "jq" "$SRC/_install/bin/jq" "$JQ_VER" "musl-libc" \
        "jq - lightweight JSON processor slice filter map transform JSON"
    cd "$WORKSPACE_ROOT"
}

build_musl_libc() {
    local MUSL_VER="1.2.5"
    local LIBC_SO="$TOOLCHAIN_DIR/$TARGET/lib/libc.so"
    [ -f "$LIBC_SO" ] || { log_err "musl libc.so not found: $LIBC_SO"; exit 1; }
    log_info "Packaging musl-libc $MUSL_VER (dynamic linker for musl-linked binaries) ..."
    local STRIP_BIN="$PKG_BUILD/_stripped/musl-libc"
    mkdir -p "$PKG_BUILD/_stripped"
    cp "$LIBC_SO" "$STRIP_BIN"
    # Use --strip-debug not --strip-all — dynamic linkers need their symbol table intact
    "$STRIP" --strip-debug "$STRIP_BIN" 2>/dev/null || true
    local SHA; SHA=$(sha256sum "$STRIP_BIN" | awk '{print $1}')
    cp "$STRIP_BIN" "$WORKSPACE_ROOT/pkgs/musl-libc"
    sed -i "/^musl-libc /d" "$WORKSPACE_ROOT/pkgs/packages.list" 2>/dev/null || true
    printf "%-16s %-6s %s  %-16s %s\n" "musl-libc" "$MUSL_VER" "$SHA" "-" \
        "musl libc dynamic linker - required by curl jq and other musl-dynamic packages" \
        >> "$WORKSPACE_ROOT/pkgs/packages.list"
    local SZ; SZ=$(du -sh "$STRIP_BIN" | awk '{print $1}')
    log_info "[+] Packaged: musl-libc v$MUSL_VER  size=$SZ  sha256=${SHA:0:16}..."
    log_info "[+] bpm will install this to \$BPM_BIN/musl-libc and /lib/ld-musl-x86_64.so.1"
}

build_strace() {
    _dl strace "$STRACE_URL"
    rm -rf "$PKG_BUILD/strace-$STRACE_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/strace-$STRACE_VER"
    log_info "Building strace $STRACE_VER (static) ..."
    local SRC="$PKG_BUILD/strace-$STRACE_VER"
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    LDFLAGS="-static" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --enable-static --disable-shared --disable-mpers
    make; make install
    _package "strace" "$SRC/_install/bin/strace" "$STRACE_VER" "-" \
        "strace - system call tracer for debugging and tracing processes"
    cd "$WORKSPACE_ROOT"
}

build_less() {
    _dl less "$LESS_URL"
    rm -rf "$PKG_BUILD/less-$LESS_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/less-$LESS_VER"
    log_info "Building less $LESS_VER (static + ncurses) ..."
    local SRC="$PKG_BUILD/less-$LESS_VER"
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CPPFLAGS="-I$SYSROOT/include -I$SYSROOT/include/ncursesw" \
    LDFLAGS="-L$SYSROOT/lib -static" \
    LIBS="-lncursesw -ltinfo" \
    ./configure --host="$TARGET" --prefix="$SRC/_install"
    make; make install
    _package "less" "$SRC/_install/bin/less" "$LESS_VER" "-" \
        "less - feature-rich terminal pager for viewing files and command output"
    cd "$WORKSPACE_ROOT"
}

build_wget() {
    _dl wget "$WGET_URL"
    rm -rf "$PKG_BUILD/wget-$WGET_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/wget-$WGET_VER"
    log_info "Building wget $WGET_VER (static + openssl + zlib) ..."
    local SRC="$PKG_BUILD/wget-$WGET_VER"
    # Minimal pkg-config wrapper so wget configure doesn't fail without system pkg-config
    local FAKE_PC="$PKG_BUILD/_pkgconfig"
    mkdir -p "$FAKE_PC"
    cat > "$FAKE_PC/pkg-config" << PCEOF
#!/bin/sh
SYSROOT="$SYSROOT"
# Handle version queries
case "\$1" in
    --version|--atleast-pkgconfig-version) echo "0.29.2"; exit 0 ;;
    --modversion) echo "1.0"; exit 0 ;;
esac
# Handle --cflags / --libs for known packages
CFLAGS="-I\$SYSROOT/include"
LIBS="-L\$SYSROOT/lib -lssl -lcrypto -lz -ldl -lpthread"
for arg in "\$@"; do
    case "\$arg" in --cflags) echo "\$CFLAGS"; exit 0 ;; --libs) echo "\$LIBS"; exit 0 ;; esac
done
exit 0
PCEOF
    chmod +x "$FAKE_PC/pkg-config"
    cd "$SRC"
    PATH="$FAKE_PC:$PATH" \
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    PKG_CONFIG="$FAKE_PC/pkg-config" \
    PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig" \
    OPENSSL_CFLAGS="-I$SYSROOT/include" \
    OPENSSL_LIBS="-L$SYSROOT/lib -lssl -lcrypto -lz -ldl -lpthread" \
    ZLIB_CFLAGS="-I$SYSROOT/include" \
    ZLIB_LIBS="-L$SYSROOT/lib -lz" \
    CPPFLAGS="-I$SYSROOT/include" \
    LDFLAGS="-L$SYSROOT/lib -L$SYSROOT/lib64 -static" \
    LIBS="-lssl -lcrypto -lz -ldl -lpthread" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --with-ssl=openssl --disable-nls --disable-rpath \
        --without-libpsl --without-libuuid --without-metalink \
        --disable-pcre2 --disable-pcre --disable-iri
    make; make install
    _package "wget" "$SRC/_install/bin/wget" "$WGET_VER" "-" \
        "wget - non-interactive network downloader with HTTPS support"
    cd "$WORKSPACE_ROOT"
}

build_tree() {
    _dl tree "$TREE_URL"
    rm -rf "$PKG_BUILD/tree-$TREE_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/tree-$TREE_VER"
    log_info "Building tree $TREE_VER (static) ..."
    local SRC="$PKG_BUILD/tree-$TREE_VER"
    cd "$SRC"
    make CC="$CC" \
        CFLAGS="-O2 -static" \
        LDFLAGS="-static" \
        tree
    _package "tree" "$SRC/tree" "$TREE_VER" "-" \
        "tree - recursive directory listing with colours and file counts"
    cd "$WORKSPACE_ROOT"
}

build_vim() {
    _dl vim "$VIM_URL"
    rm -rf "$PKG_BUILD/vim-$VIM_VER"
    _unpack "$DL_OUT" "$PKG_BUILD/vim-$VIM_VER"
    log_info "Building vim $VIM_VER (static + ncurses) ..."
    local SRC="$PKG_BUILD/vim-$VIM_VER"
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CPPFLAGS="-I$SYSROOT/include -I$SYSROOT/include/ncursesw" \
    LDFLAGS="-L$SYSROOT/lib -static" \
    LIBS="-lncursesw -ltinfo" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --with-tlib=ncursesw \
        --disable-gui --without-x --disable-gtktest \
        --disable-netbeans --disable-canberra \
        --disable-selinux --disable-nls \
        --with-features=huge \
        --enable-multibyte \
        --disable-perlinterp --disable-pythoninterp \
        --disable-python3interp --disable-rubyinterp \
        --disable-luainterp --disable-tclinterp
    make; make install
    _package "vim" "$SRC/_install/bin/vim" "$VIM_VER" "-" \
        "vim - advanced text editor with syntax highlighting and huge feature set"
    cd "$WORKSPACE_ROOT"
}

build_file() {
    _dl file "$FILE_URL"
    rm -rf "$PKG_BUILD/file-$FILE_VER" "$PKG_BUILD/file-${FILE_VER}-native"
    _unpack "$DL_OUT" "$PKG_BUILD/file-$FILE_VER"
    log_info "Building file $FILE_VER (static + zlib) ..."
    local SRC="$PKG_BUILD/file-$FILE_VER"

    # Native build to produce magic.mgc (cross-compiled binary can't run on host)
    cp -a "$SRC" "$PKG_BUILD/file-${FILE_VER}-native"
    cd "$PKG_BUILD/file-${FILE_VER}-native"
    ./configure --prefix="$PKG_BUILD/file-${FILE_VER}-native/_install" \
        --disable-shared >/dev/null 2>&1
    make -j$(nproc) >/dev/null 2>&1
    local MAGIC_MGC="$PKG_BUILD/file-${FILE_VER}-native/magic/magic.mgc"
    [ ! -f "$MAGIC_MGC" ] && MAGIC_MGC=$(find "$PKG_BUILD/file-${FILE_VER}-native" -name "magic.mgc" | head -1)
    if [ -z "$MAGIC_MGC" ]; then log_err "Native file build failed — cannot get magic.mgc"; exit 1; fi
    log_info "  Native magic.mgc: $(ls -sh $MAGIC_MGC | awk '{print $1}')"

    # Cross-compile with pre-built magic.mgc injected
    cd "$SRC"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CPPFLAGS="-I$SYSROOT/include" \
    LDFLAGS="-L$SYSROOT/lib -static" \
    LIBS="-lz" \
    ./configure --host="$TARGET" --prefix="$SRC/_install" \
        --disable-shared --enable-static \
        --disable-libseccomp --disable-bzlib --disable-xzlib
    cp "$MAGIC_MGC" magic/magic.mgc
    # Touch with future timestamp so make considers magic.mgc up-to-date
    touch -t 203001010000 magic/magic.mgc
    make; make install
    _package "file" "$SRC/_install/bin/file" "$FILE_VER" "-" \
        "file - determine file type by magic number inspection"
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
# Sign
# ---------------------------------------------------------------------------
sign_list() {
    if [ -f "$WORKSPACE_ROOT/pkgs/keys/signing_key.pem" ]; then
        log_info "Re-signing packages.list ..."
        bash "$WORKSPACE_ROOT/scripts/sign_packages.sh"
    else
        log_info "(skipping signing — signing_key.pem not present)"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [all | sysroot | curl | nano | rsync | htop | jq | musl-libc | strace | less | wget]"
    echo "  all     - sysroot libs + all packages (default)"
    echo "  sysroot - zlib + openssl + ncurses + readline only"
    echo "  curl / nano / rsync / htop / jq  - sysroot + named package"
}

build_sysroot() {
    log_info "--- Building static sysroot libs ---"
    mkdir -p "$SYSROOT" "$PKG_BUILD"
    build_zlib
    build_openssl
    build_ncurses
    build_readline
    log_info "--- Sysroot complete ---"
}

main() {
    if [ ! -x "$CC" ]; then
        log_err "Toolchain not found: $CC"
        log_err "Run first: bash scripts/build_musl_toolchain.sh"
        exit 1
    fi
    log_info "=== BitOS v2.0: Static Package Builder ==="
    log_info "Toolchain: $CC"
    log_info "Sysroot:   $SYSROOT"
    log_info "Output:    $WORKSPACE_ROOT/pkgs/"
    echo ""
    local T="${1:-all}"
    case "$T" in
        sysroot)     build_sysroot ;;
        curl)        build_sysroot; build_curl;       sign_list ;;
        nano)        build_sysroot; build_nano;       sign_list ;;
        rsync)       build_sysroot; build_rsync;      sign_list ;;
        htop)        build_sysroot; build_htop;       sign_list ;;
        jq)          build_jq;                        sign_list ;;
        musl-libc)   build_musl_libc;                 sign_list ;;
        strace)      build_strace;                    sign_list ;;
        less)        build_sysroot; build_less;        sign_list ;;
        wget)        build_sysroot; build_wget;        sign_list ;;
        tree)        build_tree;                       sign_list ;;
        vim)         build_sysroot; build_vim;          sign_list ;;
        file)        build_sysroot; build_file;         sign_list ;;
        all)
            build_sysroot
            build_curl; build_nano; build_rsync; build_htop; build_jq
            build_musl_libc; build_strace; build_less; build_wget
            build_tree; build_vim; build_file
            sign_list
            ;;
        --help|-h) usage; exit 0 ;;
        *) log_err "Unknown: $T"; usage; exit 1 ;;
    esac
    log_info "=== Done ==="
}

main "$@"
