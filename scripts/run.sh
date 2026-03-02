#!/bin/bash
# consolidated launch script for BitOS

# Ensure we have a storage disk
if [ ! -f "output/storage.img" ]; then
    echo "Creating new 64MB storage disk..."
    dd if=/dev/zero of=output/storage.img bs=1M count=64
    mkfs.ext4 output/storage.img
fi

# Rebuild the image
./scripts/create_image.sh

# Run QEMU
qemu-system-x86_64 \
    -kernel output/vmlinuz \
    -initrd output/initramfs.cpio.gz \
    -append "console=ttyS0 quiet" \
    -nographic \
    -net nic -net user \
    -drive file=output/storage.img,format=raw,if=virtio
