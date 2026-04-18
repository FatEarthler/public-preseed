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

# --- 1. Einfache Zielsetzung (Ihr Test-Setup) ---
# Hier später die komplexe Logik einfügen
TARGET_DISK="/dev/sdc"

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
