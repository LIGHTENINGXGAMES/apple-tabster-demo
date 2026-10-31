#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output=target/native-interaction/artifacts
derived=target/native-interaction/DerivedData
mkdir -p "$output"
scenario=${TABSTER_INTERACTION_SCENARIO:-boundaries}
case "$scenario" in
    boundaries) test_method=testDragBoundaries ;;
    held-drag) test_method=testHeldTabDrag ;;
    *) echo "Unknown native interaction scenario: $scenario" >&2; exit 2 ;;
esac
printf '%s\n' "$scenario" > "$output/scenario.txt"
capture_started=$(date +%s)
runtime=$(xcrun simctl list runtimes --json | python3 -c '
import json,sys
matches=[r["identifier"] for r in json.load(sys.stdin)["runtimes"]
         if "iOS-27-0" in r["identifier"] and r["isAvailable"]]
if not matches: sys.exit("No iOS 27.0 simulator runtime is installed")
print(matches[0])')
device=$(xcrun simctl create TabsterInteraction com.apple.CoreSimulator.SimDeviceType.iPhone-14 "$runtime")
video_pid=
timer_pid=
data=
cleanup() {
    local status=$?
    set +e
    if [[ -n "$timer_pid" ]]; then kill "$timer_pid" 2>/dev/null || true; fi
    if [[ -n "$video_pid" ]]; then
        kill -INT "$video_pid" 2>/dev/null || true
        wait "$video_pid" 2>/dev/null || true
    fi
    if [[ -s "$output/native-drag.mp4" ]]; then
        swift tools/native-interaction/extract-frames.swift "$output/native-drag.mp4" "$output/frames" \
            > "$output/extract-frames.log" 2>&1 || true
    fi
    if [[ -n "$data" && -d "$data/Documents/interaction" ]]; then
        cp -R "$data/Documents/interaction" "$output/"
    fi
    xcrun simctl spawn "$device" log show --last 10m --style compact \
        --predicate 'process == "Tabster" OR eventMessage CONTAINS[c] "org.lstudio.apple.Tabster"' \
        > "$output/simulator.log" 2> "$output/simulator-log-errors.log"
    python3 - "$output" "$device" "$capture_started" > "$output/crash-collection.log" 2>&1 <<'PY'
import pathlib,shutil,sys
output,device,started=pathlib.Path(sys.argv[1]),sys.argv[2],float(sys.argv[3])
roots=[pathlib.Path.home()/'Library/Logs/DiagnosticReports',
       pathlib.Path.home()/f'Library/Developer/CoreSimulator/Devices/{device}/data/Library/Logs/CrashReporter']
destination=output/'crashes'
destination.mkdir(exist_ok=True)
for index,root in enumerate(roots):
    if not root.exists(): continue
    for source in root.rglob('Tabster*'):
        if source.suffix not in ('.ips','.crash') or not source.is_file(): continue
        if source.stat().st_mtime < started-60: continue
        target=destination/f'{index}-{source.name}'
        shutil.copy2(source,target)
        print(f'{source} -> {target}')
PY
    if [[ -d "$output/NativeInteraction.xcresult" ]]; then
        xcrun xcresulttool export diagnostics --path "$output/NativeInteraction.xcresult" \
            --output-path "$output/xcresult-diagnostics" > "$output/xcresult-diagnostics.log" 2>&1
    fi
    xcrun simctl io "$device" screenshot "$output/released.png" || true
    xcrun simctl shutdown "$device" || true
    xcrun simctl delete "$device" || true
    return "$status"
}
trap cleanup EXIT
xcodebuild -version > "$output/xcode.txt"
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl install "$device" target/tabster/iphonesimulator/Tabster.app
data=$(xcrun simctl get_app_container "$device" org.lstudio.apple.Tabster data)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator \
    -dynamiclib -fobjc-arc -framework UIKit -framework QuartzCore -framework Foundation \
    tools/native-interaction/probe.m -o /tmp/tabster-interaction.dylib
codesign --force --sign - /tmp/tabster-interaction.dylib
project=tools/native-interaction/NativeInteraction.xcodeproj
xcodebuild -project "$project" -scheme NativeInteraction -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$output/build.log" 2>&1
xcodebuild -project "$project" -scheme NativeInteraction -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 75 \
    "-only-testing:NativeInteractionTests/NativeInteractionTests/$test_method" \
    -resultBundlePath "$output/NativeInteraction.xcresult" \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$output/test.log" 2>&1 &
test_pid=$!
# Wait for the injected observer in the actual app, avoiding an idle runner video.
for ((attempt=0; attempt<450; attempt++)); do
    if [[ -s "$data/Documents/interaction/interaction.jsonl" ]]; then break; fi
    if ! kill -0 "$test_pid" 2>/dev/null; then
        wait "$test_pid"
        echo 'UI test exited before the native observer started' >&2
        exit 1
    fi
    sleep 0.2
done
test -s "$data/Documents/interaction/interaction.jsonl"
xcrun simctl io "$device" recordVideo --codec=h264 "$output/native-drag.mp4" > "$output/video.log" 2>&1 &
video_pid=$!
(sleep 50; kill -INT "$video_pid" 2>/dev/null || true) &
timer_pid=$!
wait "$test_pid"
test -s "$data/Documents/interaction/interaction.jsonl"
python3 - "$data/Documents/interaction/interaction.jsonl" <<'PY'
import json,sys
events=[json.loads(line) for line in open(sys.argv[1])]
touches=[event for event in events if event['kind']=='touch']
frames=[event for event in events if event['kind']=='frame']
phases={event['phase'] for event in touches}
if not {'began','moved','ended'} <= phases or not frames:
    sys.exit('Missing real touch events or presentation frames')
print(json.dumps({'touches':len(touches),'frames':len(frames),'phases':sorted(phases)},indent=2))
PY
