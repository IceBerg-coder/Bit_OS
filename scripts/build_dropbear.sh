#!/bin/bash
source scripts/common.sh

DROPBEAR_VERSION="2022.83"
DROPBEAR_TAR="dropbear-${DROPBEAR_VERSION}.tar.bz2"
DROPBEAR_URL="https://matt.ucc.asn.au/dropbear/releases/${DROPBEAR_TAR}"
DROPBEAR_SRC="$SRC_DIR/dropbear-${DROPBEAR_VERSION}"
DROPBEAR_OUT="$BUILD_DIR/dropbear"

mkdir -p "$SRC_DIR" "$DROPBEAR_OUT"

# Download
if [ ! -f "$SRC_DIR/$DROPBEAR_TAR" ]; then
    log_info "Downloading Dropbear ${DROPBEAR_VERSION}..."
    wget -q --show-progress "$DROPBEAR_URL" -O "$SRC_DIR/$DROPBEAR_TAR"
fi

# Extract
if [ ! -d "$DROPBEAR_SRC" ]; then
    log_info "Extracting Dropbear..."
    tar -xf "$SRC_DIR/$DROPBEAR_TAR" -C "$SRC_DIR"
fi

cd "$DROPBEAR_SRC"

# Configure with static linking, minimal features
log_info "Configuring Dropbear (static)..."
./configure \
    --prefix="$DROPBEAR_OUT" \
    --disable-zlib \
    --disable-pam \
    --disable-wtmp \
    --disable-lastlog \
    --enable-bundled-libtom \
    LDFLAGS="-static" \
    CFLAGS="-Os" \
    2>&1 | tail -5

# Build only dropbear server and dropbearkey
log_info "Building Dropbear..."
make PROGRAMS="dropbear dropbearkey" -j$(nproc) 2>&1 | tail -5

# Install
log_info "Installing Dropbear to $DROPBEAR_OUT..."
make PROGRAMS="dropbear dropbearkey" install 2>&1 | tail -3

log_info "Dropbear built: $(ls -lh $DROPBEAR_OUT/sbin/dropbear)"
