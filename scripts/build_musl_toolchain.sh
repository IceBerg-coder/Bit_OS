#!/bin/bash
# Build musl-cross-make cross-compile toolchain for BitOS v2.0
# Produces: x86_64-linux-musl-gcc in ~/musl-cross/bin/
# Runtime: ~15-25 min on a modern machine (downloads ~200MB of sources)
set -euo pipefail
source "$(dirname "$0")/common.sh"

TOOLCHAIN_DIR="${MUSL_TOOLCHAIN_DIR:-$HOME/musl-cross}"
MCM_DIR="$BUILD_DIR/musl-cross-make"

GCC_VER="13.3.0"
MUSL_VER="1.2.5"
BINUTILS_VER="2.44"
TARGET="x86_64-linux-musl"

# ---------------------------------------------------------------------------
check_host_deps() {
    log_info "Checking host build dependencies..."
    local MISSING=()
    for T in gcc g++ make git wget tar bison flex perl makeinfo; do
        command -v "$T" &>/dev/null || MISSING+=("$T")
    done
    if [ ${#MISSING[@]} -gt 0 ]; then
        log_err "Missing host packages: ${MISSING[*]}"
        log_err "Install with: sudo apt-get install -y build-essential git wget bison flex perl texinfo"
        exit 1
    fi
    log_info "All host dependencies present."
}

# ---------------------------------------------------------------------------
fetch_musl_cross_make() {
    if [ -d "$MCM_DIR/.git" ]; then
        log_info "musl-cross-make already cloned — pulling latest..."
        git -C "$MCM_DIR" pull --ff-only || true
    else
        log_info "Cloning musl-cross-make..."
        git clone --depth=1 https://github.com/richfelker/musl-cross-make.git "$MCM_DIR"
    fi
}

# ---------------------------------------------------------------------------
prefetch_sources() {
    local S="$MCM_DIR/sources"
    mkdir -p "$S"
    log_info "Pre-fetching toolchain sources..."

    # GCC and toolchain libraries
    [ -f "$S/gcc-${GCC_VER}.tar.xz" ]               || wget -q --show-progress "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"               -P "$S"
    [ -f "$S/binutils-${BINUTILS_VER}.tar.gz" ]      || wget -q --show-progress "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.gz"               -P "$S"
    [ -f "$S/musl-${MUSL_VER}.tar.gz" ]              || wget -q --show-progress "https://musl.libc.org/releases/musl-${MUSL_VER}.tar.gz"                         -P "$S"
    [ -f "$S/gmp-6.3.0.tar.xz" ]                    || wget -q --show-progress "https://ftpmirror.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz"                             -P "$S"
    [ -f "$S/mpfr-4.2.2.tar.xz" ]                   || wget -q --show-progress "https://ftpmirror.gnu.org/gnu/mpfr/mpfr-4.2.2.tar.xz"                           -P "$S"
    [ -f "$S/mpc-1.3.1.tar.gz" ]                    || wget -q --show-progress "https://ftpmirror.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz"                              -P "$S"
    [ -f "$S/linux-headers-4.19.88-2.tar.xz" ]      || wget -q --show-progress "https://ftp.barfooze.de/pub/sabotage/tarballs/linux-headers-4.19.88-2.tar.xz"  -P "$S"

    log_info "All sources present."
}

# ---------------------------------------------------------------------------
build_toolchain() {
    log_info "Writing config.mak..."
    cat > "$MCM_DIR/config.mak" << EOF
TARGET      = $TARGET
OUTPUT      = $TOOLCHAIN_DIR
GCC_VER     = $GCC_VER
MUSL_VER    = $MUSL_VER
BINUTILS_VER = $BINUTILS_VER
DL_CMD      = wget -c -q
# Minimal GCC: C + C++ only, static host libs so the toolchain is self-contained
GCC_CONFIG  += --enable-languages=c,c++ --disable-nls --disable-multilib
# Pre-fetched sources directory
SOURCES     = $MCM_DIR/sources
EOF

    rm -rf "$MCM_DIR/build"   # clean any partial previous build
    log_info "Building toolchain (GCC $GCC_VER + musl $MUSL_VER) — this takes 15-25 minutes..."
    cd "$MCM_DIR"
    make -j"$(nproc)" 2>&1 | tee -a /tmp/musl_make.log
    log_info "Installing toolchain to $TOOLCHAIN_DIR..."
    make install
    cd "$WORKSPACE_ROOT"
}

# ---------------------------------------------------------------------------
verify_toolchain() {
    local GCC="$TOOLCHAIN_DIR/bin/$TARGET-gcc"
    if [ ! -x "$GCC" ]; then
        log_err "Toolchain install failed — $GCC not found"
        exit 1
    fi
    log_info "Toolchain ready:  $GCC"
    log_info "  GCC version: $($GCC --version | head -1)"
    echo ""
    log_info "Add to PATH (add to ~/.bashrc to persist):"
    echo "  export PATH=\"$TOOLCHAIN_DIR/bin:\$PATH\""
    echo "  export MUSL_CC=\"$GCC\""
}

# ---------------------------------------------------------------------------
main() {
    log_info "=== BitOS v2.0: musl-libc Cross-Compile Toolchain ==="
    log_info "Target:    $TARGET"
    log_info "GCC:       $GCC_VER"
    log_info "musl:      $MUSL_VER"
    log_info "Output:    $TOOLCHAIN_DIR"
    echo ""

    check_host_deps
    mkdir -p "$BUILD_DIR" "$TOOLCHAIN_DIR"
    fetch_musl_cross_make
    prefetch_sources
    build_toolchain
    verify_toolchain

    log_info "=== Toolchain build complete ==="
    log_info "Next: bash scripts/build_musl_packages.sh"
}

main "$@"
