#!/usr/bin/env bash
#
# Builds TokenVault for the iOS Simulator, installs it, and launches it.
#
#   ./build.sh                     # iPhone 18 Pro, seeded demo vault
#   TV_DEVICE="iPad Pro 11-inch (M5)" ./build.sh
#   ./build.sh --clean             # wipe the vault first
#
# Two facts of life:
#   • The project lives in iCloud Drive, so derived data MUST live outside it —
#     CodeSign fails with "resource fork, Finder information …" otherwise.
#   • The app icon is generated, never hand-edited: scripts/make-icon.swift.
#
set -euo pipefail

DEVICE="${TV_DEVICE:-iPhone 18 Pro}"
DERIVED="${TV_DERIVED:-/tmp/tokenvault-ios-dd}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="dev.wahsun.tokenvault"
LAUNCH_ARGS=()

if [ "${1:-}" = "--clean" ]; then
    LAUNCH_ARGS+=(-uiTestReset)
fi

UDID="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
name = sys.argv[1]
for runtime in sorted(devices, reverse=True):
    for d in devices[runtime]:
        if d['name'] == name:
            print(d['udid']); raise SystemExit
raise SystemExit('no simulator named ' + name)
" "$DEVICE")"

echo "== device: $DEVICE ($UDID) =="

echo "== generating app icon =="
swift "$ROOT/../scripts/make-icon.swift" ios \
    "$ROOT/TokenVault/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" > /dev/null
# The About card renders the same artwork from AppMark.imageset (512 px). Regenerating only the
# home-screen icon left the About card showing a palette two revisions old.
swift "$ROOT/../scripts/make-icon.swift" ios /tmp/tv-appmark-1024.png > /dev/null
sips -z 512 512 /tmp/tv-appmark-1024.png \
    --out "$ROOT/TokenVault/Resources/Assets.xcassets/AppMark.imageset/AppMark.png" > /dev/null

# iCloud Drive restores files with fresh/odd timestamps, which makes the build system believe
# an edited file is already compiled. Touching the sources forces the rebuild to match the disk.
find "$ROOT/TokenVault" "$ROOT/../Sources/Core" -name "*.swift" -exec touch {} +

echo "== building =="
if ! xcodebuild -project "$ROOT/TokenVault.xcodeproj" -scheme TokenVault \
    -sdk iphonesimulator -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" build CODE_SIGNING_ALLOWED=NO > /tmp/tokenvault-ios-build.log 2>&1; then
    grep -E "error:" /tmp/tokenvault-ios-build.log | head -20
    echo "build failed — full log at /tmp/tokenvault-ios-build.log"
    exit 1
fi
grep -E "warning:" /tmp/tokenvault-ios-build.log | grep -v "AppIntents" | head -8 || true

APP="$DERIVED/Build/Products/Debug-iphonesimulator/TokenVault.app"

echo "== booting =="
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null

echo "== installing =="
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

echo "== launching =="
if [ "${#LAUNCH_ARGS[@]}" -gt 0 ]; then
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}"
else
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
fi

echo ""
echo "✅ installed on $DEVICE"
echo "   screenshot:  xcrun simctl io $UDID screenshot /tmp/tokenvault.png"
echo "   seeded demo: xcrun simctl launch $UDID $BUNDLE_ID -uiTestReset -uiTestUnlocked -uiTestSeed"
