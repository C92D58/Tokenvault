#!/bin/bash
#
# Builds an iOS project for a connected iPhone and installs it.
#
#   ./scripts/install-device.sh                       # TokenVault, this repo
#   ./scripts/install-device.sh /path/to/X.xcodeproj X
#
# Why two install paths: on this Mac `devicectl` (CoreDevice) can fail with
# "The tunnel connection failed … RemotePairingError error 4" while usbmuxd still sees the phone
# and reports a valid pairing. So installation goes through libimobiledevice (`ideviceinstaller`)
# first — packing the .app into an .ipa — and falls back to devicectl.
#
# Signing requires two things on this machine, both learned the hard way:
#   • The signing certificate must have DEFAULT trust settings. A custom trust entry on the leaf
#     makes xcodebuild refuse with "Invalid trust settings. Restore system default trust settings".
#     Check:  security dump-trust-settings | grep -E '^Cert'
#     Clear:  security find-certificate -c "<cert name>" -p login.keychain-db > /tmp/leaf.pem
#             security remove-trusted-cert /tmp/leaf.pem
#   • The team must be the one signed into Xcode; it is read from Xcode's preferences below.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${1:-$ROOT/TokenVault.xcodeproj}"
SCHEME="${2:-TokenVault}"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-/tmp/dd-$SCHEME}"
BUNDLE_ID="${BUNDLE_ID:-}"

TEAM="${TV_TEAM:-}"
if [ -z "$TEAM" ]; then
    TEAM="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
        | grep -o 'teamID = [A-Z0-9]\{10\}' | head -1 | awk '{print $3}')" || true
fi
TEAM="${TEAM:-MAA6W8AG5P}"

UDID="${TV_DEVICE_ID:-$(idevice_id -l 2>/dev/null | head -1)}"

echo "== project $PROJECT ($SCHEME, team $TEAM) =="
echo "== device  ${UDID:-none} =="

echo "== building for the device =="
# Icons are generated, never hand-edited. The device path used to skip this, so a build could ship
# whatever artwork happened to be on disk — regenerate both the icon and the in-app About mark.
swift "$ROOT/../scripts/make-icon.swift" ios \
    "$ROOT/TokenVault/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" > /dev/null
swift "$ROOT/../scripts/make-icon.swift" ios /tmp/tv-appmark-1024.png > /dev/null
sips -z 512 512 /tmp/tv-appmark-1024.png \
    --out "$ROOT/TokenVault/Resources/Assets.xcassets/AppMark.imageset/AppMark.png" > /dev/null
# iCloud Drive restores files with fresh/odd timestamps, which can make the build system skip an
# edited file; touch sources so the build always matches the disk.
find "$ROOT/TokenVault" "$ROOT/../Sources/Core" -name "*.swift" -exec touch {} + 2>/dev/null || true
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
    build > "/tmp/build-$SCHEME.log" 2>&1; then
    grep -E "error:" "/tmp/build-$SCHEME.log" | head -10
    echo "build failed — full log /tmp/build-$SCHEME.log"
    exit 1
fi

APP="$(find "$DERIVED/Build/Products/$CONFIG-iphoneos" -maxdepth 1 -name '*.app' | head -1)"
[ -d "$APP" ] || { echo "no .app produced"; exit 1; }
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
echo "== app $APP ($BUNDLE_ID) =="
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier" | sed 's/^/   /'

if [ -z "$UDID" ]; then
    echo "no iPhone visible (idevice_id). Plug it in, unlock it, keep the screen on."
    exit 2
fi

echo "== installing via usbmuxd =="
WORK="/tmp/ipa-$SCHEME"
rm -rf "$WORK"; mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
( cd "$WORK" && zip -qry "/tmp/$SCHEME.ipa" Payload ) || { echo "ipa packing failed"; exit 1; }
if ideviceinstaller -u "$UDID" install "/tmp/$SCHEME.ipa" 2>&1 | tail -1 | grep -q Complete; then
    echo "✅ installed $BUNDLE_ID"
    echo "   launch: xcrun devicectl device process launch --device $UDID $BUNDLE_ID"
    exit 0
fi

echo "== usbmuxd install failed, trying devicectl =="
if xcrun devicectl device install app --device "$UDID" "$APP"; then
    echo "✅ installed $BUNDLE_ID"
else
    echo "❌ both install paths failed — see the tool output above"
    exit 1
fi
