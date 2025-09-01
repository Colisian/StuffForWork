#!/bin/bash
# Diagnostic script to test the installer package - Version 2
# This version correctly checks the Scripts directory for embedded files

echo "==========================================="
echo "UMD Installer Package Diagnostic Test v2"
echo "==========================================="
echo ""

# Check if the package exists
PKG_FILE="UMD_Library_Printers_Installer.pkg"
if [ ! -f "$PKG_FILE" ]; then
    echo "❌ Package file not found: $PKG_FILE"
    exit 1
fi

echo "📦 Found package: $PKG_FILE"
echo "Package size: $(ls -lh "$PKG_FILE" | awk '{print $5}')"
echo "Package date: $(ls -lh "$PKG_FILE" | awk '{print $6, $7, $8}')"
echo ""

# Expand the package to examine contents
echo "🔍 Examining package contents..."
TEMP_DIR="/tmp/pkg_diagnostic_$$"
mkdir -p "$TEMP_DIR"

# Expand the package
pkgutil --expand "$PKG_FILE" "$TEMP_DIR/expanded"

echo ""
echo "📋 Package structure:"
ls -la "$TEMP_DIR/expanded/"

echo ""
echo "📋 UI Resources (welcome/conclusion screens):"
if [ -d "$TEMP_DIR/expanded/Resources" ]; then
    ls -la "$TEMP_DIR/expanded/Resources/"
else
    echo "No Resources directory (this is OK)"
fi

echo ""
echo "📋 Scripts directory contents (where the actual files should be):"
if [ -d "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts" ]; then
    ls -la "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/"
    
    echo ""
    echo "🔍 Checking for required files in Scripts directory:"
    
    # Check for Popup.pkg in Scripts
    if [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/Popup.pkg" ]; then
        echo "✅ Popup.pkg found ($(ls -lh "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/Popup.pkg" | awk '{print $5}'))"
    else
        echo "❌ Popup.pkg NOT found in Scripts directory"
    fi
    
    # Check for install script in Scripts (either .sh or .command)
    INSTALL_SCRIPT=""
    if [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/install_printers.sh" ]; then
        INSTALL_SCRIPT="install_printers.sh"
    elif [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/install_printers.command" ]; then
        INSTALL_SCRIPT="install_printers.command"
    fi
    
    if [ -n "$INSTALL_SCRIPT" ]; then
        echo "✅ $INSTALL_SCRIPT found ($(ls -lh "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/$INSTALL_SCRIPT" | awk '{print $5}'))"
        # Check if it's executable
        if [ -x "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/$INSTALL_SCRIPT" ]; then
            echo "   ✓ Script has execute permissions"
        else
            echo "   ⚠️  Script missing execute permissions"
        fi
    else
        echo "❌ install_printers script (.sh or .command) NOT found in Scripts directory"
    fi
    
    # Check for postinstall script
    if [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/postinstall" ]; then
        echo "✅ postinstall script found"
        if [ -x "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/postinstall" ]; then
            echo "   ✓ Postinstall has execute permissions"
        else
            echo "   ⚠️  Postinstall missing execute permissions"
        fi
    else
        echo "❌ postinstall script NOT found"
    fi
else
    echo "❌ No Scripts directory found - this is a problem!"
fi

echo ""
echo "📋 Postinstall script preview:"
if [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/postinstall" ]; then
    echo "First 20 lines of postinstall:"
    echo "-----------------------------------"
    head -20 "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/postinstall"
    echo "-----------------------------------"
fi

echo ""
echo "🔍 Checking recent installation logs..."

# Check for recent log entries (last 5 minutes)
CURRENT_TIME=$(date +%s)
FIVE_MIN_AGO=$((CURRENT_TIME - 300))

echo "📋 UMD printer install log (recent entries):"
if [ -f "/var/log/umd_printer_install.log" ]; then
    # Get entries from the last hour
    echo "Entries from the last hour:"
    echo "-----------------------------------"
    ONE_HOUR_AGO=$(date -v-1H "+%Y-%m-%d %H:%M")
    while IFS= read -r line; do
        # Check if line contains a timestamp
        if [[ $line == *"2025"* ]] || [[ $line == *"Started:"* ]] || [[ $line == *"Completed:"* ]] || [[ $line == *"ERROR"* ]] || [[ $line == *"Exit code"* ]]; then
            echo "$line"
        fi
    done < <(tail -50 /var/log/umd_printer_install.log)
    echo "-----------------------------------"
else
    echo "No UMD install log found at /var/log/umd_printer_install.log"
fi

echo ""
echo "🔍 Package validity check..."
# Run a basic verification
if pkgutil --check-signature "$PKG_FILE" 2>/dev/null; then
    echo "✅ Package signature check passed (or unsigned)"
else
    echo "⚠️  Package may have signature issues (this is usually OK for local packages)"
fi

echo ""
echo "📊 Summary:"
echo "-----------"
HAS_POPUP=false
HAS_SCRIPT=false
HAS_POSTINSTALL=false

if [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/Popup.pkg" ]; then
    HAS_POPUP=true
fi
if [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/install_printers.sh" ] || [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/install_printers.command" ]; then
    HAS_SCRIPT=true
fi
if [ -f "$TEMP_DIR/expanded/UMDPrinters.pkg/Scripts/postinstall" ]; then
    HAS_POSTINSTALL=true
fi

if [ "$HAS_POPUP" = true ] && [ "$HAS_SCRIPT" = true ] && [ "$HAS_POSTINSTALL" = true ]; then
    echo "✅ Package appears to be correctly built!"
    echo "   All required files are present in the Scripts directory."
    echo "   The package should install successfully."
else
    echo "❌ Package is missing required files:"
    [ "$HAS_POPUP" = false ] && echo "   - Missing Popup.pkg"
    [ "$HAS_SCRIPT" = false ] && echo "   - Missing install_printers script (.sh or .command)"
    [ "$HAS_POSTINSTALL" = false ] && echo "   - Missing postinstall script"
fi

# Clean up
rm -rf "$TEMP_DIR"

echo ""
echo "==========================================="
echo "Diagnostic complete"
echo ""
echo "To test installation, run:"
echo "  sudo installer -pkg $PKG_FILE -target /"
echo "Or double-click the package file"
echo "==========================================="