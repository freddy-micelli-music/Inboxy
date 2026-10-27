#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${AERIS_BUILD_DIR:-$project_dir/build}"
mkdir -p "$build_dir/Inboxy.app/Contents/MacOS" "$build_dir/Inboxy.app/Contents/Resources" "$build_dir/ModuleCache"
cp "$project_dir/Info.plist" "$build_dir/Inboxy.app/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$build_dir/ModuleCache" "$project_dir"/Sources/Aeris/*.swift -o "$build_dir/Inboxy.app/Contents/MacOS/Inboxy"
if [ -f "$project_dir/Resources/AppIcon.icns" ]; then cp "$project_dir/Resources/AppIcon.icns" "$build_dir/Inboxy.app/Contents/Resources/"; fi
codesign --force --sign - "$build_dir/Inboxy.app"
echo "Application créée : $build_dir/Inboxy.app"

sh "$project_dir/package.sh" "$build_dir/Inboxy.app" "$build_dir/Distribution"
