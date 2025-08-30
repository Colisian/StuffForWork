#!/bin/bash
# UMD Pharos Mobile Print Installer
# Public Distribution Version - Compatible with all modern macOS versions
# Created for UMD students to install mobile printing support

set -e

# Enhanced error handling with user-friendly messages
trap 'osascript -e "display dialog \"Installation encountered an error. Please try again or contact IT Support at help@umd.edu for assistance.\" buttons {\"OK\"} with icon stop"' ERR

# Create timestamped log file
LOG_FILE="$HOME/Desktop/UMD_MobilePrint_Install_$(date +%Y%m%d_%H%M%S).log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Pharos Mobile Print Installer v2.0"
echo "Compatible with macOS 10.14 and later"
echo "==========================================="
echo "Started: $(date)"
echo "macOS Version: $(sw_vers -productVersion)"
echo "User: $(whoami)"
echo "Log: $LOG_FILE"
echo ""

# Function to check system compatibility
check_compatibility() {
    echo "🔍 Checking system compatibility..."
    
    # Check macOS version
    OS_VERSION=$(sw_vers -productVersion)
    OS_MAJOR=$(echo $OS_VERSION | cut -d. -f1)
    OS_MINOR=$(echo $OS_VERSION | cut -d. -f2)
    
    if [[ $OS_MAJOR -lt 10 ]] || [[ $OS_MAJOR -eq 10 && $OS_MINOR -lt 14 ]]; then
        echo " This installer requires macOS 10.14 or later"
        echo "   Your version: $OS_VERSION"
        osascript -e 'display dialog "This installer requires macOS 10.14 (Mojave) or later. Please update your Mac or contact IT Support." buttons {"OK"} with icon stop'
        exit 1
    fi
    
    echo "macOS $OS_VERSION is supported"
}

# Function to check admin privileges
check_admin() {
    echo " Checking administrator privileges..."
    
    if ! sudo -n true 2>/dev/null; then
        echo "ℹ Administrator privileges required for installation"
        osascript -e 'display dialog "This installer needs administrator privileges to install printers.\n\nYou will be prompted for your Mac password." buttons {"Continue", "Cancel"} default button "Continue" with icon note' > /dev/null
        
        # Test sudo access
        if ! sudo -v; then
            echo " Administrator privileges required but not granted"
            osascript -e 'display dialog "Installation cancelled. Administrator privileges are required to install printers." buttons {"OK"} with icon stop'
            exit 1
        fi
    fi
    
    echo " Administrator privileges confirmed"
}

# Function to check network connectivity
check_network() {
    echo " Checking network connectivity..."
    
    if ping -c 1 -W 3000 LIBRPS406DV.AD.UMD.EDU &>/dev/null; then
        echo " Can reach UMD Pharos server"
    else
        echo "  Cannot reach UMD Pharos server"
        echo "   Make sure you're connected to:"
        echo "   • UMD campus WiFi, or"
        echo "   • UMD VPN if off-campus"
        
        osascript -e 'display dialog "Cannot reach the UMD print server.\n\nPlease ensure you are connected to:\n• UMD campus WiFi, or\n• UMD VPN if off-campus\n\nInstallation will continue, but printing may not work until connected." buttons {"Continue Anyway", "Cancel"} default button "Continue Anyway" with icon caution' > /dev/null
    fi
}

# Run compatibility checks
check_compatibility
check_admin  
check_network

echo ""
echo "Installing Pharos Popup Client..."

# Install Pharos Popup Client
POPUP_PKG="$(dirname "$0")/Popup.pkg"

if [ ! -f "$POPUP_PKG" ]; then
    echo " ERROR: Popup.pkg not found"
    echo "   Expected location: $POPUP_PKG"
    osascript -e 'display dialog "Installation files are missing. Please download a fresh copy from the UMD website." buttons {"OK"} with icon stop'
    exit 1
fi

# Check if already installed
if [ -d "/Library/Application Support/Pharos" ] || [ -d "/Applications/Utilities/Pharos" ]; then
    echo " Pharos client already installed, skipping..."
else
    echo "   Installing from: $POPUP_PKG"
    if sudo installer -pkg "$POPUP_PKG" -target / -verbose; then
        echo "Pharos popup client installed successfully"
    else
        echo " Failed to install Pharos popup client"
        exit 1
    fi
fi

echo ""
echo "  Configuring UMD Library Mobile Print Queues..."

# Define all UMD library printers with organized structure
declare -A library_printers=(
    ["Architecture Library"]="LIB-ArchMobileBW LIB-ArchMobileColor"
    ["Art Library"]="LIB-ArtMobileBW LIB-ArtMobileColor"  
    ["EPSL Library"]="LIB-EPSLMobileBW LIB-EPSLMobileColor"
    ["Hornbake Library"]="LIB-HBKMobileBW LIB-HBKMobileColor"
    ["Maryland Room"]="LIB-MarylandRoomMobileBW LIB-MarylandRoomMobileColor"
    ["McKeldin Library"]="LIB-McKMobileBW LIB-McKMobileColor LIB-Mck2FMobileWideFormat"
    ["PAL Library"]="LIB-PALMobileBW LIB-PALMobileColor"
)

PHAROS_SERVER="LIBRPS406DV.AD.UMD.EDU"
PHAROS_PORT="515"
TOTAL_INSTALLED=0
TOTAL_SKIPPED=0
TOTAL_FAILED=0

# Install printers by library location
for library in "${!library_printers[@]}"; do
    echo ""
    echo " $library:"
    
    for printer in ${library_printers[$library]}; do
        printer_uri="popup://$PHAROS_SERVER:$PHAROS_PORT/$printer"
        
        # Determine printer type for description
        if [[ $printer == *"BW"* ]]; then
            printer_type="Black & White"
        elif [[ $printer == *"Color"* ]]; then
            printer_type="Color"
        elif [[ $printer == *"WideFormat"* ]]; then
            printer_type="Wide Format"
        else
            printer_type="Printer"
        fi
        
        printer_description="$library - $printer_type"
        
        if lpstat -p "$printer" &>/dev/null; then
            echo "     $printer: Already installed"
            ((TOTAL_SKIPPED++))
        else
            echo "   🔧 Installing: $printer ($printer_type)"
            
            # Try multiple CUPS installation methods for maximum compatibility
            if sudo /usr/sbin/lpadmin -p "$printer" -E -v "$printer_uri" -m everywhere -D "$printer_description" 2>/dev/null; then
                echo "       Installed with IPP Everywhere driver"
            elif sudo /usr/sbin/lpadmin -p "$printer" -E -v "$printer_uri" -m lsb/usr/cupsfilters/generic-pdf-to-ps.ppd -D "$printer_description" 2>/dev/null; then
                echo "       Installed with generic PDF driver"  
            elif sudo /usr/sbin/lpadmin -p "$printer" -E -v "$printer_uri" -D "$printer_description" 2>/dev/null; then
                echo "       Installed with system default driver"
            else
                echo "       Failed to install $printer"
                ((TOTAL_FAILED++))
                continue
            fi
            
            # Configure printer options
            sudo /usr/sbin/lpadmin -p "$printer" -o printer-is-shared=false 2>/dev/null || true
            sudo /usr/sbin/lpadmin -p "$printer" -o printer-error-policy=retry-job 2>/dev/null || true
            
            ((TOTAL_INSTALLED++))
        fi
    done
done

echo ""
echo "==========================================="
echo " Installation Summary"
echo "==========================================="
echo "Printers installed: $TOTAL_INSTALLED"
echo "Printers skipped (already installed): $TOTAL_SKIPPED"
echo "Printers failed: $TOTAL_FAILED"
echo "Log file: $LOG_FILE"
echo "Completed: $(date)"
echo ""

# Show appropriate completion dialog
if [ $TOTAL_FAILED -eq 0 ]; then
    # Perfect success
    osascript -e "display dialog \"SUCCESS! All UMD library printers installed!\\n\\n📊 Summary:\\n• $TOTAL_INSTALLED printers installed\\n• $TOTAL_SKIPPED printers were already present\\n\\n How to Print:\\n1. Print from any Mac application\\n2. Select your desired library printer\\n3. Use your UMD credentials at the printer to release jobs\\n\\n📞 Need help? Contact help@umd.edu\" buttons {\"Great!\"} default button \"Great!\" with icon note"
    echo "🎉 SUCCESS: All printers installed successfully!"
elif [ $TOTAL_INSTALLED -gt 0 ]; then
    # Partial success
    osascript -e "display dialog \" Installation completed with some issues\\n\\n📊 Summary:\\n• $TOTAL_INSTALLED printers installed successfully\\n• $TOTAL_FAILED printers failed\\n• $TOTAL_SKIPPED printers were already present\\n\\n You can use the successfully installed printers immediately\\n\\n📞 Need help? Contact help@umd.edu\" buttons {\"OK\"} default button \"OK\" with icon caution"
    echo "⚠️  PARTIAL SUCCESS: Some printers installed successfully"
else
    # Complete failure
    osascript -e "display dialog \" Installation failed\\n\\nNo printers were installed successfully.\\nPlease check your network connection and try again.\\n\\n📞 Need help? Contact help@umd.edu\" buttons {\"OK\"} default button \"OK\" with icon stop"
    echo " FAILURE: No printers were installed"
    exit 1
fi

echo ""
echo "🎓 Ready for UMD Mobile Printing!"
echo "Thank you for using UMD IT services."