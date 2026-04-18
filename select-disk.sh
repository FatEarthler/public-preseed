#!/bin/sh

# --- Konfiguration ---
LOG_TERM="/dev/tty3"
LOG_FILE="/tmp/disk-select.log"

# --- Helper: Log Funktion ---
log() {
    MSG="DISK-SELECT: $1"
    # 1. Auf den Bildschirm schreiben (tty3)
    echo "$MSG" > "$LOG_TERM"
    # 2. In die Datei schreiben (für spätere Analyse)
    echo "$MSG" >> "$LOG_FILE"
}

log "=== Start Disk Selection Script ==="


log "=== START: Boot Device Detection ==="

# --- 1. Versuch: Erkennung über Label (/dev/disk/by-label) ---
# Die meisten Installer-Sticks haben ein Label (z.B. "DEBIAN_12", "KALI")
BOOT_DEV_RAW=""
if ls /dev/disk/by-label/* 2>&1; then
    # Nimm das erste gefundene Label und löse es zum echten Device auf
    BOOT_DEV_RAW=$(readlink -f /dev/disk/by-label/* 2>/dev/null | head -n1)
    if [ -n "$BOOT_DEV_RAW" ]; then
        log "Found boot device via Label: $BOOT_DEV_RAW"
    fi
fi

# --- 2. Versuch: Erkennung über Mount-Punkt (/isodevice) ---
# Falls kein Label da ist, prüfen wir, wo das ISO gemountet ist
if [ -z "$BOOT_DEV_RAW" ]; then
    MOUNT_LINE=$(mount | grep '/isodevice')
    if [ -n "$MOUNT_LINE" ]; then
        BOOT_DEV_RAW=$(echo "$MOUNT_LINE" | awk '{print $1}')
        log "Found boot device via Mount (/isodevice): $BOOT_DEV_RAW"
    fi
fi

# --- Fallback Warnung ---
if [ -z "$BOOT_DEV_RAW" ]; then
    log "WARNING: Could not automatically detect boot device!"
    log "Proceeding with empty BOOT_DISK. RISK OF DATA LOSS on first disk."
    # Wir setzen es nicht auf einen festen Wert, um Fehler zu erzwingen, falls nichts gefunden wird
    BOOT_DISK=""
else
    # --- 3. Normalisierung: Von Partition zur Basis-Disk ---
    BOOT_NAME=$(basename "$BOOT_DEV_RAW")
    log "Raw boot device name: $BOOT_NAME"

    BOOT_DISK=""
    
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
    # Wir speichern das Ergebnis in einer Variable, die wir später nutzen können
    # Oder wir setzen es direkt als Umgebungsvariable für nachfolgende Schritte (falls in einem Script)
    # Für jetzt loggen wir es nur und setzen es als Test auf partman-auto/disk (nur zum Verifizieren!)
    # ACHTUNG: Hier setzen wir noch NICHT partman-auto/disk, da wir erst die Ziel-Disk finden müssen!
    # Aber wir können es als Referenz speichern:
    echo "$BOOT_DISK" > /tmp/boot_disk_name.txt
    log "Boot disk name saved to /tmp/boot_disk_name.txt"
else
    log "ERROR: Boot disk detection failed completely."
fi

log "=== END: Boot Device Detection ==="



# --- 1. Einfache Zielsetzung (Ihr Test-Setup) ---
# Hier später die komplexe Logik einfügen
TARGET_DISK="/dev/sdq"

log "Setting target disk to: $TARGET_DISK"

# Prüfen, ob das Gerät existiert
if [ ! -b "$TARGET_DISK" ]; then
    log "ERROR: Device $TARGET_DISK does not exist!"
    # Liste verfügbare Devices zur Fehlersuche
    log "Available block devices:"
    ls /dev/sd* /dev/nvme* 2>/dev/null >> "$LOG_FILE"
    ls /dev/sd* /dev/nvme* 2>/dev/null > "$LOG_TERM"
else
    log "Device $TARGET_DISK found. Setting debconf variable."
    # Die eigentliche Magie: Variable setzen
    debconf-set partman-auto/disk "$TARGET_DISK"
    log "SUCCESS: partman-auto/disk set to $TARGET_DISK"
fi

log "=== End Disk Selection Script ==="
