#!/bin/bash
#===============================================================================
# Script      : install_umd_library_printers.sh
# Description : Installs the UMD Library Pharos print queues (Canon UFR II
#               driver) on Jamf-managed macOS devices. Idempotent: removes and
#               recreates all LIB- queues on every run, so it is safe to use
#               for both first-time setup and repair (Self Service or policy).
# Requires    : Pharos Popup.pkg and the Canon UFR II driver pkg must already
#               be installed (deploy them in the same policy with priority
#               "Before", or via an earlier policy).
# Author      : Colis McLeod (cmcleod1@umd.edu)
# Date        : 2026-07-02
# Version     : 5.0
#
# Jamf script parameters:
#   $1-$3  Reserved by Jamf (mount point, computer name, username) - unused
#   $4     Optional: Pharos server FQDN (default: LIBRPS406DV.AD.UMD.EDU)
#   $5     Optional: Pharos popup port  (default: 515)
# No parameters are required; running with defaults installs the full
# production queue set.
#
# Exit codes: 0 = all queues installed, 1 = one or more failures
#===============================================================================

set -euo pipefail

#--- Configuration -------------------------------------------------------------

LOG_FILE="/var/log/umd_printer_install.log"
PHAROS_SERVER="${4:-LIBRPS406DV.AD.UMD.EDU}"
PHAROS_PORT="${5:-515}"
POPUP_BACKEND="/usr/libexec/cups/backend/popup"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
# imageRUNNER ADVANCE C5030/C5035 series PPD shipped by the Canon UFR II pkg
TARGET_PPD="$PPD_DIR/CNPZUIRAC5030ZU.ppd.gz"

# Known executable paths inside the Pharos Popup.app bundle (name casing has
# varied between Pharos releases, so both are checked).
PHAROS_POPUP_CANDIDATES=(
    "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/Popup"
    "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/popup"
    "/Applications/Pharos/Popup.app/Contents/MacOS/Popup"
    "/Applications/Popup.app/Contents/MacOS/Popup"
)

# Queue definitions: name|location|type
# Names must match the Pharos server queue names exactly.
PRINTERS=(
    "LIB-ArchMobileBW|Architecture Library|Black & White"
    "LIB-ArchMobileColor|Architecture Library|Color"
    "LIB-ArtMobileBW|Art Library|Black & White"
    "LIB-ArtMobileColor|Art Library|Color"
    "LIB-EPSLMobileBW|EPSL Library|Black & White"
    "LIB-EPSLMobileColor|EPSL Library|Color"
    "LIB-HBKMobileBW|Hornbake Library|Black & White"
    "LIB-HBKMobileColor|Hornbake Library|Color"
    "LIB-MarylandRoomMobileBW|Maryland Room|Black & White"
    "LIB-MarylandRoomMobileColor|Maryland Room|Color"
    "LIB-McKMobileBW|McKeldin Library|Black & White"
    "LIB-McKMobileColor|McKeldin Library|Color"
    "LIB-Mck2FMobileWideFormat|McKeldin Library|Wide Format"
    "LIB-PALMobileBW|PAL Library|Black & White"
    "LIB-PALMobileColor|PAL Library|Color"
)

CANON_PPD=""
SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_PRINTERS=()

#--- Functions ------------------------------------------------------------------

# Emit a timestamped log line (all output is tee'd to LOG_FILE).
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# True if a CUPS destination with this exact name exists.
printer_exists() {
    lpstat -p "$1" >/dev/null 2>&1
}

# Print the names of all installed LIB- queues, one per line.
# awk field match avoids grabbing multi-line status text the way a bare
# grep "LIB-" on lpstat output can.
get_library_printers() {
    lpstat -p 2>/dev/null | awk '$1 == "printer" && $2 ~ /^LIB-/ {print $2}' || true
}

# Wait up to $2 seconds for queue $1 to disappear after lpadmin -x.
wait_for_printer_absent() {
    local name="$1" max_wait="${2:-5}" waited=0
    while printer_exists "$name"; do
        if [ "$waited" -ge "$max_wait" ]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 0
}

# Wait up to $2 seconds for queue $1 to appear after lpadmin -p.
wait_for_printer_present() {
    local name="$1" max_wait="${2:-5}" waited=0
    until printer_exists "$name"; do
        if [ "$waited" -ge "$max_wait" ]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 0
}

# Confirm the CUPS scheduler answers. On macOS cupsd is socket-activated, so
# the first lpstat call normally starts it; the loop only matters if the
# print system is genuinely wedged.
check_cups() {
    local waited=0
    log "Checking print system status..."
    until lpstat -r >/dev/null 2>&1; do
        if [ "$waited" -ge 30 ]; then
            log "ERROR: CUPS scheduler did not respond within 30 seconds"
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    log "   CUPS scheduler is responding"
    return 0
}

# Ensure the Pharos popup CUPS backend exists and is executable.
# The Popup.pkg normally creates it; if only the app bundle is present,
# create the backend symlink ourselves.
verify_popup_backend() {
    log "Verifying Pharos Popup backend..."

    if [ -x "$POPUP_BACKEND" ]; then
        log "   Popup backend already configured: $POPUP_BACKEND"
        if [ -L "$POPUP_BACKEND" ]; then
            log "   -> $(readlink "$POPUP_BACKEND")"
        fi
        return 0
    fi

    local popup_binary=""
    local candidate
    for candidate in "${PHAROS_POPUP_CANDIDATES[@]}"; do
        if [ -f "$candidate" ]; then
            popup_binary="$candidate"
            break
        fi
    done

    # Fall back to searching for the app bundle anywhere Pharos might put it
    if [ -z "$popup_binary" ]; then
        local popup_app
        popup_app="$(find "/Library/Application Support/Pharos" /Applications \
            -maxdepth 3 -name "Popup.app" -type d 2>/dev/null | head -n 1)" || true
        if [ -n "$popup_app" ]; then
            if [ -f "$popup_app/Contents/MacOS/Popup" ]; then
                popup_binary="$popup_app/Contents/MacOS/Popup"
            elif [ -f "$popup_app/Contents/MacOS/popup" ]; then
                popup_binary="$popup_app/Contents/MacOS/popup"
            fi
        fi
    fi

    if [ -z "$popup_binary" ]; then
        log "ERROR: Pharos Popup is not installed (no Popup.app executable found)"
        log "   Deploy Popup.pkg before this script runs."
        log "   Expected: /Library/Application Support/Pharos/Popup.app/Contents/MacOS/Popup"
        if [ -d "/Library/Application Support/Pharos" ]; then
            log "   Pharos directory contents:"
            ls -la "/Library/Application Support/Pharos/" 2>/dev/null | sed 's/^/      /'
        else
            log "   /Library/Application Support/Pharos does not exist"
        fi
        return 1
    fi

    if [ ! -x "$popup_binary" ]; then
        log "   Popup binary found but not executable; fixing..."
        chmod +x "$popup_binary"
    fi

    log "   Creating CUPS backend symlink: $POPUP_BACKEND -> $popup_binary"
    mkdir -p "$(dirname "$POPUP_BACKEND")"
    ln -sf "$popup_binary" "$POPUP_BACKEND"
    # CUPS runs 0755 backends as the unprivileged _lp user, which is what
    # Pharos Popup expects (it needs to reach the user's login session).
    chmod 755 "$POPUP_BACKEND"

    if [ ! -x "$POPUP_BACKEND" ]; then
        log "ERROR: Backend symlink was created but is not executable"
        return 1
    fi

    log "   Popup backend ready"
    return 0
}

# Locate the Canon UFR II PPD. Prefer the exact model PPD, then fall back to
# any Canon UFR II PPD the driver pkg installed. Sets CANON_PPD.
verify_canon_ppd() {
    log "Verifying Canon UFR II driver..."

    if [ -r "$TARGET_PPD" ]; then
        CANON_PPD="$TARGET_PPD"
    else
        CANON_PPD="$(find "$PPD_DIR" -type f \
            \( -name "CNPZ*.ppd.gz" -o -name "*UFRII*.ppd.gz" \) 2>/dev/null \
            | head -n 1)" || true
    fi

    if [ -z "$CANON_PPD" ]; then
        log "ERROR: No Canon PPD found in $PPD_DIR"
        log "   Deploy the Canon UFR II driver pkg before this script runs."
        log "   Canon PPDs currently on disk:"
        find /Library/Printers -type f \( -name "*.ppd.gz" -o -name "*.ppd" \) 2>/dev/null \
            | grep -i canon | sed 's/^/      /' || echo "      (none found)"
        return 1
    fi

    if [ ! -r "$CANON_PPD" ]; then
        log "ERROR: PPD exists but is not readable: $CANON_PPD"
        return 1
    fi

    log "   Using PPD: $(basename "$CANON_PPD")"
    return 0
}

# Remove every existing LIB- queue so each run produces a known-good state
# (stale queues with old URIs or drivers are the top student-facing failure).
remove_existing_printers() {
    log "Checking for existing UMD Library queues..."

    local existing=()
    local printer
    while IFS= read -r printer; do
        [ -n "$printer" ] && existing+=("$printer")
    done < <(get_library_printers)

    if [ "${#existing[@]}" -eq 0 ]; then
        log "   None found (clean install)"
        return 0
    fi

    log "   Removing ${#existing[@]} existing queue(s) for clean reinstall..."
    for printer in "${existing[@]}"; do
        log "   Removing: $printer"
        lpadmin -x "$printer" 2>&1 || true
    done

    local leftover=0
    for printer in "${existing[@]}"; do
        if ! wait_for_printer_absent "$printer" 5; then
            log "   WARNING: $printer could not be removed"
            leftover=$((leftover + 1))
        fi
    done

    if [ "$leftover" -eq 0 ]; then
        log "   All old queues removed"
    fi
    return 0
}

# Create one Pharos queue. All options go in a single lpadmin call so a
# queue is never left half-configured.
install_printer() {
    local name="$1" location="$2" type="$3"
    local uri="popup://$PHAROS_SERVER:$PHAROS_PORT/$name"
    local -a lpadmin_args
    local install_output

    log "   Installing: $name ($type)"

    # Belt-and-suspenders: removal pass should have cleared this already
    if printer_exists "$name"; then
        lpadmin -x "$name" 2>&1 || true
        if ! wait_for_printer_absent "$name" 5; then
            log "      ERROR: existing queue could not be removed"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAILED_PRINTERS+=("$name")
            return 1
        fi
    fi

    lpadmin_args=(
        -p "$name"
        -E
        -v "$uri"
        -P "$CANON_PPD"
        -D "$location - $type"
        -L "$location"
        -o printer-is-shared=false
        -o printer-error-policy=retry-job
    )

    # Architecture Library printers default to 11x17 (Tabloid)
    if [[ "$name" == *"Arch"* ]]; then
        lpadmin_args+=(
            -o PageSize=Tabloid
            -o MediaType=Plain
            -o InputSlot=Auto
        )
    fi

    if ! install_output="$(lpadmin "${lpadmin_args[@]}" 2>&1)"; then
        log "      ERROR: lpadmin failed"
        echo "$install_output" | sed 's/^/         /'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_PRINTERS+=("$name")
        return 1
    fi

    if ! wait_for_printer_present "$name" 5; then
        log "      ERROR: lpadmin succeeded but queue never appeared"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_PRINTERS+=("$name")
        return 1
    fi

    log "      OK"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    return 0
}

install_all_printers() {
    log "Installing ${#PRINTERS[@]} UMD Library queues..."
    log "   Pharos server: $PHAROS_SERVER:$PHAROS_PORT"

    local printer_def name location type current_group=""
    for printer_def in "${PRINTERS[@]}"; do
        IFS='|' read -r name location type <<< "$printer_def"
        if [ "$location" != "$current_group" ]; then
            current_group="$location"
            log ""
            log "-- $current_group"
        fi
        # Failures are counted inside install_printer; keep going so one bad
        # queue does not block the rest of the fleet's printers.
        install_printer "$name" "$location" "$type" || true
    done
}

print_summary() {
    local installed=()
    local printer
    while IFS= read -r printer; do
        [ -n "$printer" ] && installed+=("$printer")
    done < <(get_library_printers)

    log ""
    log "==========================================="
    log "INSTALLATION SUMMARY"
    log "==========================================="
    log "Installed successfully : $SUCCESS_COUNT"
    log "Failed                 : $FAIL_COUNT"
    log "Queues now on system   : ${#installed[@]}"

    if [ "${#installed[@]}" -gt 0 ]; then
        for printer in "${installed[@]}"; do
            log "   $printer"
        done
    fi

    if [ "${#FAILED_PRINTERS[@]}" -gt 0 ]; then
        log ""
        log "Failed queues:"
        for printer in "${FAILED_PRINTERS[@]}"; do
            log "   $printer"
        done
    fi

    log ""
    log "Completed: $(date)"
    log "Full log: $LOG_FILE"
    log "==========================================="
}

main() {
    # Root check must precede logging setup: tee cannot write /var/log otherwise
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: This script must be run as root" >&2
        exit 1
    fi

    exec &> >(tee -a "$LOG_FILE")
    trap 'log "ERROR: Unexpected failure on line $LINENO"; exit 1' ERR

    log "==========================================="
    log "UMD Library Printers Installation v5.0"
    log "==========================================="
    log "macOS: $(sw_vers -productVersion) ($(uname -m))"
    log ""

    # Prerequisite failures log their own diagnostics; exit directly so the
    # generic ERR trap does not add a misleading "unexpected failure" line
    check_cups || exit 1
    verify_popup_backend || exit 1
    verify_canon_ppd || exit 1
    log ""
    remove_existing_printers
    log ""
    install_all_printers
    print_summary

    if [ "$FAIL_COUNT" -eq 0 ] && [ "$SUCCESS_COUNT" -gt 0 ]; then
        log "All $SUCCESS_COUNT queues installed successfully"
        exit 0
    elif [ "$SUCCESS_COUNT" -gt 0 ]; then
        log "Partial success: $SUCCESS_COUNT installed, $FAIL_COUNT failed"
        exit 1
    else
        log "Installation FAILED: no queues were installed"
        exit 1
    fi
}

main "$@"
