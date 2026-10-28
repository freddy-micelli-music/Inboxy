#!/bin/sh
# Publisher-only: never exports the private signing key from the Keychain.
set -eu
app="${1:?Chemin de Inboxy.app requis}"
release_dir="${2:?Dossier de publication requis}"
tools_dir="${SPARKLE_TOOLS_DIR:?SPARKLE_TOOLS_DIR doit désigner la distribution officielle Sparkle 2.10.0}"
signer="${INBOXY_KEYCHAIN_SIGNER:?INBOXY_KEYCHAIN_SIGNER doit désigner InboxyKeychainSigner compilé}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")"
case "$version:$build" in *[!0-9.:]*|'') echo 'Version invalide.' >&2; exit 1 ;; esac
public_key="$("$signer" public-key)"
embedded_key="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$app/Contents/Info.plist")"
[ "$public_key" = "$embedded_key" ] || { echo 'La clé publique de l’application ne correspond pas au Trousseau Inboxy.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
mkdir -p "$release_dir"
archive="$release_dir/Inboxy-$version-Update.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
signature="$("$signer" tool "$tools_dir/bin/sign_update" -p "$archive")"
"$signer" tool "$tools_dir/bin/sign_update" --verify "$archive" "$signature"
python3 - "$release_dir/appcast.xml" "$version" "$build" "$archive" "$signature" <<'PY'
from pathlib import Path
import sys,xml.etree.ElementTree as ET,email.utils,datetime
out,version,build,archive,signature=sys.argv[1:]
ns='http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',ns)
rss=ET.Element('rss',{'version':'2.0'})
c=ET.SubElement(rss,'channel')
ET.SubElement(c,'title').text='Inboxy'
ET.SubElement(c,'link').text='https://github.com/freddy-micelli-music/Inboxy'
ET.SubElement(c,'description').text='Mises à jour signées d’Inboxy pour macOS'
i=ET.SubElement(c,'item')
ET.SubElement(i,'title').text='Inboxy '+version
ET.SubElement(i,'pubDate').text=email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(i,'{'+ns+'}minimumSystemVersion').text='14.0'
ET.SubElement(i,'enclosure',{'url':f'https://github.com/freddy-micelli-music/Inboxy/releases/download/v{version}/Inboxy-{version}-Update.zip','length':str(Path(archive).stat().st_size),'type':'application/octet-stream','{'+ns+'}version':build,'{'+ns+'}shortVersionString':version,'{'+ns+'}edSignature':signature,'{'+ns+'}installationType':'application'})
ET.indent(rss,space='  ')
ET.ElementTree(rss).write(out,encoding='UTF-8',xml_declaration=True)
PY
"$signer" tool "$tools_dir/bin/sign_update" "$release_dir/appcast.xml"
"$signer" tool "$tools_dir/bin/sign_update" --verify "$release_dir/appcast.xml"
echo "Archive et flux signés préparés dans $release_dir"
echo 'Publier le ZIP et téléverser appcast.xml sans le modifier.'
