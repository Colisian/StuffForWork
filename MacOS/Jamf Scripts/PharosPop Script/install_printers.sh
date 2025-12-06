#!/bin/bash
# Combined UMD Library Printers + Canon Driver Installation
# Version 4.8 - Fixed Pharos App Bundle Detection

LOG_FILE="/var/log/umd_printer_install.log"
exec &> >(tee -a "$LOG_FILE")

echo "==========================================="
echo "UMD Library Printers Installation"
echo "Version 4.8 - Fixed Pharos App Detection"
echo "==========================================="
echo "Started: $(date)"
echo "macOS: $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"
echo "Running as user: $(whoami)"
echo "Target volume: $3"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ This script must be run as root"
    exit 1
fi

#===========================================
# PART 1: Canon Driver Post-Install Tasks
#===========================================

echo "🔧 Running Canon driver post-install tasks..."

# Get current OS version
currentOSVersion=`sw_vers -productVersion`
currentMajor=`echo "$currentOSVersion" | cut -d '.' -f1`
currentMinor=`echo "$currentOSVersion" | cut -d '.' -f2`
currentRevision=`echo "$currentOSVersion" | cut -d '.' -f3`

if [ -z "$currentRevision" ] ; then
    currentRevision=0
fi

currentMajor=`expr "$currentMajor" '*' 10000`
currentMinor=`expr "$currentMinor" '*' 100`
currentOSVersion=`expr "$currentMajor" + "$currentMinor" + "$currentRevision"`

# For macOS < 10.6, strip x86_64 architecture
if [ "$currentOSVersion" -lt 100600 ] ; then
    echo "   Old macOS detected, stripping x86_64 binaries..."
    lipo -remove x86_64 -output "$3/Library/Printers/Canon/CUPS_Printer/Bins/Bins.bundle/Contents/Library/xdclfilter" "$3/Library/Printers/Canon/CUPS_Printer/Bins/Bins.bundle/Contents/Library/xdclfilter" 2>/dev/null
    lipo -remove x86_64 -output "$3/Library/Printers/Canon/CUPS_Printer/Utilities/Canon Office Printer Utility.app/Contents/MacOS/Canon Office Printer Utility" "$3/Library/Printers/Canon/CUPS_Printer/Utilities/Canon Office Printer Utility.app/Contents/MacOS/Canon Office Printer Utility" 2>/dev/null
    lipo -remove x86_64 -output "$3/Library/Printers/Canon/CUPS_Printer/Utilities/autoSetupTool.app/Contents/MacOS/autoSetupTool" "$3/Library/Printers/Canon/CUPS_Printer/Utilities/autoSetupTool.app/Contents/MacOS/autoSetupTool" 2>/dev/null
    
    # Set permissions
    chmod 1775 "$3/"
    chown root:admin "$3/"
    chmod 1775 "$3/Library"
    chown root:admin "$3/Library"
    chmod 775 "$3/Library/Printers"
    chown root:admin "$3/Library/Printers"
    chmod 775 "$3/Library/Printers/Canon"
    chown root:admin "$3/Library/Printers/Canon"
fi

# For macOS >= 10.9, cleanup old queues
if [ "$currentOSVersion" -ge 100900 ] ; then
    echo "   Cleaning up legacy Canon queues..."
    if [ -f "./DeleteQueues" ]; then
        ./DeleteQueues 2>/dev/null || true
    fi
    rm -rf "$3/Library/LaunchAgents/jp.co.canon.LIPSLX.BG.plist" 2>/dev/null || true
    rm -rf "$3/Library/LaunchAgents/jp.co.canon.UFR2.BG.plist" 2>/dev/null || true
    rm -rf "$3/Library/LaunchAgents/jp.co.canon.CARPS2.BG.plist" 2>/dev/null || true
    rm -rf "$3/Library/LaunchAgents/jp.co.canon.CUPSCMFP.BG.plist" 2>/dev/null || true
fi

echo "   ✅ Canon driver post-install completed"

# CRITICAL: Wait for system to register Canon drivers
echo ""
echo "⏳ Waiting for Canon drivers to register with CUPS..."
sleep 5

# Force CUPS to reload PPDs
echo "   Restarting CUPS to load Canon drivers..."
launchctl stop org.cups.cupsd 2>/dev/null || true
sleep 2
launchctl start org.cups.cupsd 2>/dev/null || true
sleep 3

# Wait for CUPS to fully start
MAX_WAIT=30
WAIT_COUNT=0
until pgrep -x cupsd > /dev/null || [ $WAIT_COUNT -eq $MAX_WAIT ]; do
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if pgrep -x cupsd > /dev/null; then
    echo "   ✅ CUPS service running"
else
    echo "   ❌ ERROR: CUPS failed to start after $MAX_WAIT seconds"
    exit 1
fi

# Additional wait for CUPS to fully initialize
sleep 5

#===========================================
# PART 2: Verify Pharos Popup Installation (FIXED FOR .APP BUNDLE)
#===========================================

echo ""
echo "🔍 Verifying Pharos Popup application..."

# Define the target location for the popup backend
POPUP_BACKEND="/usr/libexec/cups/backend/popup"

# Possible Pharos Popup.app locations and their executable paths
PHAROS_APP_LOCATIONS=(
    "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/Popup"
    "/Applications/Pharos/Popup.app/Contents/MacOS/Popup"
    "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/popup"
    "/Applications/Popup.app/Contents/MacOS/Popup"
)

POPUP_BINARY=""

# First check if the backend symlink already exists and works
if [ -x "$POPUP_BACKEND" ]; then
    echo "   ✅ Pharos popup backend already configured at: $POPUP_BACKEND"
    POPUP_BINARY=$(readlink "$POPUP_BACKEND" 2>/dev/null || echo "$POPUP_BACKEND")
    echo "      → Points to: $POPUP_BINARY"
else
    # Search for the Pharos Popup.app and its executable
    echo "   🔍 Searching for Pharos Popup.app executable..."
    
    # First, try the known locations
    for location in "${PHAROS_APP_LOCATIONS[@]}"; do
        if [ -f "$location" ] && [ -x "$location" ]; then
            POPUP_BINARY="$location"
            echo "   ✅ Found Pharos Popup executable at: $POPUP_BINARY"
            break
        fi
    done
    
    # If not found, search for Popup.app and locate its executable
    if [ -z "$POPUP_BINARY" ]; then
        echo "   🔍 Searching for Popup.app bundle..."
        
        # Find Popup.app
        POPUP_APP=$(find "/Library/Application Support/Pharos" -name "Popup.app" -type d 2>/dev/null | head -1)
        
        if [ -z "$POPUP_APP" ]; then
            # Try broader search
            POPUP_APP=$(find /Library /Applications -name "Popup.app" -type d 2>/dev/null | head -1)
        fi
        
        if [ -n "$POPUP_APP" ]; then
            echo "   ✅ Found Popup.app at: $POPUP_APP"
            
            # Look for the executable inside the app bundle
            # Try both capitalized and lowercase versions
            if [ -f "$POPUP_APP/Contents/MacOS/Popup" ]; then
                POPUP_BINARY="$POPUP_APP/Contents/MacOS/Popup"
            elif [ -f "$POPUP_APP/Contents/MacOS/popup" ]; then
                POPUP_BINARY="$POPUP_APP/Contents/MacOS/popup"
            fi
            
            if [ -n "$POPUP_BINARY" ]; then
                echo "   ✅ Found executable: $POPUP_BINARY"
                
                # Verify it's executable
                if [ ! -x "$POPUP_BINARY" ]; then
                    echo "   ⚠️  Making executable..."
                    chmod +x "$POPUP_BINARY"
                fi
            else
                echo "   ❌ ERROR: Found Popup.app but no executable inside!"
                echo "   📁 App bundle contents:"
                ls -la "$POPUP_APP/Contents/MacOS/" 2>/dev/null | sed 's/^/      /' || echo "      MacOS directory not found"
            fi
        fi
    fi
    
    # Final check - if we found the binary, create the symlink
    if [ -n "$POPUP_BINARY" ] && [ -x "$POPUP_BINARY" ]; then
        echo "   🔗 Creating CUPS backend symlink..."
        
        # Ensure the backend directory exists
        mkdir -p /usr/libexec/cups/backend 2>/dev/null || true
        
        # Create the symlink
        ln -sf "$POPUP_BINARY" "$POPUP_BACKEND"
        
        # Ensure permissions are correct
        chmod 755 "$POPUP_BACKEND" 2>/dev/null || true
        
        # Verify the symlink works
        if [ -x "$POPUP_BACKEND" ]; then
            echo "   ✅ Popup backend symlink created successfully"
            echo "      $POPUP_BACKEND → $POPUP_BINARY"
        else
            echo "   ❌ ERROR: Symlink created but not executable!"
            ls -la "$POPUP_BACKEND" 2>/dev/null | sed 's/^/      /'
            exit 1
        fi
    else
        # Absolute failure - Pharos not found or not executable
        echo "   ❌ ERROR: Pharos Popup executable not found or not executable!"
        echo ""
        echo "   Diagnostic information:"
        echo "   📁 Pharos directory contents:"
        if [ -d "/Library/Application Support/Pharos" ]; then
            ls -la "/Library/Application Support/Pharos/" 2>/dev/null | sed 's/^/      /'
            
            # If Popup.app exists, show its structure
            if [ -d "/Library/Application Support/Pharos/Popup.app" ]; then
                echo ""
                echo "   📦 Popup.app structure:"
                ls -la "/Library/Application Support/Pharos/Popup.app/Contents/" 2>/dev/null | sed 's/^/      /'
                echo ""
                echo "   🔧 MacOS directory:"
                ls -la "/Library/Application Support/Pharos/Popup.app/Contents/MacOS/" 2>/dev/null | sed 's/^/      /'
            fi
        else
            echo "      Pharos directory not found!"
        fi
        echo ""
        echo "   REQUIRED: Please ensure Popup.pkg is properly installed"
        echo "   Expected: /Library/Application Support/Pharos/Popup.app/Contents/MacOS/Popup"
        exit 1
    fi
fi

# Final verification that popup backend is accessible to CUPS
if [ -x "$POPUP_BACKEND" ]; then
    echo ""
    echo "   ✅ Final verification: Popup backend is executable and ready"
    
    # Show backend details
    echo "   📋 Backend details:"
    ls -lh "$POPUP_BACKEND" | sed 's/^/      /'
    
    # If it's a symlink, show the target
    if [ -L "$POPUP_BACKEND" ]; then
        echo "   🔗 Symlink target:"
        readlink "$POPUP_BACKEND" | sed 's/^/      /'
    fi
    
    # Check file type
    echo "   📄 File type:"
    file "$POPUP_BACKEND" | sed 's/^/      /'
else
    echo "   ❌ ERROR: Popup backend exists but is not executable!"
    echo "   This will prevent printer installation from working"
    exit 1
fi

#===========================================
# PART 3: Verify Canon PPD Driver
#===========================================

echo ""
echo "🔍 Verifying Canon PPD driver installation..."

CANON_PPD=""
PPD_LOCATIONS=(
    "/Library/Printers/PPDs/Contents/Resources"
)

for location in "${PPD_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        # Look for our specific Canon PPD (compressed)
        CANON_PPD=$(find "$location" -name "CNPZUIRAC5030ZU.ppd.gz" 2>/dev/null | head -1)
        if [ -n "$CANON_PPD" ]; then
            echo "   ✅ Found target Canon PPD: $(basename "$CANON_PPD")"
            echo "      Full path: $CANON_PPD"
            break
        fi
        
        # Fallback: Look for any Canon UFR II PPD
        CANON_PPD=$(find "$location" -name "*UFRII*.ppd.gz" -o -name "CNPZ*.ppd.gz" 2>/dev/null | head -1)
        if [ -n "$CANON_PPD" ]; then
            echo "   ✅ Found alternative Canon PPD: $(basename "$CANON_PPD")"
            echo "      Full path: $CANON_PPD"
            break
        fi
    fi
done

if [ -z "$CANON_PPD" ]; then
    echo ""
    echo "   ❌ ERROR: No Canon PPD driver found!"
    echo ""
    echo "   Searching for Canon PPDs..."
    find /Library/Printers -name "*.ppd.gz" -o -name "*.ppd" 2>/dev/null | grep -i canon | sed 's/^/      /' || echo "      No Canon PPDs found"
    echo ""
    exit 1
fi

# Test if PPD is readable
if [ -r "$CANON_PPD" ]; then
    echo "   ✅ PPD is readable"
    PPD_SIZE=$(ls -lh "$CANON_PPD" | awk '{print $5}')
    echo "   📏 PPD size: $PPD_SIZE"
else
    echo "   ❌ ERROR: PPD exists but is not readable!"
    exit 1
fi

#===========================================
# PART 4: Remove Old Printers (if any)
#===========================================

echo ""
echo "🔍 Checking for existing UMD Library printers..."
EXISTING_PRINTERS=$(lpstat -p 2>/dev/null | grep "LIB-" | awk '{print $2}')

if [ -n "$EXISTING_PRINTERS" ]; then
    EXISTING_COUNT=$(echo "$EXISTING_PRINTERS" | wc -l | tr -d ' ')
    echo "   ⚠️  Found $EXISTING_COUNT existing printer(s)"
    echo ""
    echo "🗑️  Removing old printers for clean installation..."
    
    echo "$EXISTING_PRINTERS" | while read printer; do
        if [ -n "$printer" ]; then
            echo "   Removing: $printer"
            lpadmin -x "$printer" 2>&1
        fi
    done
    
    sleep 2
    REMAINING=$(lpstat -p 2>/dev/null | grep -c "LIB-" || echo "0")
    
    if [ "$REMAINING" -eq "0" ]; then
        echo "   ✅ All old printers removed successfully"
    else
        echo "   ⚠️  Warning: $REMAINING printer(s) may still exist"
    fi
    echo ""
else
    echo "   ✅ No existing UMD Library printers found (clean install)"
    echo ""
fi

#===========================================
# PART 5: Install Printers
#===========================================

echo ""
echo "🖨️  Installing UMD Library Printers with Canon driver..."
echo "   Using PPD: $(basename "$CANON_PPD")"
echo "   Using Pharos backend: $POPUP_BACKEND"
echo ""

# Initialize counters
SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_PRINTERS=()

# Pharos server configuration
PHAROS_SERVER="LIBRPS406DV.AD.UMD.EDU"
PHAROS_PORT="515"

# Printer installation function
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
    
    # Check if printer already exists
    if lpstat -p "$name" &>/dev/null; then
        echo "      ⚠️  Printer already exists, forcing removal..."
        lpadmin -x "$name" 2>&1
        sleep 1
    fi
    
    # Install with PPD
    echo "      🔨 Running lpadmin command..."
    local install_output
    local exit_code
    
    install_output=$(lpadmin -p "$name" -E -v "$uri" -P "$CANON_PPD" -D "$description" -L "$location" 2>&1)
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "      ❌ Installation FAILED (exit code: $exit_code)"
        echo "      Error output:"
        echo "$install_output" | sed 's/^/         /'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_PRINTERS+=("$name")
        return 1
    fi
    
    # Verify printer was created
    sleep 1
    if ! lpstat -p "$name" &>/dev/null; then
        echo "      ❌ Command succeeded but printer not found!"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_PRINTERS+=("$name")
        return 1
    fi
    
    echo "      ✅ Printer created successfully"
    
    # Configure printer options
    lpadmin -p "$name" -o printer-is-shared=false 2>&1 || true
    lpadmin -p "$name" -o printer-error-policy=retry-job 2>&1 || true
    
    # Special configuration for Architecture printers (11x17 support)
    if [[ "$name" == *"Arch"* ]]; then
        echo "      📐 Configuring 11x17 (Tabloid) support..."
        lpadmin -p "$name" -o PageSize=Tabloid 2>&1 || true
        lpadmin -p "$name" -o MediaType=Plain 2>&1 || true
        lpadmin -p "$name" -o InputSlot=Auto 2>&1 || true
    fi
    
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    return 0
}

# Install all printers
echo "═══════════════════════════════════════════"
echo "📚 Installing Library Printers..."
echo "═══════════════════════════════════════════"

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
# PART 6: Final Verification
#===========================================

echo ""
echo "═══════════════════════════════════════════"
echo "🔍 FINAL VERIFICATION"
echo "═══════════════════════════════════════════"

# Refresh CUPS
echo ""
echo "🔄 Final CUPS refresh..."
launchctl stop org.cups.cupsd 2>/dev/null || true
sleep 1
launchctl start org.cups.cupsd 2>/dev/null || true
sleep 3

# Count installed printers
INSTALLED_PRINTERS=$(lpstat -p 2>/dev/null | grep -c "LIB-" || echo "0")
echo ""
echo "📊 System printer count: $INSTALLED_PRINTERS UMD Library printers"

if [ "$INSTALLED_PRINTERS" -gt 0 ]; then
    echo ""
    echo "   📋 Confirmed installed printers:"
    lpstat -p 2>/dev/null | grep "LIB-" | awk '{print "      ✅ " $2}' || true
fi

# Final summary
echo ""
echo "==========================================="
echo "📊 INSTALLATION SUMMARY"
echo "==========================================="
echo "✅ Successfully installed: $SUCCESS_COUNT printers"
echo "❌ Failed: $FAIL_COUNT printers"

if [ ${#FAILED_PRINTERS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Failed printers:"
    for failed in "${FAILED_PRINTERS[@]}"; do
        echo "   • $failed"
    done
fi

echo ""
echo "⏰ Completed: $(date)"
echo "📝 Full log: $LOG_FILE"
echo "==========================================="

# Exit with appropriate code
if [ "$FAIL_COUNT" -eq 0 ] && [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo ""
    echo "✅ Installation completed successfully!"
    echo "   All $SUCCESS_COUNT printers are ready to use"
    exit 0
elif [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo ""
    echo "⚠️  Partial success: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed"
    exit 1
else
    echo ""
    echo "❌ Installation FAILED - No printers were installed"
    exit 1
fi