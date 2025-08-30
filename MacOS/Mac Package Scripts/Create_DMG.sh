#!/bin/bash
# Script to create a DMG file for Pharos Mac client distribution

# Variables - Customize these for your environment
APP_NAME="Pharos Mobile Print Client"
DMG_NAME="Pharos-Mobile-Print-Installer"
SOURCE_FOLDER="./pharos_source"  # Folder containing your .app or .pkg
VOLUME_NAME="Pharos Mobile Print"
DMG_SIZE="100m"  # Adjust size as needed

echo "Creating DMG for $APP_NAME..."

# Step 1: Create a temporary directory
TEMP_DIR=$(mktemp -d)
echo "Working in temporary directory: $TEMP_DIR"

# Step 2: Copy source files to temp directory
cp -R "$SOURCE_FOLDER"/* "$TEMP_DIR/"

# Step 3: Create initial DMG
echo "Creating initial DMG..."
hdiutil create -srcfolder "$TEMP_DIR" -volname "$VOLUME_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size "$DMG_SIZE" "$DMG_NAME.temp.dmg"

# Step 4: Mount the DMG
echo "Mounting DMG for customization..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_NAME.temp.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

# Step 5: Customize the DMG (optional)
# Create Applications symlink for easy installation
ln -s /Applications "$MOUNT_POINT/Applications"

# Add custom background image (if you have one)
# mkdir "$MOUNT_POINT/.background"
# cp background.png "$MOUNT_POINT/.background/"

# Create custom .DS_Store for layout (optional)
# This would require AppleScript or other tools

# Step 6: Set permissions
chmod -Rf go-w "$MOUNT_POINT"

# Step 7: Sync and unmount
sync
hdiutil detach "$DEVICE"

# Step 8: Convert to compressed, read-only DMG
echo "Creating final compressed DMG..."
hdiutil convert "$DMG_NAME.temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME.dmg"

# Step 9: Clean up
rm -f "$DMG_NAME.temp.dmg"
rm -rf "$TEMP_DIR"

echo "DMG created successfully: $DMG_NAME.dmg"

# Step 10: Verify the DMG
echo "Verifying DMG..."
hdiutil verify "$DMG_NAME.dmg"

echo "Process complete!"