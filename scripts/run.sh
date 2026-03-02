#!/bin/bash
# Consolidated launch script for BitOS
# Port mappings:
#   host:2222 -> BitOS:22  (SSH   - ssh root@localhost -p 2222)
#   host:2323 -> BitOS:23  (Telnet)
#   host:8180 -> BitOS:80  (HTTP  - http://localhost:8180)
#   host:8443 -> BitOS:443 (HTTPS - https://localhost:8443)

STORAGE_IMG="output/storage.img"
[ ! -f "$STORAGE_IMG" ] && echo "[!] No storage.img found. Run: bash scripts/create_storage.sh" && STORAGE_IMG=""

# Direct kernel boot — always picks up the latest vmlinuz + initramfs.cpio.gz
# (avoids stale ISO issues; matches kernel cmdline from build_iso.sh)
qemu-system-x86_64 \
    -kernel output/vmlinuz \
    -initrd output/initramfs.cpio.gz \
    -append "console=ttyS0 console=tty1 quiet" \
    -m 256M \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2323-:23,hostfwd=tcp::8180-:80,hostfwd=tcp::8443-:443 \
    ${STORAGE_IMG:+-drive file=$STORAGE_IMG,format=raw,if=virtio}
