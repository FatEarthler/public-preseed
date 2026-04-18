#!/bin/sh

# --- Configuration ---
LOG_TERM="/dev/tty3"
LOG_FILE="/tmp/disk-select.log"

# ========================
# === Helper functions ===
# ========================

# --- Log function ---
log() {
    MSG="DISK-SELECT: $1"
    # 1. Print to screen (tty3)
    echo "$MSG" > "$LOG_TERM"
    # 2. Write to logfile
    echo "$MSG" >> "$LOG_FILE"
}

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


log "==================================="
log "=== Start Disk Selection Script ==="
log "==================================="
log "Log messages will be written to tty3 and $LOG_FILE"

# =============================
# === Boot device detection ===
# =============================
log "=== START: Boot Device Detection ==="

# --- Identify by label (/dev/disk/by-label) ---
# Die meisten Installer-Sticks haben ein Label (z.B. "DEBIAN_12", "KALI")
BOOT_DEV_RAW=""
log "Checking /dev/disk/by-label"
if ls /dev/disk/by-label/* >/dev/null 2>&1; then
    # Nimm das erste gefundene Label und löse es zum echten Device auf
    BOOT_DEV_RAW=$(readlink -f /dev/disk/by-label/* 2>/dev/null | head -n1)
    if [ -n "$BOOT_DEV_RAW" ]; then
        log "Found boot device via Label: $BOOT_DEV_RAW"
    fi
else
	log "No disks found by label"
fi

# --- Identify via mount points ---
log "Checking mount points"
if [ -z "$BOOT_DEV_RAW" ]; then
    # Check for presence of /isodevice (standard for USB installations)
    if mount | grep -q '/isodevice'; then
        BOOT_DEV_RAW=$(mount | grep '/isodevice' | awk '{print $1}')
        log "Found boot device via /isodevice: $BOOT_DEV_RAW"
    # Check for presence of /cdrom (standard for ISO/VM installations)
    elif mount | grep -q '/cdrom'; then
        BOOT_DEV_RAW=$(mount | grep '/cdrom' | awk '{print $1}')
        log "Found boot device via /cdrom: $BOOT_DEV_RAW"
    # Check if /dev/sr0 is mounted (often the case for VMs)
    else
        if [ -b "/dev/sr0" ]; then
             BOOT_DEV_RAW="/dev/sr0"
             log "Fallback: Assuming /dev/sr0 is boot device."
        fi
    fi
fi

# --- Fallback warning ---
BOOT_DISK=""
if [ -z "$BOOT_DEV_RAW" ]; then
    log "WARNING: Could not automatically detect boot device!"
    log "Proceeding with empty BOOT_DISK. RISK OF DATA LOSS on first disk."
else
    # Normalizing from partition name to disk name
    BOOT_NAME=$(basename "$BOOT_DEV_RAW")
    log "Raw boot device name: $BOOT_NAME"

    # Fall A: NVMe Partition (z.B. nvme0n1p2 -> nvme0n1)
    # Muster: nvme[Nummer]n[Nummer]p[Nummer]
    if echo "$BOOT_NAME" | grep -qE '^nvme[0-9]+n[0-9]+p[0-9]+'; then
        BOOT_DISK=$(echo "$BOOT_NAME" | sed 's/p[0-9]*$//')
        log "Detected NVMe partition. Normalized to: $BOOT_DISK"
    
    # Fall B: SATA/SCSI/USB Partition (z.B. sda1, sdb4 -> sda, sdb)
    # Muster: sd[Buchstabe][Nummer]
    elif echo "$BOOT_NAME" | grep -qE '^sd[a-z][0-9]+'; then
        BOOT_DISK=$(echo "$BOOT_NAME" | sed 's/[0-9]*$//')
        log "Detected SATA/USB partition. Normalized to: $BOOT_DISK"
    
    # Fall C: Es ist bereits eine Basis-Disk (z.B. nvme0n1, sr0)
    else
        BOOT_DISK="$BOOT_NAME"
        log "Device appears to be a base disk already: $BOOT_DISK"
    fi
fi

# --- 4. Ergebnis ausgeben ---
if [ -n "$BOOT_DISK" ]; then
    log "SUCCESS: Boot Base Disk identified as: /dev/$BOOT_DISK"
else
    log "ERROR: Boot disk detection failed completely."
fi

log "=== END: Boot Device Detection ==="

# ==============================
# === Target disk candidates ===
# ==============================

# Candidate file
# Format: "SIZE_MB NAME TYPE_PRIORITY"
# Typ: 1=NVMe, 2=SSD (SATA/VirtIO non-rot), 3=HDD (rotational)
CANDIDATE_FILE="/tmp/candidates.txt"
> "$CANDIDATE_FILE" # Datei leer machen

# Durchlaufe ALLE Block-Geräte im System
log "=== START: Candidate identification ==="
for dev_path in /sys/block/*; do
    DEV_NAME=$(basename "$dev_path")
    DISK="/dev/$DEV_NAME"

    # 1. Filter: Ist es ein Block Device?
    if [ ! -b "$DISK" ]; then continue; fi

    # 2. Filter: Ignoriere das BOOT-GERÄT
    if [ -n "$BOOT_DISK" ] && [ "$DEV_NAME" = "$BOOT_DISK" ]; then
        log "Skipping BOOT device: $DEV_NAME"
        continue
    fi

    # 3. Filter: Ignoriere System-Geräte (RAM, Loop, CD-ROM)
    if echo "$DEV_NAME" | grep -qE '^(ram|loop|sr|md)'; then
        log "Skipping system device: $DEV_NAME"
        continue
    fi

    # 4. Filter: Ignoriere USB-Geräte (nur bei sdX relevant, NVMe ist nie USB)
    # Wir prüfen es zur Sicherheit bei allen, aber es betrifft meist nur sdX
    if is_usb "$DEV_NAME"; then
        log "Skipping USB device: $DEV_NAME"
        continue
    fi

    # Wenn wir hier sind, ist es eine potenzielle Ziel-Disk
    SIZE=$(get_size_mb "$DISK")
    if [ -z "$SIZE" ] || [ "$SIZE" -eq 0 ]; then
        log "Skipping $DEV_NAME (Size unknown or 0)"
        continue
    fi

    # check minimum disk size (20 GB = 20 * 1024 = 20480 MB)
    MIN_SIZE_MB=20000
    if [ -z "$SIZE" ] || [ "$SIZE" -lt "$MIN_SIZE_MB" ]; then
        log "Skipping $DEV_NAME (Size: ${SIZE}MB is below minimum ${MIN_SIZE_MB}MB)"
        continue
    fi

    # Typ bestimmen (NVMe vs SSD vs HDD)
    TYPE=3 # Default: HDD
    if echo "$DEV_NAME" | grep -q '^nvme'; then
        TYPE=1 # NVMe
    else
        # Prüfe rotational für SATA/VirtIO/etc
        ROT=$(cat "/sys/block/$DEV_NAME/queue/rotational" 2>/dev/null)
        if [ "$ROT" = "0" ]; then
            TYPE=2 # SSD
        else
            TYPE=3 # HDD
        fi
    fi

    log "Found candidate: $DEV_NAME (${SIZE}MB, Type: $TYPE)"
    echo "$SIZE $DEV_NAME $TYPE" >> "$CANDIDATE_FILE"
done
# --- Anzeige der Kandidaten (Debug) ---
log "Raw candidates list:"
cat "$CANDIDATE_FILE" > "$LOG_TERM" # Zeigt die Liste sauber auf TTY3
cat "$CANDIDATE_FILE" >> "$LOG_FILE"
log "=== END: Candidate identification ==="

# =============================
# === Target disk selection ===
# =============================
log "=== START: Candidate selection ==="
# Sortiere nach: 1. Typ (aufsteigend), 2. Größe (aufsteigend)
BEST_MATCH=$(sort -k3,3n -k1,1n "$CANDIDATE_FILE" | head -n1)

TARGET=""
if [ -n "$BEST_MATCH" ]; then
    TARGET_NAME=$(echo "$BEST_MATCH" | awk '{print $2}')
    TARGET="/dev/$TARGET_NAME"
    log "SELECTED TARGET: $TARGET (Size: $(echo $BEST_MATCH | awk '{print $1}')MB, Type: $(echo $BEST_MATCH | awk '{print $3}'))"
    
    log "Identified $TARGET as installation target"
else
    log "ERROR: No suitable target disk found!"
    log "Candidates were: $CANDIDATES"
    log "Boot Disk was: $BOOT_DISK"
fi

log "=== END: Candidate selection ==="

# ================================
# === Setting partman variable ===
# ================================
# Prüfen, ob das Gerät existiert
log "=== START: debconf-set ==="
log "executing 'debconf-set partman-auto/disk $TARGET'"
if [ ! -b "$TARGET" ]; then
    log "ERROR: Device $TARGET does not exist!"
    # Liste verfügbare Devices zur Fehlersuche
    log "Available block devices:"
    ls /dev/sd* /dev/nvme* 2>/dev/null >> "$LOG_FILE"
    ls /dev/sd* /dev/nvme* 2>/dev/null > "$LOG_TERM"
else
    log "Device $TARGET_DISK found. Setting debconf variable."
    # Die eigentliche Magie: Variable setzen
    debconf-set partman-auto/disk "$TARGET"
    log "SUCCESS: partman-auto/disk set to $TARGET"
fi

log "=== END: debconf-set ==="

log "=== End Disk Selection Script ==="
