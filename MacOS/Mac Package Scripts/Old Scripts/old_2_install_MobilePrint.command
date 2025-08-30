#!/bin/bash
# UMD Pharos Mobile Print Installer - Simple & Reliable Version
# Compatible with all bash versions and macOS systems

set -e
trap 'osascript -e "display dialog \"Installation failed. Contact help@umd.edu\" buttons {\"OK\"} with icon stop"' ERR

# Setup logging
LOG_FILE="$HOME/Desktop/UMD_MobilePrint_Install_$(date +%Y%m%d_%H%M%S).log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Pharos Mobile Print Installer v2.1"
echo "==========================================="
echo "Started: $(date)"
echo "macOS: $(sw_vers -productVersion)"
echo ""

# Check admin privileges
echo "🔐 Checking administrator privileges..."
if ! sudo -n true 2>/dev/null; then
    osascript -e 'display dialog "Administrator privileges required. You will be prompted for your Mac password." buttons {"Continue"} with icon note' > /dev/null
    sudo -v
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
    sudo installer -pkg "$POPUP_PKG" -target /
    echo "✅ Pharos client installed"
fi

# Install printers
echo ""
echo "🖨️  Installing UMD Library Printers..."

PHAROS_SERVER="LIBRPS406DV.AD.UMD.EDU"
PHAROS_PORT="515"
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

# Function to install a printer
install_printer() {
    local name=$1
    local location=$2  
    local type=$3
    
    local uri="popup://$PHAROS_SERVER:$PHAROS_PORT/$name"
    local description="$location - $type"
    
    if lpstat -p "$name" &>/dev/null 2>&1; then
        echo "   ⏭️  $name: Already installed"
        ((SKIP_COUNT++))
        return 0
    fi
    
    echo "   🔧 Installing: $name ($type) at $location"
    
    # Try multiple installation methods
    if sudo lpadmin -p "$name" -E -v "$uri" -m everywhere -D "$description" 2>/dev/null; then
        echo "      ✅ Success (IPP Everywhere)"
    elif sudo lpadmin -p "$name" -E -v "$uri" -D "$description" 2>/dev/null; then  
        echo "      ✅ Success (Default driver)"
    else
        echo "      ❌ Failed"
        ((FAIL_COUNT++))
        return 1
    fi
    
    # Set printer options
    sudo lpadmin -p "$name" -o printer-is-shared=false 2>/dev/null || true
    sudo lpadmin -p "$name" -o printer-error-policy=retry-job 2>/dev/null || true
    
    ((SUCCESS_COUNT++))
    return 0
}

# Install all printers (organized by library)
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

# Final summary
echo ""
echo "==========================================="
echo "📊 Installation Summary"
echo "==========================================="
echo "✅ Successfully installed: $SUCCESS_COUNT printers"
echo "⏭️  Already installed: $SKIP_COUNT printers" 
echo "❌ Failed: $FAIL_COUNT printers"
echo "📝 Log saved to: $LOG_FILE"
echo "⏰ Completed: $(date)"

# Show completion dialog
if [ $FAIL_COUNT -eq 0 ]; then
    osascript -e "display dialog \"🎉 Success! All UMD library printers are now available.\\n\\n📊 Summary:\\n• $SUCCESS_COUNT printers installed\\n• $SKIP_COUNT already present\\n\\n🖨️ To print:\\n1. Print from any application\\n2. Choose your library printer\\n3. Use UMD credentials at printer\\n\\n📞 Help: help@umd.edu\" buttons {\"Great!\"} with icon note"
    echo "🎉 Installation completed successfully!"
elif [ $SUCCESS_COUNT -gt 0 ]; then
    osascript -e "display dialog \"⚠️ Partial success\\n\\n📊 Results:\\n• $SUCCESS_COUNT installed successfully\\n• $FAIL_COUNT failed\\n\\n✅ Working printers are ready to use\\n📞 Help: help@umd.edu\" buttons {\"OK\"} with icon caution"  
    echo "⚠️  Partial success - some printers installed"
else
    osascript -e "display dialog \"❌ Installation failed\\n\\nNo printers were installed. Please check your connection and try again.\\n\\n📞 Help: help@umd.edu\" buttons {\"OK\"} with icon stop"
    echo "❌ Installation failed completely"
    exit 1
fi

echo ""
echo "Ready for UMD mobile printing! 🎓"