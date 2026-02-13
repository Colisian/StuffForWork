#!/bin/bash
# =============================================================================
# UMD Libraries - Staff Printer Installation Script (macOS / Jamf Self Service)
# =============================================================================
# Installs a single staff printer via SMB to the Windows print server.
# The Canon UFR II driver package must be deployed BEFORE this script runs.
# Jamf should pair this script with the Canon driver package in the same policy,
# or ensure the driver is a prerequisite policy.
#
# Author: Oji
# Date: 2026-02-13
# Version: 1.0
#
# TEMPLATE INSTRUCTIONS:
# To create a script for a different printer, duplicate this file and change
# ONLY the variables in the "PRINTER CONFIGURATION" section below:
#   - PRINTER_NAME    (e.g., "MCK_4F_PR1")
#   - PRINTER_DESC    (e.g., "McKeldin 4th Floor Printer 1")
#   - PRINTER_LOC     (e.g., "McKeldin Library, 4th Floor")
#
# JAMF SELF SERVICE DEPLOYMENT:
#   1. Upload this script to Jamf Pro > Settings > Scripts
#   2. Create a Policy:
#      - Trigger: Self Service
#      - Frequency: Ongoing
#      - Packages: Canon UFR II driver package (runs before script)
#      - Scripts: This script (runs after package)
#      - Self Service: Add icon, display name "Install PAL_1F_PR1"
#   3. Scope to appropriate Smart Groups
# =============================================================================

set -e          # Exit on error
set -u          # Exit on undefined variable
set -o pipefail # Catch errors in pipelines

# =============================================================================
# PRINTER CONFIGURATION - Change these for each printer
# =============================================================================
PRINTER_NAME="PAL_1F_PR1"
PRINTER_DESC="PAL 1st Floor Printer 1"
PRINTER_LOC="Performance Art Library, 1st Floor"

# =============================================================================
# SHARED CONFIGURATION - Same for all staff printers (do not change)
# =============================================================================
PRINT_SERVER="LIBRPS403v.ad.umd.edu"
PRINTER_URI="smb://${PRINT_SERVER}/${PRINTER_NAME}"
PPD_FILE="CNPZUIRAC5030ZU.ppd.gz"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
SCRIPT_VERSION="1.0"

# =============================================================================
# LOGGING
# =============================================================================
LOG_FILE="/var/log/umd_staff_printer_install.log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Libraries - Staff Printer Installation"
echo "Version ${SCRIPT_VERSION}"
echo "==========================================="
echo "Started: $(date)"
echo "Printer: ${PRINTER_NAME}"
echo "Server:  ${PRINT_SERVER}"
echo "URI:     ${PRINTER_URI}"
echo "macOS:   $(sw_vers -productVersion)"
echo "Arch:    $(uname -m)"
echo "User:    $(whoami)"
echo ""

# =============================================================================
# FUNCTIONS
# =============================================================================

function check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: This script must be run as root"
        echo "Jamf policies run as root automatically."
        exit 1
    fi
    echo "Root privileges confirmed"
}

function check_cups() {
    echo ""
    echo "Checking CUPS service..."

    if pgrep -x cupsd > /dev/null; then
        echo "CUPS service is running"
        return 0
    fi

    echo "CUPS not running, attempting to start..."
    launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || \
        launchctl load -w /System/Library/LaunchDaemons/org.cups.cupsd.plist 2>/dev/null || true
    sleep 3

    if pgrep -x cupsd > /dev/null; then
        echo "CUPS service started successfully"
        return 0
    fi

    echo "ERROR: CUPS service could not be started"
    exit 1
}

function check_ppd() {
    echo ""
    echo "Checking for Canon UFR II PPD driver..."

    CANON_PPD=""

    # Primary: exact PPD file
    if [ -f "${PPD_DIR}/${PPD_FILE}" ]; then
        CANON_PPD="${PPD_DIR}/${PPD_FILE}"
        echo "Found Canon PPD: ${CANON_PPD}"
    fi

    # Fallback: search for alternative Canon UFR II PPD
    if [ -z "$CANON_PPD" ]; then
        CANON_PPD=$(find "$PPD_DIR" -name "CNPZUIRAC5030ZU.ppd.gz" 2>/dev/null | head -1)
    fi

    if [ -z "$CANON_PPD" ]; then
        CANON_PPD=$(find "$PPD_DIR" \( -name "*UFRII*.ppd.gz" -o -name "CNPZ*.ppd.gz" \) 2>/dev/null | head -1)
        if [ -n "$CANON_PPD" ]; then
            echo "Found alternative Canon PPD: $(basename "$CANON_PPD")"
        fi
    fi

    if [ -z "$CANON_PPD" ]; then
        echo ""
        echo "ERROR: Canon UFR II PPD driver not found!"
        echo ""
        echo "The Canon UFR II driver package must be installed before this script."
        echo "In Jamf, ensure the Canon driver package is set to install BEFORE"
        echo "this script in the policy configuration."
        echo ""
        echo "Expected PPD: ${PPD_DIR}/${PPD_FILE}"
        echo ""
        echo "Searching for any Canon PPDs on system..."
        find /Library/Printers -name "*.ppd.gz" -o -name "*.ppd" 2>/dev/null | grep -i canon | sed 's/^/   /' || echo "   No Canon PPDs found"
        exit 1
    fi

    # Verify readable
    if [ ! -r "$CANON_PPD" ]; then
        echo "ERROR: PPD file exists but is not readable: ${CANON_PPD}"
        exit 1
    fi

    echo "PPD is readable ($(ls -lh "$CANON_PPD" | awk '{print $5}'))"
}

function remove_existing_printer() {
    echo ""
    echo "Checking for existing printer '${PRINTER_NAME}'..."

    if lpstat -p "$PRINTER_NAME" &>/dev/null; then
        echo "Found existing printer, removing..."
        lpadmin -x "$PRINTER_NAME" 2>&1
        sleep 2

        if lpstat -p "$PRINTER_NAME" &>/dev/null; then
            echo "WARNING: Printer may not have been fully removed"
        else
            echo "Existing printer removed successfully"
        fi
    else
        echo "No existing printer found (clean install)"
    fi
}

function install_printer() {
    echo ""
    echo "Installing printer '${PRINTER_NAME}'..."
    echo "   URI:         ${PRINTER_URI}"
    echo "   PPD:         $(basename "$CANON_PPD")"
    echo "   Description: ${PRINTER_DESC}"
    echo "   Location:    ${PRINTER_LOC}"

    local install_output
    local exit_code

    install_output=$(lpadmin -p "$PRINTER_NAME" \
        -E \
        -v "$PRINTER_URI" \
        -P "$CANON_PPD" \
        -D "$PRINTER_DESC" \
        -L "$PRINTER_LOC" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "ERROR: lpadmin failed (exit code: ${exit_code})"
        echo "Output: ${install_output}"
        exit 1
    fi

    # Verify printer was created
    sleep 2
    if ! lpstat -p "$PRINTER_NAME" &>/dev/null; then
        echo "ERROR: lpadmin succeeded but printer not found in CUPS"
        exit 1
    fi

    echo "Printer created successfully"
}

function configure_printer() {
    echo ""
    echo "Configuring printer options..."

    # Do not share this printer
    lpadmin -p "$PRINTER_NAME" -o printer-is-shared=false 2>&1 || true
    echo "   printer-is-shared=false"

    # Retry on error instead of aborting
    lpadmin -p "$PRINTER_NAME" -o printer-error-policy=retry-job 2>&1 || true
    echo "   printer-error-policy=retry-job"

    echo "Printer options configured"
}

function verify_installation() {
    echo ""
    echo "Verifying installation..."

    if lpstat -p "$PRINTER_NAME" &>/dev/null; then
        echo "Printer '${PRINTER_NAME}' is installed and registered with CUPS"

        # Show printer details
        echo ""
        echo "Printer details:"
        lpstat -p "$PRINTER_NAME" -l 2>/dev/null | sed 's/^/   /' || true

        echo ""
        echo "Printer URI:"
        lpstat -v "$PRINTER_NAME" 2>/dev/null | sed 's/^/   /' || true
    else
        echo "ERROR: Printer '${PRINTER_NAME}' not found after installation!"
        exit 1
    fi
}

# =============================================================================
# ERROR HANDLING
# =============================================================================
trap 'echo ""; echo "ERROR on line $LINENO"; echo "Installation failed for ${PRINTER_NAME}"; exit 1' ERR

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function main() {
    check_root
    check_cups
    check_ppd
    remove_existing_printer
    install_printer
    configure_printer
    verify_installation

    echo ""
    echo "==========================================="
    echo "INSTALLATION COMPLETE"
    echo "==========================================="
    echo "Printer: ${PRINTER_NAME}"
    echo "Status:  SUCCESS"
    echo "Time:    $(date)"
    echo "Log:     ${LOG_FILE}"
    echo "==========================================="

    exit 0
}

main "$@"
