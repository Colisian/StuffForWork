#!/bin/bash
# UMD Library Printers Installation Script for Jamf
# Version 3.1-JAMF-CANON
# Requires: Canon UFR II Driver + Popup.pkg
# Auto-removes old printers before installing new ones

LOG_FILE="/var/log/umd_printer_install.log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Library Printers Installation"
echo "Canon UFR II + Jamf Deployment"
echo "Version 3.1 - Auto Upgrade"
echo "==========================================="
echo "Started: $(date)"
echo "macOS: $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ This script must be run as root"
    exit 1
fi

#===========================================
# STEP 1: Remove Old Printers (if any)
#===========================================
echo "🔍 Checking for existing UMD printers..."
EXISTING_PRINTERS=$(lpstat -p 2>/dev/null | grep "LIB-" | awk '{print $2}')

if [ -n "$EXISTING_PRINTERS" ]; then
    EXISTING_COUNT=$(echo "$EXISTING_PRINTERS" | wc -l | tr -d ' ')
    echo "⚠️  Found $EXISTING_COUNT existing UMD printer(s)"
    echo ""
    echo "🗑️  Removing old printers for clean installation..."
    
    echo "$EXISTING_PRINTERS" | while read printer; do
        if [ -n "$printer" ]; then
            echo "   Removing: $printer"
            lpadmin -x "$printer" 2>/dev/null || true
        fi
    done
    
    # Verify removal
    sleep 2
    REMAINING=$(lpstat -p 2>/dev/null | grep -c "LIB-" || echo "0")
    
    if [ "$REMAINING" -eq "0" ]; then
        echo "   ✅ All old printers removed successfully"
    else
        echo "   ⚠️  Warning: $REMAINING printer(s) may still exist"
    fi
    echo ""
else
    echo "✅ No existing UMD printers found (clean install)"
    echo ""
fi

#===========================================
# STEP 2: Verify Prerequisites
#===========================================

# Check CUPS service
echo "🔍 Checking print system status..."
if ! pgrep -x cupsd > /dev/null; then
    echo "⚠️  CUPS service not running, attempting to start..."
    launchctl kickstart -k system/org.cups.cupsd 2>/dev/null || \
    launchctl load -w /System/Library/LaunchDaemons/org.cups.cupsd.plist 2>/dev/null || true
    sleep 3
fi

if pgrep -x cupsd > /dev/null; then
    echo "✅ CUPS service is running"
else
    echo "⚠️  CUPS service not detected (continuing anyway)"
fi

# Verify Pharos Popup is installed
echo ""
echo "🔍 Verifying Pharos installation..."
POPUP_BACKEND="/usr/libexec/cups/backend/popup"

if [ -f "$POPUP_BACKEND" ] || [ -L "$POPUP_BACKEND" ]; then
    echo "✅ Pharos popup backend found"
elif [ -f "/Library/Application Support/Pharos/popup" ]; then
    echo "⚠️  Creating popup backend symlink..."
    ln -sf "/Library/Application Support/Pharos/popup" "$POPUP_BACKEND"
    chmod 755 "$POPUP_BACKEND" 2>/dev/null || true
    echo "✅ Popup backend symlink created"
else
    echo "❌ ERROR: Pharos Popup not installed!"
    echo "   Please ensure Popup.pkg is deployed first"
    exit 1
fi

# Verify Canon UFR II Driver is installed
echo ""
echo "🔍 Verifying Canon UFR II driver..."

CANON_PPD=""
PPD_LOCATIONS=(
    "/Library/Printers/PPDs/Contents/Resources"
    "/Library/Printers/Canon/UFR2/Resources"
)

for location in "${PPD_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        # Find any Canon PPD file
        CANON_PPD=$(find "$location" -name "CNPZ*.ppd.gz" 2>/dev/null | head -1)
        if [ -n "$CANON_PPD" ]; then
            echo "✅ Found Canon PPD: $(basename "$CANON_PPD")"
            break
        fi
    fi
done

if [ -z "$CANON_PPD" ]; then
    echo "❌ ERROR: Canon UFR II driver not found!"
    echo "   Please ensure Canon driver package is deployed first"
    echo "   Expected location: /Library/Printers/PPDs/Contents/Resources/"
    exit 1
fi

#===========================================
# STEP 3: Install Printers with Canon Driver
#===========================================

echo ""
echo "🖨️  Installing UMD Library Printers with Canon UFR II driver..."

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
    echo "   📝 Installing: $name"
    echo "      Location: $location"
    echo "      Type: $type"
    
    # Check if somehow still installed (shouldn't happen after removal)
    if lpstat -p "$name" &>/dev/null; then
        echo "      ⚠️  Printer still exists, forcing removal..."
        lpadmin -x "$name" 2>/dev/null || true
        sleep 1
    fi
    
    # Install with Canon PPD - capture full output but check exit code
    local install_output
    install_output=$(lpadmin -p "$name" -E -v "$uri" -P "$CANON_PPD" -D "$description" -L "$location" 2>&1)
    local exit_code=$?
    
    # Check if installation succeeded by exit code
    if [ $exit_code -eq 0 ]; then
        echo "      ✅ Installed with Canon UFR II driver"
        
        # Configure basic printer options
        lpadmin -p "$name" -o printer-is-shared=false 2>/dev/null || true
        lpadmin -p "$name" -o printer-error-policy=retry-job 2>/dev/null || true
        
        # Special configuration for Architecture printers (11x17 support)
        if [[ "$name" == *"Arch"* ]]; then
            echo "      📐 Configuring 11x17 (Tabloid) support..."
            lpadmin -p "$name" -o PageSize=Tabloid 2>/dev/null || true
            lpadmin -p "$name" -o MediaType=Plain 2>/dev/null || true
            lpadmin -p "$name" -o InputSlot=Auto 2>/dev/null || true
            echo "      ✅ 11x17 support enabled"
        fi
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        echo "      ❌ Installation failed"
        echo "      Error: $install_output"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Install all printers by library
echo ""
echo "📚 Architecture Library"
install_printer "LIB-ArchMobileBW" "Architecture Library" "Black & White"
install_printer "LIB-ArchMobileColor" "Architecture Library" "Color"

echo ""
echo "📚 Art Library"
install_printer "LIB-ArtMobileBW" "Art Library" "Black & White"
install_printer "LIB-ArtMobileColor" "Art Library" "Color"

echo ""
echo "📚 EPSL Library"
install_printer "LIB-EPSLMobileBW" "EPSL Library" "Black & White"
install_printer "LIB-EPSLMobileColor" "EPSL Library" "Color"

echo ""
echo "📚 Hornbake Library"
install_printer "LIB-HBKMobileBW" "Hornbake Library" "Black & White"
install_printer "LIB-HBKMobileColor" "Hornbake Library" "Color"

echo ""
echo "📚 Maryland Room"
install_printer "LIB-MarylandRoomMobileBW" "Maryland Room" "Black & White"
install_printer "LIB-MarylandRoomMobileColor" "Maryland Room" "Color"

echo ""
echo "📚 McKeldin Library"
install_printer "LIB-McKMobileBW" "McKeldin Library" "Black & White"
install_printer "LIB-McKMobileColor" "McKeldin Library" "Color"
install_printer "LIB-Mck2FMobileWideFormat" "McKeldin Library" "Wide Format"

echo ""
echo "📚 PAL Library"
install_printer "LIB-PALMobileBW" "PAL Library" "Black & White"
install_printer "LIB-PALMobileColor" "PAL Library" "Color"

#===========================================
# STEP 4: Verification
#===========================================

# Refresh print system
echo ""
echo "🔄 Refreshing print system..."
launchctl stop org.cups.cupsd 2>/dev/null || true
sleep 1
launchctl start org.cups.cupsd 2>/dev/null || true
sleep 2

# Verification
echo ""
echo "🔍 Verifying installation..."
INSTALLED_PRINTERS=$(lpstat -p 2>/dev/null | grep -c "LIB-" || echo "0")
echo "   Found $INSTALLED_PRINTERS UMD printers in system"

if [ "$INSTALLED_PRINTERS" -gt 0 ]; then
    echo ""
    echo "   📋 Installed printers:"
    lpstat -p | grep "LIB-" | awk '{print "      • " $2}' || true
fi

# Verify 11x17 support on Architecture printers
echo ""
echo "🔍 Verifying 11x17 support on Architecture printers..."
for printer in LIB-ArchMobileBW LIB-ArchMobileColor; do
    if lpstat -p "$printer" &>/dev/null; then
        echo ""
        echo "   📄 $printer:"
        if lpoptions -p "$printer" -l 2>/dev/null | grep -qi "tabloid\|11x17\|ledger"; then
            echo "      ✅ 11x17/Tabloid support confirmed"
        else
            echo "      ⚠️  11x17 not detected in options"
            echo "      Available sizes:"
            lpoptions -p "$printer" -l 2>/dev/null | grep -i "PageSize" | head -3 || echo "      Unable to query"
        fi
    fi
done

# Final summary
echo ""
echo "==========================================="
echo "📊 Installation Summary"
echo "==========================================="
echo "✅ Successfully installed: $SUCCESS_COUNT printers"
echo "⏭️  Already present: $SKIP_COUNT printers"
echo "❌ Failed: $FAIL_COUNT printers"
echo "⏰ Completed: $(date)"
echo "==========================================="

# Exit with appropriate code for Jamf
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo ""
    echo "✅ Installation completed successfully"
    echo "📝 Log file: $LOG_FILE"
    exit 0
else
    echo ""
    echo "⚠️  Installation completed with $FAIL_COUNT error(s)"
    echo "📝 Log file: $LOG_FILE"
    exit 1
fi