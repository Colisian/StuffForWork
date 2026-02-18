#!/bin/bash
# =============================================================================
# UMD Libraries - Staff Printer Uninstall Script (macOS / Jamf Self Service)
# =============================================================================
# Removes a single staff printer from the system.
#
# Author: Oji
# Date: 2026-02-17
# Version: 1.0
#
# TEMPLATE INSTRUCTIONS:
# To create an uninstall script for a different printer, duplicate this file
# and change ONLY the PRINTER_NAME variable below.
#
# JAMF DEPLOYMENT:
#   This script can be used as:
#   - A separate "Uninstall" Self Service policy
#   - The uninstall script in an Extension Attribute or policy
# =============================================================================

set -e          # Exit on error
set -u          # Exit on undefined variable
set -o pipefail # Catch errors in pipelines

# =============================================================================
# PRINTER CONFIGURATION - Change this for each printer
# =============================================================================
PRINTER_NAME="PAL_2F_PR1"

# =============================================================================
# LOGGING
# =============================================================================
LOG_FILE="/var/log/umd_staff_printer_install.log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Libraries - Staff Printer Removal"
echo "==========================================="
echo "Started: $(date)"
echo "Printer: ${PRINTER_NAME}"
echo ""

# =============================================================================
# FUNCTIONS
# =============================================================================

function check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: This script must be run as root"
        exit 1
    fi
    echo "Root privileges confirmed"
}

function remove_printer() {
    echo ""
    if lpstat -p "$PRINTER_NAME" &>/dev/null; then
        echo "Found printer '${PRINTER_NAME}', removing..."
        lpadmin -x "$PRINTER_NAME" 2>&1
        sleep 2

        if lpstat -p "$PRINTER_NAME" &>/dev/null; then
            echo "ERROR: Printer '${PRINTER_NAME}' could not be removed"
            exit 1
        fi

        echo "Printer '${PRINTER_NAME}' removed successfully"
    else
        echo "Printer '${PRINTER_NAME}' is not installed (nothing to remove)"
    fi
}

# =============================================================================
# ERROR HANDLING
# =============================================================================
trap 'echo "ERROR on line $LINENO"; exit 1' ERR

# =============================================================================
# MAIN
# =============================================================================

function main() {
    check_root
    remove_printer

    echo ""
    echo "==========================================="
    echo "REMOVAL COMPLETE"
    echo "==========================================="
    echo "Printer: ${PRINTER_NAME}"
    echo "Time:    $(date)"
    echo "==========================================="

    exit 0
}

main "$@"
