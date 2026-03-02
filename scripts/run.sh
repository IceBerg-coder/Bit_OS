#!/bin/bash
# Consolidated launch script for BitOS

# Run QEMU with ISO boot and port forwarding
# Port mappings:
#   host:2222 -> BitOS:22  (SSH  - ssh root@localhost -p 2222)
#   host:2323 -> BitOS:23  (Telnet)
#   host:8180 -> BitOS:80  (HTTP - http://localhost:8180)
qemu-system-x86_64 \
    -cdrom output/bitos.iso \
    -m 256M \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2323-:23,hostfwd=tcp::8180-:80
    -drive file=output/storage.img,format=raw,if=virtio
