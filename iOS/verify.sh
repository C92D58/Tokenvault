#!/usr/bin/env bash
#
# Builds TokenVault and runs the acceptance suite on a simulator.
#
#   ./verify.sh            # full suite
#   ./verify.sh -only-testing:TokenVaultUITests/TokenVaultUITests/testAddTokenEndsUpInTheList
#
# Notes:
#   • iCloud Drive restores files with fresh/odd timestamps, which lets the build system skip an
#     edited file — so the sources are touched before every build.
#   • The watchdog kills ONLY this run's xcodebuild PID. A `pkill -f xcodebuild` watchdog outlives
#     its own run (killing the subshell leaves the `sleep` alive) and then fires into a later run,
#     which is how result bundles end up unfinalized and corrupt.
#   • The verdict comes from the log, not from the exit code: a runner that had to be reaped can
#     still have run a green suite.
#
set -euo pipefail

DEVICE="${TV_DEVICE:-iPhone 18 Pro}"
DERIVED="${TV_DERIVED:-/tmp/tokenvault-ios-dd}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/tmp/tokenvault-ios-tests.log
RESULT=/tmp/tokenvault-ios-tests.xcresult
EXTRA=()
if [ "$#" -gt 0 ]; then EXTRA=("$@"); fi

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
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null

rm -rf "$RESULT"
echo "== build-for-testing =="
# iCloud Drive restores files with fresh/odd timestamps, which lets the build system skip an
# edited file. Touch the sources so the build always matches the disk.
find "$ROOT/TokenVault" "$ROOT/../Sources/Core" -name "*.swift" -exec touch {} +
if ! xcodebuild -project "$ROOT/TokenVault.xcodeproj" -scheme TokenVault -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" \
    build-for-testing > /tmp/tokenvault-ios-buildft.log 2>&1; then
    grep -E "error:" /tmp/tokenvault-ios-buildft.log | head -20
    echo "build failed — see /tmp/tokenvault-ios-buildft.log"
    exit 1
fi

echo "== running tests =="
: > "$LOG"
xcodebuild test-without-building -project "$ROOT/TokenVault.xcodeproj" -scheme TokenVault \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" \
    -resultBundlePath "$RESULT" ${EXTRA[@]+"${EXTRA[@]}"} > "$LOG" 2>&1 &
RUNNER=$!

# The watchdog's stdout is /dev/null so its `sleep` cannot hold the caller's pipe open: the
# subshell is killed on the happy path, but the `sleep` grandchild survives and `bash verify.sh |
# tail` then waits the full timeout for EOF.
( sleep "${TV_TEST_TIMEOUT:-1500}"; kill -TERM "$RUNNER" 2>/dev/null ) >/dev/null 2>&1 &
WATCHDOG=$!

wait "$RUNNER" || true
kill "$WATCHDOG" 2>/dev/null || true
wait "$WATCHDOG" 2>/dev/null || true

grep -E "Test Case .*(passed|failed)" "$LOG" || true

# The verdict comes from the run's own marker plus the absence of failed cases. Matching
# "Executed N tests, with 0 failures" was wrong: every suite prints that line for itself, so a
# 2-failure run still carried a passing per-suite line and the script reported ✅ PASS.
TOTAL="$(grep -E '^[[:space:]]*Executed [0-9]+ tests?' "$LOG" | tail -1 | sed 's/^[[:space:]]*//')"
if grep -q "\*\* TEST EXECUTE SUCCEEDED \*\*" "$LOG" \
    && ! grep -q "Test Case .* failed (" "$LOG"; then
    echo ""
    echo "✅ PASS — $TOTAL"
    echo "   screenshots: xcrun xcresulttool export attachments --path $RESULT --output-path /tmp/tv-shots"
    exit 0
fi

echo ""
echo "❌ FAIL — see $LOG"
echo "   ${TOTAL:-no summary line — the run did not finish}"
grep -E "error:|XCTAssert|Test Case .* failed" "$LOG" | head -20
exit 1
