#!/bin/bash
source scripts/common.sh

log_info "Preparing ISO files..."
ISO_PATH="$BUILD_DIR/iso"
mkdir -p "$ISO_PATH/isolinux"

# Copy kernel and initramfs INTO isolinux/ directory so ISOLINUX can find them
cp "$OUTPUT_DIR/vmlinuz" "$ISO_PATH/isolinux/vmlinuz"
cp "$OUTPUT_DIR/initramfs.cpio.gz" "$ISO_PATH/isolinux/initramfs.cpio.gz"

# Copy ISOLINUX binaries from system (typical Debian/Ubuntu path)
ISOLINUX_BIN="/usr/lib/ISOLINUX/isolinux.bin"
LDLINUX_C32="/usr/lib/syslinux/modules/bios/ldlinux.c32"

if [ ! -f "$ISOLINUX_BIN" ]; then
    # Fallback to alternate paths if not found
    ISOLINUX_BIN=$(find /usr/lib -name isolinux.bin | head -n 1)
    LDLINUX_C32=$(find /usr/lib -name ldlinux.c32 | head -n 1)
fi

if [ -z "$ISOLINUX_BIN" ] || [ ! -f "$ISOLINUX_BIN" ]; then
    log_err "isolinux.bin not found. Please install 'isolinux' and 'syslinux-common' packages."
    exit 1
fi

cp "$ISOLINUX_BIN" "$ISO_PATH/isolinux/isolinux.bin"
cp "$LDLINUX_C32" "$ISO_PATH/isolinux/ldlinux.c32"

# Ensure isolinux directory exists and write config
mkdir -p "$ISO_PATH/isolinux"
cat << 'EOF' > "$ISO_PATH/isolinux/isolinux.cfg"
DEFAULT bitos
TIMEOUT 50
PROMPT 0

LABEL bitos
    KERNEL vmlinuz
    APPEND initrd=initramfs.cpio.gz console=ttyS0 console=tty1 quiet
EOF

log_info "Generating ISO image..."

# Create GRUB config for both BIOS and EFI boot
mkdir -p "$ISO_PATH/boot/grub"
cat << 'EOF' > "$ISO_PATH/boot/grub/grub.cfg"
set default=0
set timeout=3

menuentry "BitOS Professional Edition" {
    linux /isolinux/vmlinuz console=ttyS0 console=tty1 quiet
    initrd /isolinux/initramfs.cpio.gz
}

menuentry "BitOS (verbose boot)" {
    linux /isolinux/vmlinuz console=ttyS0 console=tty1
    initrd /isolinux/initramfs.cpio.gz
}
EOF

if command -v grub-mkrescue >/dev/null 2>&1; then
    log_info "Building hybrid BIOS+EFI ISO with grub-mkrescue..."
    grub-mkrescue -o "$OUTPUT_DIR/bitos.iso" "$ISO_PATH" 2>&1
else
    log_info "grub-mkrescue not found, falling back to genisoimage (BIOS only)..."
    genisoimage -o "$OUTPUT_DIR/bitos.iso" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -R -J "$ISO_PATH"
fi

log_info "ISO created at $OUTPUT_DIR/bitos.iso"
