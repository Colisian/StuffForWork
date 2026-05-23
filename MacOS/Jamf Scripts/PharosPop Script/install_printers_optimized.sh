#!/bin/bash
# UMD Library Printers + Canon Driver Installation
# Optimized variant: fewer fixed sleeps, fewer lpadmin calls, data-driven queues.

LOG_FILE="/var/log/umd_printer_install.log"
TARGET_VOLUME="${3:-}"
DISPLAY_TARGET_VOLUME="${TARGET_VOLUME:-/}"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

exec &> >(tee -a "$LOG_FILE")
set -o pipefail

echo "==========================================="
echo "UMD Library Printers Installation"
echo "Optimized version"
echo "==========================================="
echo "Started: $(date)"
echo "macOS: $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"
echo "Running as user: $(whoami)"
echo "Target volume: $DISPLAY_TARGET_VOLUME"
echo ""

version_to_code() {
    local version="$1"
    local major minor revision

    IFS='.' read -r major minor revision <<< "$version"
    major="${major:-0}"
    minor="${minor:-0}"
    revision="${revision:-0}"

    echo $((10#$major * 10000 + 10#$minor * 100 + 10#$revision))
}

wait_for_cups() {
    local max_wait="${1:-30}"
    local waited=0

    until lpstat -r >/dev/null 2>&1; do
        if [ "$waited" -ge "$max_wait" ]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done

    return 0
}

restart_cups() {
    local reason="$1"

    echo "   Restarting CUPS: $reason"
    launchctl stop org.cups.cupsd 2>/dev/null || true
    launchctl start org.cups.cupsd 2>/dev/null || true

    if wait_for_cups 30; then
        echo "   CUPS scheduler is running"
        return 0
    fi

    echo "   ERROR: CUPS failed to become ready"
    return 1
}

printer_exists() {
    local name="$1"
    lpstat -p "$name" >/dev/null 2>&1
}

wait_for_printer() {
    local name="$1"
    local max_wait="${2:-5}"
    local waited=0

    until printer_exists "$name"; do
        if [ "$waited" -ge "$max_wait" ]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done

    return 0
}

wait_for_printer_absent() {
    local name="$1"
    local max_wait="${2:-5}"
    local waited=0

    while printer_exists "$name"; do
        if [ "$waited" -ge "$max_wait" ]; then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done

    return 0
}

get_library_printers() {
    lpstat -p 2>/dev/null | awk '$2 ~ /LIB-/ {print $2}'
}

echo "Running Canon driver post-install tasks..."

current_os_version="$(sw_vers -productVersion)"
current_os_code="$(version_to_code "$current_os_version")"

if [ "$current_os_code" -lt 100600 ]; then
    echo "   Old macOS detected, stripping x86_64 binaries..."
    lipo -remove x86_64 -output "${TARGET_VOLUME}/Library/Printers/Canon/CUPS_Printer/Bins/Bins.bundle/Contents/Library/xdclfilter" "${TARGET_VOLUME}/Library/Printers/Canon/CUPS_Printer/Bins/Bins.bundle/Contents/Library/xdclfilter" 2>/dev/null || true
    lipo -remove x86_64 -output "${TARGET_VOLUME}/Library/Printers/Canon/CUPS_Printer/Utilities/Canon Office Printer Utility.app/Contents/MacOS/Canon Office Printer Utility" "${TARGET_VOLUME}/Library/Printers/Canon/CUPS_Printer/Utilities/Canon Office Printer Utility.app/Contents/MacOS/Canon Office Printer Utility" 2>/dev/null || true
    lipo -remove x86_64 -output "${TARGET_VOLUME}/Library/Printers/Canon/CUPS_Printer/Utilities/autoSetupTool.app/Contents/MacOS/autoSetupTool" "${TARGET_VOLUME}/Library/Printers/Canon/CUPS_Printer/Utilities/autoSetupTool.app/Contents/MacOS/autoSetupTool" 2>/dev/null || true

    chmod 1775 "${TARGET_VOLUME:-/}" 2>/dev/null || true
    chown root:admin "${TARGET_VOLUME:-/}" 2>/dev/null || true
    chmod 1775 "${TARGET_VOLUME}/Library" 2>/dev/null || true
    chown root:admin "${TARGET_VOLUME}/Library" 2>/dev/null || true
    chmod 775 "${TARGET_VOLUME}/Library/Printers" 2>/dev/null || true
    chown root:admin "${TARGET_VOLUME}/Library/Printers" 2>/dev/null || true
    chmod 775 "${TARGET_VOLUME}/Library/Printers/Canon" 2>/dev/null || true
    chown root:admin "${TARGET_VOLUME}/Library/Printers/Canon" 2>/dev/null || true
fi

if [ "$current_os_code" -ge 100900 ]; then
    echo "   Cleaning up legacy Canon queues..."
    if [ -f "./DeleteQueues" ]; then
        ./DeleteQueues 2>/dev/null || true
    fi
    rm -f "${TARGET_VOLUME}/Library/LaunchAgents/jp.co.canon.LIPSLX.BG.plist" 2>/dev/null || true
    rm -f "${TARGET_VOLUME}/Library/LaunchAgents/jp.co.canon.UFR2.BG.plist" 2>/dev/null || true
    rm -f "${TARGET_VOLUME}/Library/LaunchAgents/jp.co.canon.CARPS2.BG.plist" 2>/dev/null || true
    rm -f "${TARGET_VOLUME}/Library/LaunchAgents/jp.co.canon.CUPSCMFP.BG.plist" 2>/dev/null || true
fi

echo "   Canon driver post-install completed"

echo ""
echo "Verifying Pharos Popup application..."

POPUP_BACKEND="/usr/libexec/cups/backend/popup"
PHAROS_APP_LOCATIONS=(
    "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/Popup"
    "/Applications/Pharos/Popup.app/Contents/MacOS/Popup"
    "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/popup"
    "/Applications/Popup.app/Contents/MacOS/Popup"
)

POPUP_BINARY=""

if [ -x "$POPUP_BACKEND" ]; then
    echo "   Pharos popup backend already configured at: $POPUP_BACKEND"
    POPUP_BINARY="$(readlink "$POPUP_BACKEND" 2>/dev/null || echo "$POPUP_BACKEND")"
    echo "      Points to: $POPUP_BINARY"
else
    echo "   Searching known Pharos Popup locations..."

    for location in "${PHAROS_APP_LOCATIONS[@]}"; do
        if [ -x "$location" ]; then
            POPUP_BINARY="$location"
            echo "   Found Pharos Popup executable at: $POPUP_BINARY"
            break
        fi
    done

    if [ -z "$POPUP_BINARY" ]; then
        echo "   Searching for Popup.app bundle..."
        POPUP_APP="$(find "/Library/Application Support/Pharos" -name "Popup.app" -type d 2>/dev/null | head -n 1)"

        if [ -z "$POPUP_APP" ]; then
            POPUP_APP="$(find /Library /Applications -name "Popup.app" -type d 2>/dev/null | head -n 1)"
        fi

        if [ -n "$POPUP_APP" ]; then
            echo "   Found Popup.app at: $POPUP_APP"

            if [ -f "$POPUP_APP/Contents/MacOS/Popup" ]; then
                POPUP_BINARY="$POPUP_APP/Contents/MacOS/Popup"
            elif [ -f "$POPUP_APP/Contents/MacOS/popup" ]; then
                POPUP_BINARY="$POPUP_APP/Contents/MacOS/popup"
            fi

            if [ -n "$POPUP_BINARY" ] && [ ! -x "$POPUP_BINARY" ]; then
                echo "   Making Popup executable..."
                chmod +x "$POPUP_BINARY"
            fi
        fi
    fi

    if [ -n "$POPUP_BINARY" ] && [ -x "$POPUP_BINARY" ]; then
        echo "   Creating CUPS backend symlink..."
        mkdir -p /usr/libexec/cups/backend 2>/dev/null || true
        ln -sf "$POPUP_BINARY" "$POPUP_BACKEND"
        chmod 755 "$POPUP_BACKEND" 2>/dev/null || true
    fi
fi

if [ ! -x "$POPUP_BACKEND" ]; then
    echo "   ERROR: Pharos Popup executable not found or backend is not executable"
    echo ""
    echo "   Diagnostic information:"
    if [ -d "/Library/Application Support/Pharos" ]; then
        echo "   Pharos directory contents:"
        ls -la "/Library/Application Support/Pharos/" 2>/dev/null | sed 's/^/      /'

        if [ -d "/Library/Application Support/Pharos/Popup.app" ]; then
            echo ""
            echo "   Popup.app Contents:"
            ls -la "/Library/Application Support/Pharos/Popup.app/Contents/" 2>/dev/null | sed 's/^/      /'
            echo ""
            echo "   Popup.app MacOS directory:"
            ls -la "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/" 2>/dev/null | sed 's/^/      /'
        fi
    else
        echo "      Pharos directory not found"
    fi
    echo ""
    echo "   REQUIRED: Ensure Popup.pkg is properly installed"
    echo "   Expected: /Library/Application Support/Pharos/Popup.app/Contents/MacOS/Popup"
    exit 1
fi

echo "   Popup backend is executable and ready"
ls -lh "$POPUP_BACKEND" 2>/dev/null | sed 's/^/      /'
if [ -L "$POPUP_BACKEND" ]; then
    readlink "$POPUP_BACKEND" 2>/dev/null | sed 's/^/      Symlink target: /'
fi
file "$POPUP_BACKEND" 2>/dev/null | sed 's/^/      /'

echo ""
echo "Verifying Canon PPD driver installation..."

CANON_PPD=""
CANON_PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
TARGET_PPD="$CANON_PPD_DIR/CNPZUIRAC5030ZU.ppd.gz"

if [ -r "$TARGET_PPD" ]; then
    CANON_PPD="$TARGET_PPD"
else
    CANON_PPD="$(find "$CANON_PPD_DIR" -type f -name "CNPZUIRAC5030ZU.ppd.gz" 2>/dev/null | head -n 1)"
fi

if [ -z "$CANON_PPD" ]; then
    CANON_PPD="$(find "$CANON_PPD_DIR" -type f \( -name "*UFRII*.ppd.gz" -o -name "CNPZ*.ppd.gz" \) 2>/dev/null | head -n 1)"
fi

if [ -z "$CANON_PPD" ]; then
    echo ""
    echo "   ERROR: No Canon PPD driver found"
    echo ""
    echo "   Canon PPD search results:"
    find /Library/Printers -type f \( -name "*.ppd.gz" -o -name "*.ppd" \) 2>/dev/null | grep -i canon | sed 's/^/      /' || echo "      No Canon PPDs found"
    exit 1
fi

if [ ! -r "$CANON_PPD" ]; then
    echo "   ERROR: PPD exists but is not readable: $CANON_PPD"
    exit 1
fi

echo "   Found Canon PPD: $(basename "$CANON_PPD")"
echo "      Full path: $CANON_PPD"
PPD_SIZE="$(ls -lh "$CANON_PPD" 2>/dev/null | awk '{print $5}')"
echo "      PPD size: $PPD_SIZE"

echo ""
echo "Reloading CUPS after driver and backend setup..."
if ! restart_cups "driver/backend setup complete"; then
    exit 1
fi

echo ""
echo "Checking for existing UMD Library printers..."
EXISTING_PRINTERS=()
while IFS= read -r printer; do
    if [ -n "$printer" ]; then
        EXISTING_PRINTERS+=("$printer")
    fi
done < <(get_library_printers)

if [ "${#EXISTING_PRINTERS[@]}" -gt 0 ]; then
    echo "   Found ${#EXISTING_PRINTERS[@]} existing printer(s)"
    echo "Removing old printers for clean installation..."

    for printer in "${EXISTING_PRINTERS[@]}"; do
        echo "   Removing: $printer"
        lpadmin -x "$printer" 2>&1 || true
    done

    REMAINING_COUNT=0
    for printer in "${EXISTING_PRINTERS[@]}"; do
        if ! wait_for_printer_absent "$printer" 5; then
            REMAINING_COUNT=$((REMAINING_COUNT + 1))
        fi
    done

    if [ "$REMAINING_COUNT" -eq 0 ]; then
        echo "   All old printers removed successfully"
    else
        echo "   Warning: $REMAINING_COUNT printer(s) may still exist"
    fi
else
    echo "   No existing UMD Library printers found"
fi

echo ""
echo "Installing UMD Library Printers with Canon driver..."
echo "   Using PPD: $(basename "$CANON_PPD")"
echo "   Using Pharos backend: $POPUP_BACKEND"

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_PRINTERS=()

PHAROS_SERVER="LIBRPS406DV.AD.UMD.EDU"
PHAROS_PORT="515"

install_printer() {
    local name="$1"
    local location="$2"
    local type="$3"
    local uri="popup://$PHAROS_SERVER:$PHAROS_PORT/$name"
    local description="$location - $type"
    local install_output
    local exit_code
    local -a lpadmin_args

    echo ""
    echo "   Installing: $name"
    echo "      Location: $location"
    echo "      Type: $type"

    if printer_exists "$name"; then
        echo "      Printer already exists, forcing removal..."
        lpadmin -x "$name" 2>&1 || true
        if ! wait_for_printer_absent "$name" 5; then
            echo "      ERROR: Existing printer could not be removed"
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
        -D "$description"
        -L "$location"
        -o printer-is-shared=false
        -o printer-error-policy=retry-job
    )

    if [[ "$name" == *"Arch"* ]]; then
        echo "      Applying 11x17 Tabloid defaults..."
        lpadmin_args+=(
            -o PageSize=Tabloid
            -o MediaType=Plain
            -o InputSlot=Auto
        )
    fi

    install_output="$(lpadmin "${lpadmin_args[@]}" 2>&1)"
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        echo "      ERROR: Installation failed with exit code $exit_code"
        echo "$install_output" | sed 's/^/         /'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_PRINTERS+=("$name")
        return 1
    fi

    if ! wait_for_printer "$name" 5; then
        echo "      ERROR: lpadmin succeeded but printer was not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_PRINTERS+=("$name")
        return 1
    fi

    echo "      Printer created successfully"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    return 0
}

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

CURRENT_GROUP=""
for printer_def in "${PRINTERS[@]}"; do
    IFS='|' read -r printer_name printer_location printer_type <<< "$printer_def"

    if [ "$printer_location" != "$CURRENT_GROUP" ]; then
        CURRENT_GROUP="$printer_location"
        echo ""
        echo "$CURRENT_GROUP"
    fi

    install_printer "$printer_name" "$printer_location" "$printer_type"
done

echo ""
echo "Final verification..."

INSTALLED_PRINTERS=()
while IFS= read -r printer; do
    if [ -n "$printer" ]; then
        INSTALLED_PRINTERS+=("$printer")
    fi
done < <(get_library_printers)

if [ "${#INSTALLED_PRINTERS[@]}" -lt "$SUCCESS_COUNT" ]; then
    echo "   Printer count lower than expected; refreshing CUPS once before final count..."
    restart_cups "final verification retry" || true
    INSTALLED_PRINTERS=()
    while IFS= read -r printer; do
        if [ -n "$printer" ]; then
            INSTALLED_PRINTERS+=("$printer")
        fi
    done < <(get_library_printers)
fi

echo ""
echo "System printer count: ${#INSTALLED_PRINTERS[@]} UMD Library printers"

if [ "${#INSTALLED_PRINTERS[@]}" -gt 0 ]; then
    echo ""
    echo "Confirmed installed printers:"
    for printer in "${INSTALLED_PRINTERS[@]}"; do
        echo "      $printer"
    done
fi

echo ""
echo "==========================================="
echo "INSTALLATION SUMMARY"
echo "==========================================="
echo "Successfully installed: $SUCCESS_COUNT printers"
echo "Failed: $FAIL_COUNT printers"

if [ "${#FAILED_PRINTERS[@]}" -gt 0 ]; then
    echo ""
    echo "Failed printers:"
    for failed in "${FAILED_PRINTERS[@]}"; do
        echo "   $failed"
    done
fi

echo ""
echo "Completed: $(date)"
echo "Full log: $LOG_FILE"
echo "==========================================="

if [ "$FAIL_COUNT" -eq 0 ] && [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo ""
    echo "Installation completed successfully. All $SUCCESS_COUNT printers are ready to use."
    exit 0
elif [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo ""
    echo "Partial success: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed"
    exit 1
fi

echo ""
echo "Installation failed: no printers were installed"
exit 1
