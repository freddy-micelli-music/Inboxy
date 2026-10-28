#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
sh "$project_dir/fetch-sparkle.sh"
check_dir="${AERIS_BUILD_DIR:-$project_dir/build}/checks"
mkdir -p "$check_dir" "$check_dir/ModuleCache"
xcrun swiftc -swift-version 5 -F "$project_dir/Libraries" -framework Sparkle -Xlinker -rpath -Xlinker "$project_dir/Libraries" -module-cache-path "$check_dir/ModuleCache" "$project_dir/Sources/Aeris/Models.swift" "$project_dir/Sources/Aeris/GoogleAuth.swift" "$project_dir/Sources/Aeris/GmailAPI.swift" "$project_dir/Sources/Aeris/WebSessions.swift" "$project_dir/Sources/Aeris/Backup.swift" "$project_dir/Sources/Aeris/AutomaticUpdater.swift" "$project_dir/Sources/Aeris/AppModel.swift" "$project_dir/Checks/CoreChecks.swift" -o "$check_dir/CoreChecks" "$@"
"$check_dir/CoreChecks" "$@"
