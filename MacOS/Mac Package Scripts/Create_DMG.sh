#!/bin/bash
set -e

APP_NAME="Libraries Mobile Print Client"
DMG_NAME="Libraries-Mobile-Print-Installer.dmg"
SOURCE_FOLDER="./Users/cmcleod1/Library/CloudStorage/OneDrive-UniversityofMaryland/Documents/Work/StuffForWork/MacOS/Mac Package Scripts/PharosPopUp"
VOLUME_NAME="Libraries Mobile Print"
BACKGROUND="background.png"  # optional
VOL_ICON="VolumeIcon.icns"   # optional

echo "Building DMG for $APP_NAME..."

create-dmg \
  --volname "$VOLUME_NAME" \
  --background "$BACKGROUND" \
  --volicon "$VOL_ICON" \
  --app-drop-link 450 185 \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "$(basename "$SOURCE_FOLDER")" 100 185 \
  --format UDZO \
  --filesystem APFS \
  "$DMG_NAME" "$SOURCE_FOLDER"

echo "DMG created: $DMG_NAME"