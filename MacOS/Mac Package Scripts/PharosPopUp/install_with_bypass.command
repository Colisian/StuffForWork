#!/bin/bash

# UMD Printer Installer - Gatekeeper Bypass Script

clear
echo "==========================================="
echo "UMD Library Printers - Secure Installer"
echo "==========================================="
echo ""
echo "This script will install the UMD printers while bypassing"
echo "macOS Gatekeeper restrictions for university software."
echo ""

# Find the package in the same directory as this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PKG_FILE="$SCRIPT_DIR/UMD_Library_Printers_Installer.pkg"

if [ ! -f "$PKG_FILE" ]; then
    echo "❌ Error: Cannot find UMD_Library_Printers_Installer.pkg"
    echo "Please ensure the package is in the same folder as this script."
    echo ""
    echo "Press any key to exit..."
    read -n 1
    exit 1
fi

echo "📦 Found installer package"
echo ""
echo "🔐 Administrator privileges required..."
echo "You will be prompted for your password."
echo ""

# Remove quarantine from the package
echo "Removing security restrictions..."
sudo xattr -cr "$PKG_FILE" 2>/dev/null

# Install bypassing Gatekeeper
echo ""
echo "📦 Installing UMD Library Printers..."
echo "This may take a minute..."
echo ""

sudo installer -pkg "$PKG_FILE" -target / -allowUntrusted

if [ $? -eq 0 ]; then
    echo ""
    echo "==========================================="
    echo "✅ Installation Complete!"
    echo "==========================================="
    echo ""
    echo "All UMD library printers have been installed."
    echo ""
    echo "📍 Next steps:"
    echo "1. Try printing from any application (Cmd+P)"
    echo "2. Select a printer starting with 'LIB-'"
    echo "3. Enter your Directory ID when prompted"
    echo ""
    echo "⚠️  IMPORTANT: If macOS Firewall asks about 'Pharos Popup.app',"
    echo "click 'Allow' to enable printing."
    echo ""
    echo "Press any key to close this window..."
    read -n 1
else
    echo ""
    echo "==========================================="
    echo "❌ Installation Failed"
    echo "==========================================="
    echo ""
    echo "The installation could not be completed."
    echo ""
    echo "Please try:"
    echo "1. Make sure you're connected to UMD network or VPN"
    echo "2. Verify you entered your admin password correctly"
    echo "3. Contact help@umd.edu for assistance"
    echo ""
    echo "Press any key to close this window..."
    read -n 1
    exit 1
fi