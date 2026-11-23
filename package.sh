#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP=".build/TokenVault.app"
# Version comes from project.yml (single source of truth), TV_VERSION overrides.
VERSION="${TV_VERSION:-$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\(.*\)".*/\1/p' project.yml | head -1)}"
DMG_NAME="TokenVault-${VERSION:-1.0}"
DMG_FILE=".build/${DMG_NAME}.dmg"
STAGING=".build/dmg_staging"

echo "📦 Packaging TokenVault for distribution..."

# Clean up previous
rm -rf "$STAGING" "$DMG_FILE"

# Ensure no old mount
hdiutil detach /Volumes/TokenVault 2>/dev/null || true
sleep 1

# Create staging directory
mkdir -p "$STAGING"

# Copy the signed app
cp -R "$APP" "$STAGING/"

# Create Applications symlink (for drag-to-install)
ln -s /Applications "$STAGING/Applications"

# Create DMG directly using diskutil (modern, non-deprecated)
echo "💿 Creating DMG..."
diskutil image create from "$STAGING" \
    --volumeName "TokenVault" \
    --format UDZO \
    "$DMG_FILE" \
    > /dev/null

# Configure layout (mount, arrange icons, unmount)
echo "🎨 Configuring DMG layout..."
MOUNT_POINT=$(hdiutil attach "$DMG_FILE" -nobrowse -noautoopen 2>&1 | awk '/\/Volumes\/TokenVault/ {print $NF}')
if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    osascript -e "
    tell application \"Finder\"
        tell disk \"TokenVault\"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {400, 200, 900, 540}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 96
            set position of item \"TokenVault.app\" to {140, 160}
            set position of item \"Applications\" to {360, 160}
            close
        end tell
    end tell" 2>/dev/null || true
    sleep 2
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    echo "   Layout configured."
fi

# Sign the DMG
echo "🔏 Signing DMG..."
codesign --sign - "$DMG_FILE" 2>/dev/null || true

# Clean up staging
rm -rf "$STAGING"

# Show result
SIZE=$(du -h "$DMG_FILE" | cut -f1)
echo ""
echo "✅ DMG created: ${DMG_FILE}"
echo "   Size: ${SIZE}"
echo ""
echo "📋 To install:"
echo "   open ${DMG_FILE}"
echo "   Drag TokenVault.app → Applications"
echo ""
