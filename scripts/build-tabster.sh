#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk=${1:-iphoneos}
case "$sdk" in
    iphoneos) triple=arm64-apple-ios27.0 ;;
    iphonesimulator) triple=arm64-apple-ios27.0-simulator ;;
    *) echo "Unsupported SDK: $sdk" >&2; exit 1 ;;
esac
version=$(xcrun --sdk "$sdk" --show-sdk-version)
if [[ ${version%%.*} -lt 27 ]]; then
    echo "Tabster requires an iOS 27 SDK; found $version" >&2
    exit 1
fi
output="target/tabster/$sdk/Tabster.app"
mkdir -p "$output"
xcrun --sdk "$sdk" clang -target "$triple" \
    -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -fno-objc-arc -fno-objc-msgsend-selector-stubs -O1 -g \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -Wl,-no_fixup_chains \
    apps/tabster/main.m apps/tabster/inspection.m -o "$output/Tabster"
cp apps/tabster/Info.plist "$output/Info.plist"
codesign --force --sign - "$output"
xcrun vtool -show-build "$output/Tabster" > "target/tabster/$sdk/build-version.txt"
shasum -a 256 "$output/Tabster" > "target/tabster/$sdk/SHA256SUMS"
