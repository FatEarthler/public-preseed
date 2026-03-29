#!/bin/sh
# File: select-disk.sh
# Purpose: Detect SSD, exclude USB boot media, and set partman-auto/disk

log() {
    echo "[$(date)] $1" >> /var/log/disk-selection.log
    echo "$1"
}

log "Starting disk selection script..."

# 1. Identify the boot device (USB Stick)
# In Debian installer, the ISO/USB is usually mounted at /cdrom
BOOT_DEV=""
if mount | grep -q '/cdrom'; then
    # Extract device name (e.g., /dev/sdb1 -> sdb)
    BOOT_DEV=$(mount | grep '/cdrom' | awk '{print $1}' | sed 's|/dev/||' | sed 's|[0-9]*$||')
    log "Detected boot device: $BOOT_DEV"
fi

# 2. Find the best target disk
TARGET_DISK=""
SSD_FOUND=0

# Iterate over all block devices (SATA and NVMe)
for dev_path in /sys/block/sd* /sys/block/nvme*; do
    [ -d "$dev_path" ] || continue
    
    dev_name=$(basename "$dev_path")
    
    # Safety: Skip if we can't determine name
    [ -z "$dev_name" ] && continue

    # Skip the boot device
    if [ "$dev_name" = "$BOOT_DEV" ]; then
        log "Skipping boot device: $dev_name"
        continue
    fi
    
    # Check rotational status (0 = SSD/NVMe, 1 = HDD)
    if [ -f "$dev_path/queue/rotational" ]; then
        is_rotational=$(cat "$dev_path/queue/rotational")
        
        if [ "$is_rotational" -eq 0 ]; then
            # It's an SSD. Pick the first one found.
            # (Optional: Add logic to pick smallest SSD if multiple exist)
            TARGET_DISK="/dev/$dev_name"
            SSD_FOUND=1
            log "Selected SSD: $TARGET_DISK"
            break 
        fi
    fi
done

# 3. Fallback: If no SSD, pick the first non-boot HDD
if [ -z "$TARGET_DISK" ]; then
    log "No SSD found. Searching for HDD..."
    for dev_path in /sys/block/sd*; do
        [ -d "$dev_path" ] || continue
        dev_name=$(basename "$dev_path")
        
        if [ "$dev_name" != "$BOOT_DEV" ]; then
            TARGET_DISK="/dev/$dev_name"
            log "Fallback to HDD: $TARGET_DISK"
            break
        fi
    done
fi

# 4. Apply the selection
if [ -n "$TARGET_DISK" ]; then
    log "Setting partman-auto/disk to $TARGET_DISK"
    debconf-set partman-auto/disk "$TARGET_DISK"
else
    log "ERROR: No suitable disk found! Installation may fail."
    # Optional: Drop to a shell for debugging
    # debconf-set debian-installer/exit-on-error false
fi

log "Disk selection script finished."
