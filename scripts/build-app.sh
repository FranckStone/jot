#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
configuration="${1:-release}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
deployment_target="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$project_dir/Resources/Info.plist")"
# Explicit SDK selection lets AppKit opt into the current system design while
# Package.swift continues to specify the oldest supported macOS deployment target.
xcrun swift build --sdk "$sdk_path" -c "$configuration" --scratch-path "$project_dir/.build" \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$deployment_target" -Xlinker "$sdk_version"
bin_dir="$(xcrun swift build --sdk "$sdk_path" -c "$configuration" --scratch-path "$project_dir/.build" --show-bin-path)"
bundle_dir="$project_dir/dist/Jot.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$bin_dir/Jot" "$bundle_dir/Contents/MacOS/Jot"
# Catch a build-engine regression that stamps the deployment target as the SDK.
linked_sdk="$(xcrun vtool -show-build "$bundle_dir/Contents/MacOS/Jot" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$linked_sdk" != "$sdk_version" ]]; then
    printf 'SDK mismatch: built with %s, expected %s\n' "$linked_sdk" "$sdk_version" >&2
    exit 1
fi
cp "$project_dir/Resources/Info.plist" "$bundle_dir/Contents/Info.plist"
# A content-specific filename invalidates macOS's cached bundle icon on asset changes.
icon_hash="$(shasum -a 256 "$project_dir/Resources/AppIcon.icns" | cut -c 1-12)"
icon_name="AppIcon-$icon_hash"
cp "$project_dir/Resources/AppIcon.icns" "$bundle_dir/Contents/Resources/$icon_name.icns"
cp "$project_dir/Resources/AppIcon.icns.json" "$bundle_dir/Contents/Resources/$icon_name.icns.json"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $icon_name" "$bundle_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$sdk_version" "$bundle_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTPlatformName string macosx" "$bundle_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTPlatformVersion string $sdk_version" "$bundle_dir/Contents/Info.plist"
codesign --force --sign - "$bundle_dir"
printf 'Built %s\n' "$bundle_dir"
