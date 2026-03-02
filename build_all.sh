#!/bin/bash
source scripts/common.sh

log_info "Welcome to the Bit OS build script!"
log_info "This script will compile the Kernel, BusyBox, and create a bootable image."

echo "Press ENTER to start the build process..."
read

./scripts/build_busybox.sh
./scripts/build_kernel.sh
./scripts/build_openssh.sh
./scripts/create_image.sh

log_info "Build process complete!"
log_info "Kernel: $OUTPUT_DIR/vmlinuz"
log_info "Initrd: $OUTPUT_DIR/initramfs.cpio.gz"
log_info "To boot with QEMU, run: qemu-system-x86_64 -kernel output/vmlinuz -initrd output/initramfs.cpio.gz -append 'console=ttyS0' -nographic"
