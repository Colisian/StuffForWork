#!/bin/bash
# 
# Homebrew Metadata Update via Jamf (update only, no upgrade)

LOG_DIR="/var/log/jamf_brew"
LOG_FILE="$LOG_DIR/brew_update.log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}

CURRENT_USER=$(stat -f "%Su" /dev/console)

if [[ -z "$CURRENT_USER" || "$CURRENT_USER" == "root" ]]; then
    log "ERROR: No standard user is logged in. Skipping."
    exit 1
fi

log "INFO: Logged-in user detected: $CURRENT_USER"

if [[ -x "/opt/homebrew/bin/brew" ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
elif [[ -x "/usr/local/bin/brew" ]]; then
    BREW_BIN="/usr/local/bin/brew"
else
    log "ERROR: Homebrew binary not found. Is Homebrew installed?"
    exit 2
fi

log "INFO: Brew binary located at $BREW_BIN"

log "INFO: Starting brew update..."
su - "$CURRENT_USER" -c "$BREW_BIN update" >> "$LOG_FILE" 2>&1
UPDATE_EXIT=$?

if [[ $UPDATE_EXIT -ne 0 ]]; then
    log "WARNING: brew update exited with code $UPDATE_EXIT"
fi

log "INFO: Running brew cleanup..."
su - "$CURRENT_USER" -c "$BREW_BIN cleanup" >> "$LOG_FILE" 2>&1

log "INFO: Homebrew metadata update complete."
exit 0