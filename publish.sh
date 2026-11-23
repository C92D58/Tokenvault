#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP="TokenVault"
BUILD=".build"
BUNDLE="$BUILD/$APP.app"
RES="Resources"

echo "🚀 TokenVault Release & Notarization Pipeline"
echo "--------------------------------------------------"

# 1. Check for Developer ID Application certificate
SIGN_IDENTITY=""
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
    echo "✅ Found Developer ID Certificate: $SIGN_IDENTITY"
else
    echo "⚠️  No 'Developer ID Application' certificate found in Keychain."
    echo "   Falling back to ad-hoc signing (-) for local testing."
    SIGN_IDENTITY="-"
fi

# 2. Build and sign app
echo "🔨 Compiling and signing $APP..."
bash scripts/build-macos.sh

if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "🔏 Re-signing with Developer ID: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" \
      --options runtime \
      --entitlements "$RES/TokenVault.entitlements" \
      --timestamp \
      "$BUNDLE"
      
    echo "🔍 Verifying signature..."
    codesign -dvvv --entitlements - "$BUNDLE"
    spctl -a -t exec -vv "$BUNDLE" || echo "⚠️ Gatekeeper assessment failed (expected if not notarized yet)"
fi

# 3. Package into DMG
./package.sh

# 4. Optional Notarization (if Apple ID credentials configured)
if [ "$SIGN_IDENTITY" != "-" ] && [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    VERSION="${TV_VERSION:-$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\(.*\)".*/\1/p' project.yml | head -1)}"
    DMG_FILE="$BUILD/TokenVault-${VERSION:-1.0}.dmg"
    echo "📦 Submitting DMG for Apple Notarization..."
    xcrun notarytool submit "$DMG_FILE" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "${APPLE_APP_SPECIFIC_PASSWORD:-}" \
      --wait
      
    echo " staple Notarization ticket..."
    xcrun stapler staple "$BUNDLE"
    xcrun stapler staple "$DMG_FILE"
    echo "✨ Notarization completed successfully!"
else
    echo ""
    echo "ℹ️  To notarize automatically, set environment variables:"
    echo "   export APPLE_ID='your@email.com'"
    echo "   export APPLE_TEAM_ID='YOUR_TEAM_ID'"
    echo "   export APPLE_APP_SPECIFIC_PASSWORD='abcd-efgh-ijkl-mnop'"
    echo ""
fi

echo "🎉 TokenVault release pipeline finished!"
