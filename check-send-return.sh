#!/bin/sh
# Builds an isolated native WebKit check app. Launch it manually; no real email is sent.
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
check_dir="$project_dir/build/send-return-checks"
mkdir -p "$check_dir/Checks.app/Contents/MacOS" "$check_dir/ModuleCache"
python3 - "$project_dir" "$check_dir" <<'PY'
from pathlib import Path
import sys,plistlib
project,root=map(Path,sys.argv[1:])
s=(project/'Sources/Aeris/WebSessions.swift').read_text()
body=s.split('enum GmailSendCompletion {',1)[1].split('@MainActor final class GmailMailboxTracker',1)[0]
(root/'Observer.swift').write_text('import WebKit\nenum GmailMailboxTracker { static let world = WKContentWorld.world(name: "AerisMailbox") }\nenum GmailSendCompletion {'+body)
(root/'Checks.app/Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'fr.inboxy.sendreturnchecks','CFBundleExecutable':'Checks','CFBundleName':'Inboxy send-return checks','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication'}))
PY
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$check_dir/ModuleCache" "$project_dir/Sources/Aeris/Models.swift" "$check_dir/Observer.swift" "$project_dir/Checks/SendReturnChecks.swift" "$project_dir/Checks/SendReturnHarness.swift" -o "$check_dir/Checks.app/Contents/MacOS/Checks"
codesign --force --sign - "$check_dir/Checks.app"
echo "Ouvrir manuellement : $check_dir/Checks.app"
echo 'Résultat texte : $TMPDIR/InboxySendReturnChecks.log'
