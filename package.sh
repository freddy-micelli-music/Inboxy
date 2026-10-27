#!/bin/sh
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
app_path="${1:?Indiquez le chemin de Inboxy.app}"
distribution_dir="${2:-$(dirname -- "$app_path")/Distribution}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
case "$version" in ''|*[!0-9.]*) echo "Numéro de version invalide." >&2; exit 1 ;; esac
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Contents/Info.plist")"
[ "$bundle_id" = 'fr.aeris.mail.prototype' ] || { echo "Application Inboxy attendue." >&2; exit 1; }
codesign --verify --deep --strict "$app_path"
mkdir -p "$distribution_dir"
distribution_dir="$(CDPATH= cd -- "$distribution_dir" && pwd)"
package_dir="$distribution_dir/Inboxy-$version"
if [ -e "$package_dir" ]; then
    [ -f "$package_dir/MISE-A-JOUR.txt" ] && [ -L "$package_dir/Applications" ] || { echo "Le dossier cible contient des fichiers non reconnus." >&2; exit 1; }
    [ "$(readlink "$package_dir/Applications")" = /Applications ] || exit 1
    if [ -e "$package_dir/Inboxy.app" ]; then
        old_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$package_dir/Inboxy.app/Contents/Info.plist")"
        [ "$old_id" = 'fr.aeris.mail.prototype' ] || { echo "Application cible non reconnue." >&2; exit 1; }
        rm -rf -- "$package_dir/Inboxy.app"
    fi
fi
mkdir -p "$package_dir"
ditto "$app_path" "$package_dir/Inboxy.app"
if [ ! -L "$package_dir/Applications" ]; then ln -s /Applications "$package_dir/Applications"; fi
sed "s/@VERSION@/$version/g" "$project_dir/INSTALLATION.txt.in" > "$package_dir/MISE-A-JOUR.txt"
codesign --verify --deep --strict "$package_dir/Inboxy.app"
ditto -c -k --sequesterRsrc --keepParent "$package_dir" "$distribution_dir/Inboxy-$version-macOS.zip"
echo "Dossier d’installation : $package_dir"
echo "Archive : $distribution_dir/Inboxy-$version-macOS.zip"
