#!/bin/bash
# Build script to create the combined installer package
# This script packages the printer installer script and Popup.pkg into a single .pkg/.dmg

echo "==========================================="
echo "UMD Printer Installer Package Builder"
echo "==========================================="

# Set up paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create build directory in /tmp to avoid OneDrive sync issues
BUILD_BASE="/tmp/umd_installer_build_$"
mkdir -p "$BUILD_BASE"
BUILD_DIR="$BUILD_BASE/UMD_Installer_Build"
SCRIPTS_DIR="$BUILD_DIR/scripts"
RESOURCES_DIR="$BUILD_DIR/Resources"
OUTPUT_DIR="$SCRIPT_DIR"
PKG_VERSION="2.5.0"
PKG_IDENTIFIER="edu.umd.library.printers"
PKG_NAME="UMD_Library_Printers_Installer"

# Check for required files
echo "🔍 Checking for required files..."
if [ ! -f "$SCRIPT_DIR/Popup.pkg" ]; then
    echo "❌ Error: Popup.pkg not found"
    echo "Please place Popup.pkg in: $SCRIPT_DIR"
    exit 1
fi

# Check for either .sh or .command version of the installer script
INSTALLER_SCRIPT=""
if [ -f "$SCRIPT_DIR/install_printers.sh" ]; then
    INSTALLER_SCRIPT="install_printers.sh"
elif [ -f "$SCRIPT_DIR/install_printers.command" ]; then
    INSTALLER_SCRIPT="install_printers.command"
else
    echo "❌ Error: install_printers.sh or install_printers.command not found"
    echo "Please place your printer installation script in: $SCRIPT_DIR"
    exit 1
fi

echo "✅ Found Popup.pkg"
echo "✅ Found $INSTALLER_SCRIPT"

# Clean and create build directories
echo ""
echo "📁 Setting up build directories..."
rm -rf "$BUILD_BASE" 2>/dev/null || true
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$RESOURCES_DIR"

# Also create a temporary payload directory for pkgbuild
PAYLOAD_DIR="${BUILD_DIR}/payload"
mkdir -p "$PAYLOAD_DIR"
# Create a dummy file so the payload directory isn't empty
touch "$PAYLOAD_DIR/.placeholder"

# Copy Popup.pkg to Resources
echo "📦 Copying Popup.pkg to Resources..."
cp "$SCRIPT_DIR/Popup.pkg" "$RESOURCES_DIR/"

# Copy the printer installation script to Resources
echo "📦 Copying printer installation script to Resources..."
cp "$SCRIPT_DIR/$INSTALLER_SCRIPT" "$RESOURCES_DIR/install_printers.sh"

# Create the postinstall script that will run during package installation
echo "📝 Creating postinstall script..."
cat > "$SCRIPTS_DIR/postinstall" << 'POSTINSTALL_SCRIPT'
#!/bin/bash
# This script runs during package installation
# Files are in the same directory as this script

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="/var/log/umd_printer_install.log"
TEMP_DIR="/tmp/umd_printer_install_$"

echo "UMD Printer Installation Started: $(date)" >> "$LOG_FILE"
echo "Script directory: $SCRIPT_DIR" >> "$LOG_FILE"

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Copy installer files from script directory to temp directory
echo "Copying installation files..." >> "$LOG_FILE"
if [ -f "$SCRIPT_DIR/Popup.pkg" ]; then
    cp "$SCRIPT_DIR/Popup.pkg" "$TEMP_DIR/" 2>> "$LOG_FILE"
    echo "Copied Popup.pkg" >> "$LOG_FILE"
else
    echo "ERROR: Popup.pkg not found in $SCRIPT_DIR" >> "$LOG_FILE"
fi

if [ -f "$SCRIPT_DIR/install_printers.sh" ]; then
    cp "$SCRIPT_DIR/install_printers.sh" "$TEMP_DIR/" 2>> "$LOG_FILE"
    chmod +x "$TEMP_DIR/install_printers.sh"
    echo "Copied install_printers.sh" >> "$LOG_FILE"
else
    echo "ERROR: install_printers.sh not found in $SCRIPT_DIR" >> "$LOG_FILE"
fi

# Change to temp directory and run the installer
cd "$TEMP_DIR"

# List files for debugging
echo "Files in temp directory:" >> "$LOG_FILE"
ls -la >> "$LOG_FILE"

# Run the printer installation script if it exists
if [ -f "./install_printers.sh" ]; then
    echo "Running printer installation script..." >> "$LOG_FILE"
    ./install_printers.sh >> "$LOG_FILE" 2>&1
    RESULT=$?
else
    echo "ERROR: install_printers.sh not found in temp directory" >> "$LOG_FILE"
    RESULT=1
fi

# Clean up
rm -rf "$TEMP_DIR"

echo "UMD Printer Installation Completed: $(date)" >> "$LOG_FILE"
echo "Exit code: $RESULT" >> "$LOG_FILE"

exit $RESULT
POSTINSTALL_SCRIPT

# Make postinstall executable
chmod +x "$SCRIPTS_DIR/postinstall"

# Create welcome message
echo "📝 Creating welcome message..."
cat > "$RESOURCES_DIR/welcome.html" << 'WELCOME_HTML'
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }
        h2 { color: #333; }
        ul { line-height: 1.6; }
        .warning { color: #d00; font-weight: bold; }
    </style>
</head>
<body>
    <h2>UMD Library Printers Installer</h2>
    <p>This installer will set up all UMD library printers on your Mac.</p>
    
    <p><strong>What will be installed:</strong></p>
    <ul>
        <li>Pharos Popup printing client</li>
        <li>All UMD library printers (17 printers total)</li>
        <li>Required printer drivers</li>
    </ul>
    
    <p><strong>Libraries included:</strong></p>
    <ul>
        <li>McKeldin Library</li>
        <li>Architecture Library</li>
        <li>Art Library</li>
        <li>Engineering & Physical Sciences Library (EPSL)</li>
        <li>Hornbake Library</li>
        <li>Performing Arts Library (PAL)</li>
        <li>Maryland Room</li>
    </ul>
    
    <p class="warning">Note: Administrator password required for installation.</p>
</body>
</html>
WELCOME_HTML

# Create conclusion message
cat > "$RESOURCES_DIR/conclusion.html" << 'CONCLUSION_HTML'
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; }
        h2 { color: #2d7d2d; }
        ul { line-height: 1.6; }
        .next { background: #f0f0f0; padding: 15px; border-radius: 5px; margin-top: 20px; }
        .support { color: #666; margin-top: 20px; }
        code { background: #f5f5f5; padding: 2px 4px; border-radius: 3px; }
    </style>
</head>
<body>
    <h2>✅ Installation Complete!</h2>
    <p>UMD library printers have been successfully installed on your Mac.</p>
    
    <div class="next">
        <p><strong>How to print:</strong></p>
        <ol>
            <li>Open any document and press <code>⌘P</code> (Cmd+P)</li>
            <li>Select a UMD printer from the dropdown
                <ul>
                    <li>Names start with "LIB-"</li>
                    <li>BW = Black & White, Color = Color printing</li>
                </ul>
            </li>
            <li>Click Print</li>
            <li>Enter your Directory ID and password when prompted</li>
            <li>Go to any library print release station to get your printout</li>
        </ol>
    </div>
    
    <p><strong>Installation log saved to:</strong><br>
    <code>/var/log/umd_printer_install.log</code></p>
    
    <p class="support">
        <strong>Need help?</strong><br>
        Contact UMD IT Service Desk<br>
        Email: help@umd.edu<br>
        Phone: 301-405-1500
    </p>
</body>
</html>
CONCLUSION_HTML

# Create Distribution file
echo "📝 Creating distribution configuration..."
cat > "$BUILD_DIR/distribution.xml" << 'DISTRIBUTION_XML'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2.0">
    <title>UMD Library Printers</title>
    <organization>edu.umd</organization>
    <welcome file="welcome.html"/>
    <conclusion file="conclusion.html"/>
    
    <pkg-ref id="edu.umd.library.printers">
        <bundle-version/>
    </pkg-ref>
    
    <options customize="never" require-scripts="true" hostArchitectures="x86_64,arm64"/>
    <domains enable_localSystem="true"/>
    
    <choices-outline>
        <line choice="default">
            <line choice="edu.umd.library.printers"/>
        </line>
    </choices-outline>
    
    <choice id="default"/>
    <choice id="edu.umd.library.printers" visible="false">
        <pkg-ref id="edu.umd.library.printers"/>
    </choice>
    
    <pkg-ref id="edu.umd.library.printers" version="2.5.0" onConclusion="none">UMDPrinters.pkg</pkg-ref>
</installer-gui-script>
DISTRIBUTION_XML

# Build the component package WITH resources embedded
echo ""
echo "📦 Building component package..."

# First, we need to create a proper package with resources
# Copy resources into the Scripts folder where they'll be accessible
cp "$RESOURCES_DIR/Popup.pkg" "$SCRIPTS_DIR/" 2>/dev/null || echo "Warning: Could not copy Popup.pkg"
cp "$RESOURCES_DIR/install_printers.sh" "$SCRIPTS_DIR/" 2>/dev/null || echo "Warning: Could not copy install script"

pkgbuild \
    --root "$PAYLOAD_DIR" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$PKG_VERSION" \
    --scripts "$SCRIPTS_DIR" \
    --install-location /tmp \
    "$BUILD_DIR/UMDPrinters.pkg"

if [ $? -ne 0 ]; then
    echo "❌ Failed to build component package"
    exit 1
fi

# Build the final product archive
echo "📦 Building final installer package..."
productbuild \
    --distribution "$BUILD_DIR/distribution.xml" \
    --resources "$RESOURCES_DIR" \
    --package-path "$BUILD_DIR" \
<<<<<<< HEAD
    "$OUTPUT_DIR/${PKG_NAME}.pkg"
=======
    "$OUTPUT_DIR/${PKG_NAME}_unsigned.pkg"
>>>>>>> c371f76349bc9ad6424e3222d56c75e8fac05992

if [ $? -ne 0 ]; then
    echo "❌ Failed to build product package"
    exit 1
fi

<<<<<<< HEAD
=======
echo "📦 Package ready for signing and notarization..."
mv "$OUTPUT_DIR/${PKG_NAME}_unsigned.pkg" "$OUTPUT_DIR/${PKG_NAME}.pkg"
echo "✅ Package built: ${PKG_NAME}.pkg (unsigned, ready for notarization)"

>>>>>>> c371f76349bc9ad6424e3222d56c75e8fac05992
echo "✅ Package built: ${PKG_NAME}.pkg"

# Create DMG
echo ""
echo "💿 Creating DMG installer..."
DMG_NAME="${PKG_NAME}.dmg"
DMG_TEMP="${PKG_NAME}_temp.dmg"
DMG_FINAL="$OUTPUT_DIR/$DMG_NAME"

# Create a temporary directory for DMG contents
DMG_DIR="$SCRIPT_DIR/DMG_Contents"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy the installer package
cp "$OUTPUT_DIR/${PKG_NAME}.pkg" "$DMG_DIR/"

<<<<<<< HEAD
# Create a simple README
cat > "$DMG_DIR/How to Install.txt" << 'README_TXT'
UMD Library Printers - Installation Instructions
================================================

INSTALLATION:
1. Double-click "UMD_Library_Printers_Installer.pkg"
2. Follow the on-screen instructions
3. Enter your Mac administrator password when prompted
4. Installation will complete automatically

AFTER INSTALLATION:
• All UMD library printers will appear in your print dialog (Cmd+P)
• Printer names start with "LIB-" (e.g., LIB-McKMobileBW)
• You'll authenticate with your Directory ID when printing

PRINTING STEPS:
1. Press Cmd+P in any application
2. Select a UMD printer from the dropdown
3. Click Print
4. Enter your Directory ID and password
5. Go to any library print station to release your job
=======

# Copy the README.md if it exists
if [ -f "$SCRIPT_DIR/README.md" ]; then
    cp "$SCRIPT_DIR/README.md" "$DMG_DIR/"
    echo "✅ Added README.md to DMG"
else
    echo "⚠️  README.md not found, creating basic instructions..."
    # Create a basic README if none exists
    cat > "$DMG_DIR/README.txt" << 'README_TXT'
UMD Library Printers - Installation Instructions
================================================

⚠️ GETTING SECURITY WARNINGS?
-----------------------------
If macOS blocks the installer, use "Install_with_Bypass.command" instead:
1. Double-click "Install_with_Bypass.command"
2. Enter your administrator password
3. Installation will proceed without Gatekeeper blocks

STANDARD INSTALLATION:
1. Double-click "UMD_Library_Printers_Installer.pkg"
2. Follow the on-screen instructions
3. Enter your Mac administrator password when prompted

IMPORTANT - FIREWALL CONFIGURATION:
If prompted about allowing "Pharos Popup.app" to accept incoming connections, click "Allow"
>>>>>>> c371f76349bc9ad6424e3222d56c75e8fac05992

SUPPORT:
Email: help@umd.edu
Phone: 301-405-1500
<<<<<<< HEAD
Web: it.umd.edu

================================================
README_TXT
=======

================================================
README_TXT
fi
>>>>>>> c371f76349bc9ad6424e3222d56c75e8fac05992

# Create the DMG
echo "Building DMG file..."
hdiutil create -volname "UMD Library Printers" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_FINAL"

if [ $? -eq 0 ]; then
    echo "✅ DMG created: $DMG_NAME"
else
    echo "⚠️  DMG creation failed, but PKG is still available"
fi

# Clean up
echo ""
echo "🧹 Cleaning up build files..."
rm -rf "$BUILD_BASE"
rm -rf "$DMG_DIR"

# Final summary
echo ""
echo "==========================================="
echo "✅ Build Complete!"
echo "==========================================="
echo ""
echo "📦 Created files:"
ls -lh "$OUTPUT_DIR/${PKG_NAME}.pkg" 2>/dev/null && echo "   • ${PKG_NAME}.pkg"
<<<<<<< HEAD
ls -lh "$OUTPUT_DIR/${PKG_NAME}.dmg" 2>/dev/null && echo "   • ${PKG_NAME}.dmg (recommended for distribution)"
echo ""
echo "📋 Required files for this build script:"
echo "   • install_printers.sh (your printer installation script)"
echo "   • Popup.pkg (Pharos client installer)"
echo "   • This build script"
echo ""
echo "📚 To distribute to students:"
echo "   1. Upload the .dmg file to a web server"
echo "   2. Share the download link with students"
echo "   3. Students just double-click to install"
=======
ls -lh "$OUTPUT_DIR/Install_with_Bypass.command" 2>/dev/null && echo "   • Install_with_Bypass.command"
ls -lh "$OUTPUT_DIR/${PKG_NAME}.dmg" 2>/dev/null && echo "   • ${PKG_NAME}.dmg (recommended for distribution)"
echo ""
echo "📋 DMG Contents:"
echo "The DMG should contain:"
echo "   • ${PKG_NAME}.pkg"
echo "   • Install_with_Bypass.command"
echo "   • README.md (if present)"
echo ""
echo "To verify DMG contents, run:"
echo "   hdiutil attach '${PKG_NAME}.dmg' && ls '/Volumes/UMD Library Printers/'"
echo ""
echo "📚 To distribute to students:"
echo "   1. Upload the .dmg file to a web server"
echo "   2. Tell students to use Install_with_Bypass.command if they get security warnings"
echo "   3. Students just double-click Install_with_Bypass.command to install"
>>>>>>> c371f76349bc9ad6424e3222d56c75e8fac05992
echo ""
echo "==========================================="