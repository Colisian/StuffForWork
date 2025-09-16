#!/bin/bash
# UMD Pharos Mobile Print Installer - Enhanced Diagnostics Version
# Version 2.5 - Fixed for modern macOS

LOG_FILE="$HOME/Desktop/UMD_MobilePrint_Install_$(date +%Y%m%d_%H%M%S).log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Pharos Mobile Print Installer v2.5"
echo "Enhanced Diagnostics Edition"
echo "==========================================="
echo "Started: $(date)"
echo "macOS: $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"
echo ""

# Enhanced error reporting
set -o pipefail
VERBOSE_ERRORS=true

# Check admin privileges
echo "🔐 Checking administrator privileges..."
if ! sudo -n true 2>/dev/null; then
    osascript -e 'display dialog "Administrator privileges required. You will be prompted for your Mac password." buttons {"Continue"} with icon note' > /dev/null
    sudo -v || exit 1
fi
echo "✅ Administrator access confirmed"

# Check CUPS service
echo ""
echo "🔍 Checking print system status..."
if ! pgrep -x cupsd > /dev/null; then
    echo "⚠️  CUPS service not running, attempting to start..."
    sudo launchctl load -w /System/Library/LaunchDaemons/org.cups.cupsd.plist 2>/dev/null || true
    sleep 2
fi

if pgrep -x cupsd > /dev/null; then
    echo "✅ CUPS service is running"
else
    echo "❌ CUPS service failed to start"
    exit 1
fi

# Check for Pharos Popup support
echo ""
echo "🔍 Checking for Pharos popup:// protocol support..."
POPUP_BACKEND="/usr/libexec/cups/backend/popup"
if [ -f "$POPUP_BACKEND" ]; then
    echo "✅ Pharos popup backend found"
elif [ -L "$POPUP_BACKEND" ]; then
    echo "✅ Pharos popup backend symlink found"
else
    echo "⚠️  Pharos popup backend not found - will be installed with Popup.pkg"
fi

# Install Pharos client
echo ""
echo "📦 Installing Pharos Popup Client..."
POPUP_PKG="$(dirname "$0")/Popup.pkg"

if [ ! -f "$POPUP_PKG" ]; then
    echo "❌ ERROR: Popup.pkg not found at $POPUP_PKG"
    echo "Please ensure Popup.pkg is in the same folder as this script"
    exit 1
fi

# Force reinstall for better reliability
echo "   Removing old Pharos installation if present..."
sudo rm -rf "/Library/Application Support/Pharos" 2>/dev/null || true
sudo rm -rf "/Applications/Utilities/Pharos" 2>/dev/null || true
sudo rm -f /usr/libexec/cups/backend/popup 2>/dev/null || true

echo "   Installing fresh Pharos client..."
if sudo installer -pkg "$POPUP_PKG" -target / -verboseR; then
    echo "✅ Pharos client installed successfully"
else
    echo "❌ Pharos client installation failed"
    echo "   Try downloading a fresh copy of Popup.pkg from UMD IT"
    exit 1
fi

# Wait for installation to complete
sleep 3

<<<<<<< HEAD
=======
# ADD THIS NEW SECTION HERE:
# Disable the problematic Notify app to prevent "damaged app" errors
echo ""
echo "🔧 Disabling Pharos Notify app to prevent errors..."
# Kill the app if it's running
sudo killall "Notify" 2>/dev/null || true
sudo killall "psnotifyd" 2>/dev/null || true
sleep 1

# Rename the Notify app to disable it
if [ -d "/Library/Application Support/Pharos/Notify.app" ]; then
    sudo mv "/Library/Application Support/Pharos/Notify.app" "/Library/Application Support/Pharos/Notify.app.disabled" 2>/dev/null || true
    echo "✅ Notify app disabled (prevents 'damaged app' errors)"
else
    echo "ℹ️  Notify app not found or already disabled"
fi

>>>>>>> c371f76349bc9ad6424e3222d56c75e8fac05992
# Verify popup backend was installed
if [ ! -f "$POPUP_BACKEND" ] && [ ! -L "$POPUP_BACKEND" ]; then
    echo "⚠️  Creating popup backend manually..."
    # Try to create symlink to Pharos backend
    if [ -f "/Library/Application Support/Pharos/popup" ]; then
        sudo ln -sf "/Library/Application Support/Pharos/popup" "$POPUP_BACKEND"
        sudo chmod 755 "$POPUP_BACKEND" 2>/dev/null || true
    fi
fi

# List available PPDs for diagnostics
echo ""
echo "🔍 Scanning for available printer drivers..."
echo "   Available PPD models:"
lpinfo -m 2>/dev/null | grep -i "postscript\|generic\|everywhere" | head -5 || echo "   Unable to list PPDs"

# Find working PPD/driver
echo ""
echo "🔍 Testing printer driver options..."

# Test different driver approaches
DRIVER_METHOD=""
TEST_PRINTER="_test_printer_$$"

# Method 1: IPP Everywhere (most reliable on modern macOS)
if sudo lpadmin -p "$TEST_PRINTER" -E -v "ipp://localhost:631/printers/$TEST_PRINTER" -m everywhere 2>/dev/null; then
    DRIVER_METHOD="everywhere"
    echo "✅ IPP Everywhere driver works"
# Method 2: Raw queue (no driver)
elif sudo lpadmin -p "$TEST_PRINTER" -E -v "ipp://localhost:631/printers/$TEST_PRINTER" -m raw 2>/dev/null; then
    DRIVER_METHOD="raw"
    echo "✅ Raw driver works"
# Method 3: Generic PostScript
elif sudo lpadmin -p "$TEST_PRINTER" -E -v "ipp://localhost:631/printers/$TEST_PRINTER" -P /System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/Generic.ppd 2>/dev/null; then
    DRIVER_METHOD="generic_ppd"
    echo "✅ Generic PPD works"
else
    DRIVER_METHOD="none"
    echo "⚠️  No standard driver method worked - will try defaults"
fi

# Clean up test printer
sudo lpadmin -x "$TEST_PRINTER" 2>/dev/null || true

# Install printers
echo ""
echo "🖨️  Installing UMD Library Printers..."
echo "   Using driver method: $DRIVER_METHOD"

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
    
    echo "   🔧 Installing: $name ($type)"
    
    # Check if already installed
    if lpstat -p "$name" &>/dev/null; then
        echo "      ⏭️ Already installed"
        ((SKIP_COUNT++))
        return 0
    fi
    
    local success=false
    local error_msg=""
    
    # Remove any existing failed installation
    sudo lpadmin -x "$name" 2>/dev/null || true
    
    # Try installation based on what worked in testing
    case "$DRIVER_METHOD" in
        "everywhere")
            if sudo lpadmin -p "$name" -E -v "$uri" -m everywhere -D "$description" -L "$location" 2>&1; then
                echo "      ✅ Success (IPP Everywhere)"
                success=true
            else
                error_msg=$?
            fi
            ;;
        "raw")
            if sudo lpadmin -p "$name" -E -v "$uri" -m raw -D "$description" -L "$location" 2>&1; then
                echo "      ✅ Success (Raw)"
                success=true
            else
                error_msg=$?
            fi
            ;;
        "generic_ppd")
            if sudo lpadmin -p "$name" -E -v "$uri" -P /System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/Generic.ppd -D "$description" -L "$location" 2>&1; then
                echo "      ✅ Success (Generic PPD)"
                success=true
            else
                error_msg=$?
            fi
            ;;
        *)
            # Try multiple fallback methods
            if sudo lpadmin -p "$name" -E -v "$uri" -D "$description" -L "$location" 2>&1; then
                echo "      ✅ Success (Default)"
                success=true
            elif sudo lpadmin -p "$name" -E -v "$uri" -m everywhere -D "$description" -L "$location" 2>&1; then
                echo "      ✅ Success (IPP Everywhere fallback)"
                success=true
            elif sudo lpadmin -p "$name" -E -v "$uri" -m raw -D "$description" -L "$location" 2>&1; then
                echo "      ✅ Success (Raw fallback)"
                success=true
            else
                error_msg="All methods failed"
            fi
            ;;
    esac
    
    if [ "$success" = false ]; then
        echo "      ❌ Failed: $error_msg"
        if [ "$VERBOSE_ERRORS" = true ]; then
            # Try to get more error details
            echo "      Debug: Testing URI connectivity..."
            ping -c 1 -W 2 $(echo $PHAROS_SERVER | cut -d: -f1) &>/dev/null && echo "        Server reachable" || echo "        Server unreachable"
        fi
        ((FAIL_COUNT++))
        return 1
    fi
    
    # Configure printer options
    sudo lpadmin -p "$name" -o printer-is-shared=false 2>/dev/null || true
    sudo lpadmin -p "$name" -o printer-error-policy=retry-job 2>/dev/null || true
    
    ((SUCCESS_COUNT++))
    return 0
}

# Create printer groups for better organization
echo ""
echo "📂 Creating printer groups..."
sudo lpadmin -p "_UMD_BW_Printers" -E -v "file:///dev/null" -D "UMD Black & White Printers" -m raw 2>/dev/null || true
sudo lpadmin -p "_UMD_Color_Printers" -E -v "file:///dev/null" -D "UMD Color Printers" -m raw 2>/dev/null || true

# Install all printers
echo ""
echo "📍 Architecture Library:"
install_printer "LIB-ArchMobileBW" "Architecture Library" "Black & White"
install_printer "LIB-ArchMobileColor" "Architecture Library" "Color"

echo ""
echo "📍 Art Library:"
install_printer "LIB-ArtMobileBW" "Art Library" "Black & White"
install_printer "LIB-ArtMobileColor" "Art Library" "Color"

echo ""
echo "📍 EPSL Library:"
install_printer "LIB-EPSLMobileBW" "EPSL Library" "Black & White"
install_printer "LIB-EPSLMobileColor" "EPSL Library" "Color"

echo ""
echo "📍 Hornbake Library:"
install_printer "LIB-HBKMobileBW" "Hornbake Library" "Black & White"
install_printer "LIB-HBKMobileColor" "Hornbake Library" "Color"

echo ""
echo "📍 Maryland Room:"
install_printer "LIB-MarylandRoomMobileBW" "Maryland Room" "Black & White"
install_printer "LIB-MarylandRoomMobileColor" "Maryland Room" "Color"

echo ""
echo "📍 McKeldin Library:"
install_printer "LIB-McKMobileBW" "McKeldin Library" "Black & White"
install_printer "LIB-McKMobileColor" "McKeldin Library" "Color"
install_printer "LIB-Mck2FMobileWideFormat" "McKeldin Library" "Wide Format"

echo ""
echo "📍 PAL Library:"
install_printer "LIB-PALMobileBW" "PAL Library" "Black & White"
install_printer "LIB-PALMobileColor" "PAL Library" "Color"

# Clean up dummy printers
sudo lpadmin -x "_UMD_BW_Printers" 2>/dev/null || true
sudo lpadmin -x "_UMD_Color_Printers" 2>/dev/null || true

# System integration
echo ""
echo "🔄 Refreshing print system..."
sudo launchctl stop org.cups.cupsd 2>/dev/null || true
sudo launchctl start org.cups.cupsd 2>/dev/null || true
sleep 2

# Final verification
echo ""
echo "🔍 Verifying installation..."
INSTALLED_PRINTERS=$(lpstat -p 2>/dev/null | grep "LIB-" | wc -l | tr -d ' ')
echo "   Found $INSTALLED_PRINTERS UMD printers in system"

if [ "$INSTALLED_PRINTERS" -gt 0 ]; then
    echo ""
    echo "   Installed printers:"
    lpstat -p | grep "LIB-" | awk '{print "   • " $2}'
fi

# Diagnostics if all failed
if [ "$SUCCESS_COUNT" -eq 0 ] && [ "$SKIP_COUNT" -eq 0 ]; then
    echo ""
    echo "🔍 Running diagnostics..."
    echo "   CUPS backends available:"
    ls -la /usr/libexec/cups/backend/ | grep -E "popup|lpd|ipp" || echo "   No relevant backends found"
    
    echo ""
    echo "   Network connectivity:"
    ping -c 1 -W 2 LIBRPS406DV.AD.UMD.EDU &>/dev/null && echo "   ✅ Server reachable" || echo "   ❌ Cannot reach server"
    
    echo ""
    echo "   Pharos installation:"
    [ -d "/Library/Application Support/Pharos" ] && echo "   ✅ Pharos directory exists" || echo "   ❌ Pharos directory missing"
fi

# Final summary
echo ""
echo "==========================================="
echo "📊 Installation Summary"
echo "==========================================="
echo "✅ Successfully installed: $SUCCESS_COUNT printers"
echo "⏭️ Already present: $SKIP_COUNT printers"
echo "❌ Failed: $FAIL_COUNT printers"
echo "📝 Log file: $LOG_FILE"
echo "⏰ Completed: $(date)"

# Show completion dialog
if [ $FAIL_COUNT -eq 0 ] && [ $SUCCESS_COUNT -gt 0 ]; then
    osascript -e "display dialog \"🎉 SUCCESS! UMD printers installed!\\n\\n📊 Summary:\\n• $SUCCESS_COUNT printers installed\\n• $SKIP_COUNT already present\\n\\n📞 Need help? Contact: help@umd.edu\" buttons {\"Great!\"} with icon note"
elif [ $SUCCESS_COUNT -gt 0 ]; then
    osascript -e "display dialog \"⚠️ Partial Success\\n\\n• $SUCCESS_COUNT installed\\n• $FAIL_COUNT failed\\n\\nSome printers are ready to use.\\n\\n📞 For help: help@umd.edu\" buttons {\"OK\"} with icon caution"
elif [ $SKIP_COUNT -gt 0 ]; then
    osascript -e "display dialog \"ℹ️ Printers Already Installed\\n\\nAll $SKIP_COUNT printers were already present.\\n\\nNo changes needed.\" buttons {\"OK\"} with icon note"
else
    osascript -e "display dialog \"❌ Installation Failed\\n\\nNo printers could be installed.\\n\\nPossible issues:\\n• Network connection\\n• Missing Popup.pkg\\n• Permissions\\n\\nCheck the log file on your Desktop for details.\\n\\n📞 Contact: help@umd.edu\" buttons {\"OK\"} with icon stop"
fi

echo ""
echo "Installation script completed."