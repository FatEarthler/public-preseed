#!/bin/sh

# --- get disk size in mb ---
get_size_mb() {
    blockdev --getsize64 "$1" 2>/dev/null | awk '{print int($1/1048576)}'
}

# --- Test if usb device ---
is_usb() {
    local DEV=$1
    # Check Transport Attribute
    if [ -f "/sys/block/$DEV/device/transport" ]; then
        local TRANS=$(cat "/sys/block/$DEV/device/transport" 2>/dev/null)
        if [ "$TRANS" = "usb" ]; then return 0; fi
    fi
    # Check Sysfs Path
    local DEVPATH=$(readlink -f "/sys/block/$DEV" 2>/dev/null)
    if echo "$DEVPATH" | grep -q "/usb"; then return 0; fi
    return 1
}

# Durchlaufe ALLE Block-Geräte im System
for dev_path in /sys/block/*; do
    echo $dev_path
    DEV_NAME=$(basename "$dev_path")
    echo $DEV_NAME
    DISK="/dev/$DEV_NAME"
    echo $DISK

    # 1. Filter: Ist es ein Block Device?
    if [ ! -b "$DISK" ]; then continue; fi
    echo "$DISK is block device"

    # 2. Filter: Ignoriere System-Geräte (RAM, Loop, CD-ROM)
    if echo "$DEV_NAME" | grep -qE '^(ram|loop|sr|md)'; then
        echo "Skipping system device: $DISK"
        continue
    fi

    # 4. Filter: Ignoriere USB-Geräte (nur bei sdX relevant, NVMe ist nie USB)
    # Wir prüfen es zur Sicherheit bei allen, aber es betrifft meist nur sdX
    if is_usb "$DEV_NAME"; then
        echo "Skipping USB device: $DISK"
        continue
    fi

    # Wenn wir hier sind, ist es eine potenzielle Ziel-Disk
    SIZE=$(get_size_mb "$DISK")
    if [ -z "$SIZE" ] || [ "$SIZE" -eq 0 ]; then
        echo "Skipping $DISK (Size unknown or 0)"
        continue
    fi

    # Typ bestimmen (NVMe vs SSD vs HDD)
    TYPE=3 # Default: HDD
    if echo "$DEV_NAME" | grep -q '^nvme'; then
        TYPE=1 # NVMe
	echo "$DEV_NAME is NVMe"
    else
        # Prüfe rotational für SATA/VirtIO/etc
        ROT=$(cat "/sys/block/$DEV_NAME/queue/rotational" 2>/dev/null)
        if [ "$ROT" = "0" ]; then
            TYPE=2 # SSD
	    echo "$DEV_NAME is SSD"
        else
            TYPE=3 # HDD
	    echo "$DEV_NAME is HDD"
        fi
    fi

    echo "Found candidate: $DEV_NAME (${SIZE}MB, Type: $TYPE)"
    CANDIDATES="$CANDIDATES
$SIZE $DEV_NAME $TYPE"
done
echo $CANDIDATES
