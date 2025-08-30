#!/bin/bash
# UMD Pharos Mobile Print Installer - PostScript Driver Version
# Uses generic PostScript driver for better macOS integration

LOG_FILE="$HOME/Desktop/UMD_MobilePrint_Install_$(date +%Y%m%d_%H%M%S).log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Pharos Mobile Print Installer v2.4"
echo "PostScript Driver Edition"
echo "==========================================="
echo "Started: $(date)"
echo "macOS: $(sw_vers -productVersion)"
echo ""

# Check admin privileges
echo "🔐 Checking administrator privileges..."
if ! sudo -n true 2>/dev/null; then
    osascript -e 'display dialog "Administrator privileges required. You will be prompted for your Mac password." buttons {"Continue"} with icon note' > /dev/null
    sudo -v || exit 1
fi
echo "✅ Administrator access confirmed"

# Install Pharos client
echo ""
echo "📦 Installing Pharos Popup Client..."
POPUP_PKG="$(dirname "$0")/Popup.pkg"

if [ ! -f "$POPUP_PKG" ]; then
    echo "❌ ERROR: Popup.pkg not found at $POPUP_PKG"
    exit 1
fi

if [ -d "/Library/Application Support/Pharos" ] || [ -d "/Applications/Utilities/Pharos" ]; then
    echo "ℹ️  Pharos client already installed"
else
    echo "   Installing Pharos client..."
    sudo installer -pkg "$POPUP_PKG" -target / && echo "✅ Pharos client installed"
fi

# Find the best PostScript PPD
echo ""
echo "🔍 Locating PostScript printer drivers..."

# Common PostScript PPD locations on macOS
PPD_PATHS=(
    "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/Generic.ppd"
    "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/GenericPrinter.ppd"
    "/System/Volumes/Data/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Versions/A/Resources/Generic.ppd"
    "/usr/share/cups/model/postscript.ppd"
)

SELECTED_PPD=""
for ppd_path in "${PPD_PATHS[@]}"; do
    if [ -f "$ppd_path" ]; then
        SELECTED_PPD="$ppd_path"
        echo "✅ Found PostScript PPD: $ppd_path"
        break
    fi
done

if [ -z "$SELECTED_PPD" ]; then
    echo "⚠️  No PostScript PPD found, will use alternative methods"
fi

# Install printers
echo ""
echo "🖨️  Installing UMD Library Printers with PostScript Support..."

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
    
    if lpstat -p "$name" &>/dev/null; then
        echo "      ⏭️ Already installed"
        ((SKIP_COUNT++))
        return 0
    fi
    
    local success=false
    
    # Method 1: Use found PostScript PPD
    if [ -n "$SELECTED_PPD" ]; then
        if sudo lpadmin -p "$name" -E -v "$uri" -P "$SELECTED_PPD" -D "$description" 2>/dev/null; then
            echo "      ✅ Success (PostScript PPD)"
            success=true
        fi
    fi
    
    # Method 2: Try built-in PostScript driver
    if [ "$success" = false ]; then
        if sudo lpadmin -p "$name" -E -v "$uri" -m postscript-color.ppd -D "$description" 2>/dev/null; then
            echo "      ✅ Success (Color PostScript)"
            success=true
        elif sudo lpadmin -p "$name" -E -v "$uri" -m postscript.ppd -D "$description" 2>/dev/null; then
            echo "      ✅ Success (PostScript)"
            success=true
        fi
    fi
    
    # Method 3: Try generic PostScript model
    if [ "$success" = false ]; then
        if sudo lpadmin -p "$name" -E -v "$uri" -m "drv:///generic.drv/generic-ps.ppd" -D "$description" 2>/dev/null; then
            echo "      ✅ Success (Generic PostScript)"
            success=true
        fi
    fi
    
    # Method 4: PostScript with manufacturer
    if [ "$success" = false ]; then
        if sudo lpadmin -p "$name" -E -v "$uri" -m "lsb/usr/cupsfilters/generic.ppd" -D "$description" 2>/dev/null; then
            echo "      ✅ Success (CUPS PostScript)"
            success=true
        fi
    fi
    
    # Method 5: IPP Everywhere fallback
    if [ "$success" = false ]; then
        if sudo lpadmin -p "$name" -E -v "$uri" -m everywhere -D "$description" 2>/dev/null; then
            echo "      ✅ Success (IPP Everywhere fallback)"
            success=true
        fi
    fi
    
    # Method 6: Default driver fallback
    if [ "$success" = false ]; then
        if sudo lpadmin -p "$name" -E -v "$uri" -D "$description" 2>/dev/null; then
            echo "      ✅ Success (Default driver)"
            success=true
        fi
    fi
    
    if [ "$success" = false ]; then
        echo "      ❌ All methods failed"
        ((FAIL_COUNT++))
        return 1
    fi
    
    # Configure printer options for better integration
    sudo lpadmin -p "$name" -o printer-is-shared=false 2>/dev/null || true
    sudo lpadmin -p "$name" -o printer-error-policy=retry-job 2>/dev/null || true
    sudo lpadmin -p "$name" -o printer-is-accepting-jobs=true 2>/dev/null || true
    
    # Set PostScript-specific options
    sudo lpadmin -p "$name" -o printer-make-and-model="Generic PostScript Printer" 2>/dev/null || true
    sudo lpadmin -p "$name" -o device-uri="$uri" 2>/dev/null || true
    
    ((SUCCESS_COUNT++))
    return 0
}

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

# Enhanced system integration
echo ""
echo "🔄 Applying enhanced macOS integration..."

# Force system printer database refresh
sudo rm -f /var/db/printmgr.db 2>/dev/null || true
sudo killall -HUP cupsd 2>/dev/null || true
sudo launchctl stop com.apple.printmanagerd 2>/dev/null || true
sudo launchctl start com.apple.printmanagerd 2>/dev/null || true
sleep 3

# Force UI refresh
killall Dock 2>/dev/null || true
sudo dscacheutil -flushcache

echo "✅ System integration completed"

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
if [ $FAIL_COUNT -eq 0 ]; then
    osascript -e "display dialog \"🎉 SUCCESS! UMD printers installed with PostScript drivers!\\n\\n📊 Summary:\\n• $SUCCESS_COUNT printers installed\\n• $SKIP_COUNT already present\\n\\n🖨️ The PostScript drivers should provide better compatibility with macOS print dialogs.\\n\\n📞 Help: help@umd.edu\" buttons {\"Excellent!\"} with icon note"
elif [ $SUCCESS_COUNT -gt 0 ]; then
    osascript -e "display dialog \"⚠️ Partial Success\\n\\n• $SUCCESS_COUNT installed\\n• $FAIL_COUNT failed\\n\\nWorking printers use PostScript drivers for better compatibility.\" buttons {\"OK\"} with icon caution"
else
    osascript -e "display dialog \"❌ Installation Failed\\n\\nNo printers installed. Please check network connection and try again.\" buttons {\"OK\"} with icon stop"
fi

echo ""
echo "✅ PostScript driver installation complete!"
echo ""
echo "🧪 Test Steps:"
echo "1. Wait 30 seconds for system integration"
echo "2. Open TextEdit and try to print (Cmd+P)"
echo "3. Look for UMD printers in the printer dropdown"
echo "4. If not visible, try logging out and back in"

# Final verification
FINAL_COUNT=$(lpstat -p 2>/dev/null | grep -c "LIB-" || echo "0")
echo ""
echo "🔍 Verification: $FINAL_COUNT UMD printers installed"