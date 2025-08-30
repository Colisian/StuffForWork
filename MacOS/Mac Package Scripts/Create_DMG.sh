#!/bin/bash
set -e

APP_NAME="Pharos Mobile Print Client"
DMG_NAME="Pharos-Mobile-Print-Installer.dmg"
SOURCE_FOLDER="./pharos_source"
VOLUME_NAME="Pharos Mobile Print"
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