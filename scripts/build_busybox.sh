#!/bin/bash
source scripts/common.sh

log_info "Downloading Busybox source code..."
cd "$SRC_DIR"
if [ ! -f busybox-$BUSYBOX_VERSION.tar.bz2 ]; then
    wget https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2
fi

log_info "Extracting Busybox..."
if [ ! -d busybox-$BUSYBOX_VERSION ]; then
    tar xjf busybox-$BUSYBOX_VERSION.tar.bz2
fi

cd "$SRC_DIR/busybox-$BUSYBOX_VERSION"
log_info "Configuring Busybox: Using default defconfig with static linking"
make defconfig
# Disable tc to avoid build errors with newer kernels/toolchains
sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
# Enable static linking - critical for a simple initrd-based OS
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

log_info "Building Busybox..."
make -j$(nproc)
make install
log_info "Busybox built and installed to _install"
