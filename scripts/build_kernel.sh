#!/bin/bash
source scripts/common.sh

log_info "Downloading Linux Kernel source code..."
cd "$SRC_DIR"
if [ ! -f linux-$KERNEL_VERSION.tar.xz ]; then
    wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz
fi

log_info "Extracting Linux Kernel..."
if [ ! -d linux-$KERNEL_VERSION ]; then
    tar xJf linux-$KERNEL_VERSION.tar.xz
fi

cd "$SRC_DIR/linux-$KERNEL_VERSION"
log_info "Configuring Linux Kernel..."
make x86_64_defconfig
# Enable full iptables/netfilter support
scripts/config --enable NETFILTER_ADVANCED
scripts/config --enable NF_CONNTRACK
scripts/config --enable NF_CONNTRACK_IPV4
scripts/config --enable IP_NF_IPTABLES
scripts/config --enable IP_NF_FILTER
scripts/config --enable IP_NF_TARGET_REJECT
scripts/config --enable NF_NAT
scripts/config --enable NETFILTER_XT_MATCH_STATE
scripts/config --enable NETFILTER_XT_MATCH_CONNTRACK
scripts/config --enable NETFILTER_XT_TARGET_LOG
scripts/config --enable NETFILTER_XT_MATCH_RECENT
scripts/config --enable NETFILTER_XT_MATCH_LIMIT
scripts/config --enable NETFILTER_XT_MATCH_HASHLIMIT
make olddefconfig
log_info "Building Linux Kernel - this may take some time..."
make -j$(nproc) bzImage
make -j$(nproc) modules
INSTALL_MOD_PATH="$(pwd)/../../build/initramfs" make modules_install
log_info "Kernel and modules built successfully!"
