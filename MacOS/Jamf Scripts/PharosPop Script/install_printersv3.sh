#!/bin/bash
# UMD Library Printers Installation Script for Jamf
# Version 2.6 - Fixed for B&W billing and macOS compatibility

LOG_FILE="/var/log/umd_printer_install.log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Library Printers Installation"
echo "Jamf Deployment Version 2.6"
echo "==========================================="
echo "Started: $(date)"
echo "macOS: $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"
echo ""

# Give Popup.pkg time to fully install if running in same policy
echo "Waiting for package installation to complete..."
sleep 5

# Check CUPS service
echo "Checking print system status..."
if ! pgrep -x cupsd > /dev/null; then
    echo "CUPS service not running, attempting to start..."
    # Try new macOS method first, then fall back to older method
    launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || \
    launchctl load -w /System/Library/LaunchDaemons/org.cups.cupsd.plist 2>/dev/null || true
    sleep 3
fi

if pgrep -x cupsd > /dev/null; then
    echo "✅ CUPS service is running"
else
    echo "⚠️  CUPS service not detected, but may be running (continuing anyway)"
fi

# Verify Pharos Popup is installed
echo ""
echo "Verifying Pharos installation..."
POPUP_BACKEND="/usr/libexec/cups/backend/popup"

if [ -f "$POPUP_BACKEND" ] || [ -L "$POPUP_BACKEND" ]; then
    echo "✅ Pharos popup backend found"
elif [ -f "/Library/Application Support/Pharos/popup" ]; then
    echo "Creating popup backend symlink..."
    ln -sf "/Library/Application Support/Pharos/popup" "$POPUP_BACKEND"
    chmod 755 "$POPUP_BACKEND" 2>/dev/null || true
    echo "✅ Popup backend symlink created"
else
    echo "❌ ERROR: Pharos Popup not installed!"
    echo "   Please ensure Popup.pkg is deployed first"
    exit 1
fi

# Find working PPD/driver
echo ""
echo "Testing printer driver options..."

# Full path to Generic PPD
GENERIC_PPD="/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/Generic.ppd"

# Test different driver approaches
DRIVER_METHOD=""
TEST_PRINTER="_test_printer_$$"

# Method 1: IPP Everywhere (most reliable on modern macOS)
if lpadmin -p "$TEST_PRINTER" -E -v "ipp://localhost:631/printers/$TEST_PRINTER" -m everywhere 2>/dev/null; then
    DRIVER_METHOD="everywhere"
    echo "✅ Using IPP Everywhere driver"
# Method 2: Raw queue (no driver)
elif lpadmin -p "$TEST_PRINTER" -E -v "ipp://localhost:631/printers/$TEST_PRINTER" -m raw 2>/dev/null; then
    DRIVER_METHOD="raw"
    echo "✅ Using Raw driver"
# Method 3: Generic PostScript
elif [ -f "$GENERIC_PPD" ] && lpadmin -p "$TEST_PRINTER" -E -v "ipp://localhost:631/printers/$TEST_PRINTER" -P "$GENERIC_PPD" 2>/dev/null; then
    DRIVER_METHOD="generic_ppd"
    echo "✅ Using Generic PPD"
else
    DRIVER_METHOD="default"
    echo "⚠️  No standard driver method worked - will try defaults"
fi

# Clean up test printer
lpadmin -x "$TEST_PRINTER" 2>/dev/null || true

# Install printers
echo ""
echo "Installing UMD Library Printers..."

PHAROS_SERVER="LIBRPS406DV.AD.UMD.EDU"
PHAROS_PORT="515"
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

install_printer() {
    local name="$1"
    local location="$2"
    local type="$3"
    local uri="popup://$PHAROS_SERVER:$PHAROS_PORT/$name"
    local description="$location - $type"
    
    echo ""
    echo "Installing: $name ($type)"
    
    # No need to check if exists since we removed all printers above
    # Just remove any failed remnants
    lpadmin -x "$name" 2>/dev/null || true
    
    local success=false
    
    # Try installation based on what worked in testing
    case "$DRIVER_METHOD" in
        "everywhere")
            if lpadmin -p "$name" -E -v "$uri" -m everywhere -D "$description" -L "$location" 2>&1; then
                echo "  Installed successfully (IPP Everywhere)"
                success=true
            fi
            ;;
        "raw")
            if lpadmin -p "$name" -E -v "$uri" -m raw -D "$description" -L "$location" 2>&1; then
                echo "  Installed successfully (Raw)"
                success=true
            fi
            ;;
        "generic_ppd")
            if lpadmin -p "$name" -E -v "$uri" -P "$GENERIC_PPD" -D "$description" -L "$location" 2>&1; then
                echo "  Installed successfully (Generic PPD)"
                success=true
            fi
            ;;
        *)
            # Try multiple fallback methods
            if lpadmin -p "$name" -E -v "$uri" -D "$description" -L "$location" 2>&1; then
                echo "  Installed successfully (Default)"
                success=true
            elif lpadmin -p "$name" -E -v "$uri" -m everywhere -D "$description" -L "$location" 2>&1; then
                echo "  Installed successfully (IPP Everywhere fallback)"
                success=true
            elif lpadmin -p "$name" -E -v "$uri" -m raw -D "$description" -L "$location" 2>&1; then
                echo "  Installed successfully (Raw fallback)"
                success=true
            fi
            ;;
    esac
    
    if [ "$success" = false ]; then
        echo "  ❌ Failed to install"
        ((FAIL_COUNT++))
        return 1
    fi
    
    # Apply appropriate defaults after successful installation
    apply_queue_defaults "$name" "$type"
    
    ((SUCCESS_COUNT++))
    return 0
}

# Install all printers
echo ""
echo "Starting printer installation..."

# Architecture Library
install_printer "LIB-ArchMobileBW" "Architecture Library" "Black & White"
install_printer "LIB-ArchMobileColor" "Architecture Library" "Color"

# Art Library
install_printer "LIB-ArtMobileBW" "Art Library" "Black & White"
install_printer "LIB-ArtMobileColor" "Art Library" "Color"

# EPSL Library (displayed as STEM Library)
install_printer "LIB-EPSLMobileBW" "STEM Library" "Black & White"
install_printer "LIB-EPSLMobileColor" "STEM Library" "Color"

# Hornbake Library
install_printer "LIB-HBKMobileBW" "Hornbake Library" "Black & White"
install_printer "LIB-HBKMobileColor" "Hornbake Library" "Color"

# Maryland Room
install_printer "LIB-MarylandRoomMobileBW" "Maryland Room" "Black & White"
install_printer "LIB-MarylandRoomMobileColor" "Maryland Room" "Color"

# McKeldin Library
install_printer "LIB-McKMobileBW" "McKeldin Library" "Black & White"
install_printer "LIB-McKMobileColor" "McKeldin Library" "Color"
install_printer "LIB-Mck2FMobileWideFormat" "McKeldin Library" "Wide Format"

# PAL Library
install_printer "LIB-PALMobileBW" "PAL Library" "Black & White"
install_printer "LIB-PALMobileColor" "PAL Library" "Color"

# System integration
echo ""
echo "Refreshing print system..."
launchctl stop org.cups.cupsd 2>/dev/null || true
launchctl start org.cups.cupsd 2>/dev/null || true
sleep 2

# Final verification
echo ""
echo "Verifying installation..."
INSTALLED_PRINTERS=$(lpstat -p 2>/dev/null | grep "LIB-" | wc -l | tr -d ' ')
echo "Found $INSTALLED_PRINTERS UMD printers in system"

if [ "$INSTALLED_PRINTERS" -gt 0 ]; then
    echo ""
    echo "Installed printers:"
    lpstat -p | grep "LIB-" | awk '{print "  • " $2}'
fi

# Final summary
echo ""
echo "==========================================="
echo "Installation Summary"
echo "==========================================="
echo "✅ Successfully installed: $SUCCESS_COUNT printers"
echo "⏭️  Already present: $SKIP_COUNT printers"
echo "❌ Failed: $FAIL_COUNT printers"
echo "Completed: $(date)"
echo "==========================================="

# Exit with appropriate code for Jamf
if [ $FAIL_COUNT -eq 0 ]; then
    echo "Installation completed successfully"
    exit 0
else
    echo "Installation completed with $FAIL_COUNT errors"
    exit 1
fi