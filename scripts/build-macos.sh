#!/bin/bash
#
# Builds the macOS app straight from Sources/ with swiftc — no Xcode project, no xcodebuild.
#
# The one thing this script must never forget: `Resources/Info.plist` ships
# `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`, which only Xcode substitutes. Copying that
# file verbatim into the bundle put the raw placeholders on screen — the About panel read
# "版本 $(MARKETING_VERSION) ($(CURRENT_PROJECT_VERSION))" in every local build. The placeholders are
# stamped below and the script fails if any survive.
#
#   scripts/build-macos.sh            # → .build/TokenVault.app
#   TV_VERSION=1.2 TV_BUILD=42 …      # override the numbers
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="TokenVault"
BUILD=".build"
BUNDLE="$BUILD/$APP.app"
SRC="Sources"
ASSETS="Assets.xcassets"
RES="Resources"

killall "$APP" 2>/dev/null || true

rm -rf "$BUILD" /tmp/tv_build /tmp/tv_sign
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" /tmp/tv_build

SDK=$(xcrun --show-sdk-path --sdk macosx)

echo "🔨 Compiling..."
# shellcheck disable=SC2046
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI -framework AppKit -framework Combine \
  -framework CryptoKit -framework LocalAuthentication \
  -framework Security -framework Carbon \
  -O \
  -o "$BUNDLE/Contents/MacOS/$APP" \
  $(find "$SRC" -name "*.swift" | sort)

echo "🎨 Assets..."
actool "$ASSETS" --compile "$BUNDLE/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist /tmp/tv_build/partial.plist 2>&1 | tail -1

cp "$RES/Info.plist" "$BUNDLE/Contents/Info.plist"

# project.yml is the single source of truth for the marketing version; the build number is the
# commit count, which is monotonic and needs no file to maintain.
VERSION="${TV_VERSION:-$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\(.*\)".*/\1/p' project.yml | head -1)}"
BUILD_NO="${TV_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION:-1.0}" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NO:-1}" "$BUNDLE/Contents/Info.plist"

if plutil -p "$BUNDLE/Contents/Info.plist" | grep -q '\$('; then
  echo "❌ Info.plist still contains an unsubstituted build setting:"
  plutil -p "$BUNDLE/Contents/Info.plist" | grep '\$('
  exit 1
fi
echo "🔖 Version ${VERSION:-1.0} (${BUILD_NO:-1})"

# Privacy manifest — App Store Connect rejects uploads (ITMS-91053) without it.
if [ -f "$RES/PrivacyInfo.xcprivacy" ]; then
  cp "$RES/PrivacyInfo.xcprivacy" "$BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
fi

# Localizations (en + zh-Hant). Same files the iOS target compiles from Sources/Core/Resources.
for lproj in Sources/Core/Resources/*.lproj; do
  [ -d "$lproj" ] || continue
  cp -R "$lproj" "$BUNDLE/Contents/Resources/"
done

# Embed provisioning profile if exists
if [ -f "$RES/embedded.provisionprofile" ]; then
  cp "$RES/embedded.provisionprofile" "$BUNDLE/Contents/embedded.provisionprofile"
fi

echo "🔏 Signing (Hardened Runtime)..."
mkdir -p "/tmp/tv_sign/$APP.app/Contents"
cp -R "$BUNDLE/Contents" "/tmp/tv_sign/$APP.app/"

# An ad-hoc signature may not carry com.apple.developer.* entitlements — AMFI kills the process
# at launch ("Killed: 9"). Keep the real file for App Store/notarized signing, sign the local
# build with a copy that has the iCloud keys stripped, so iCloud reports itself unavailable
# instead of taking the whole app down.
LOCAL_ENTITLEMENTS=/tmp/tv_local.entitlements
cp "$RES/TokenVault.entitlements" "$LOCAL_ENTITLEMENTS"
for key in com.apple.developer.icloud-container-identifiers \
           com.apple.developer.icloud-services \
           com.apple.developer.ubiquity-kvstore-identifier; do
  /usr/libexec/PlistBuddy -c "Delete :$key" "$LOCAL_ENTITLEMENTS" >/dev/null 2>&1 || true
done

codesign --force --deep --sign - \
  --options runtime \
  --entitlements "$LOCAL_ENTITLEMENTS" \
  --timestamp \
  "/tmp/tv_sign/$APP.app"

rm -rf "$BUNDLE"
mv "/tmp/tv_sign/$APP.app" "$BUNDLE"

echo ""
echo "✅ $BUNDLE"
echo ""
echo "   🏪 App Store 驗證："
echo "   codesign -dvvv --entitlements - \"$BUNDLE\""
echo "   spctl -a -t exec -vv \"$BUNDLE\""
