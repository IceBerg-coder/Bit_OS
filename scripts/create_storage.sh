#!/bin/bash
source scripts/common.sh

STORAGE_IMG="$OUTPUT_DIR/storage.img"
STORAGE_SIZE_MB=128

if [ -f "$STORAGE_IMG" ]; then
    log_info "Storage image already exists: $STORAGE_IMG ($(ls -lh $STORAGE_IMG | awk '{print $5}'))"
    log_info "To recreate: rm $STORAGE_IMG && bash scripts/create_storage.sh"
    exit 0
fi

log_info "Creating persistent storage image (${STORAGE_SIZE_MB}MB)..."
dd if=/dev/zero of="$STORAGE_IMG" bs=1M count=$STORAGE_SIZE_MB status=progress
mkfs.ext4 -L "BitOS_Data" -m 1 -F "$STORAGE_IMG"

log_info "Pre-populating storage with home directories..."
MOUNT_TMP=$(mktemp -d)
sudo mount -o loop "$STORAGE_IMG" "$MOUNT_TMP"
sudo mkdir -p "$MOUNT_TMP/root" "$MOUNT_TMP/kaung" "$MOUNT_TMP/bin"
sudo chown -R 1000:1000 "$MOUNT_TMP/kaung" 2>/dev/null
sudo umount "$MOUNT_TMP"
rmdir "$MOUNT_TMP"

log_info "Storage image created: $STORAGE_IMG"
log_info "Run scripts/run.sh to boot with persistent storage attached"
