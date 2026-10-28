#!/bin/sh
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
framework="$project_dir/Libraries/Sparkle.framework"
if [ -d "$framework" ]; then
    version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$framework/Resources/Info.plist")"
    [ "$version" = '2.10.0' ] || { echo "Sparkle 2.10.0 attendu." >&2; exit 1; }
    codesign --verify --deep --strict "$framework"
    exit 0
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/inboxy-sparkle.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT HUP INT TERM
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 180 \
    https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$stage/Sparkle.tar.xz"
actual="$(shasum -a 256 "$stage/Sparkle.tar.xz" | awk '{print $1}')"
[ "$actual" = 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c' ] || { echo "Empreinte Sparkle incorrecte." >&2; exit 1; }
tar -xJf "$stage/Sparkle.tar.xz" -C "$stage"
codesign --verify --deep --strict "$stage/Sparkle.framework"
mkdir -p "$project_dir/Libraries"
ditto "$stage/Sparkle.framework" "$framework"
cp "$stage/LICENSE" "$project_dir/Libraries/Sparkle-LICENSE.txt"
