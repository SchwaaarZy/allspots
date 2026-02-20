#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
sync_script="$repo_root/scripts/sync.sh"

if [[ ! -f "$sync_script" ]]; then
  echo "Script introuvable: $sync_script"
  exit 1
fi

chmod +x "$sync_script"

label="com.allspots.autosync"
launch_agents_dir="$HOME/Library/LaunchAgents"
plist_path="$launch_agents_dir/$label.plist"
log_dir="$HOME/Library/Logs"
stdout_log="$log_dir/allspots-autosync.log"
stderr_log="$log_dir/allspots-autosync.err.log"

mkdir -p "$launch_agents_dir" "$log_dir"

cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$sync_script</string>
    <string>auto-sync macOS (30 min)</string>
  </array>

  <key>StartInterval</key>
  <integer>1800</integer>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$stdout_log</string>

  <key>StandardErrorPath</key>
  <string>$stderr_log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist_path"
launchctl enable "gui/$(id -u)/$label"
launchctl kickstart -k "gui/$(id -u)/$label"

echo "Auto-sync macOS activé (toutes les 30 minutes)."
echo "Plist: $plist_path"
echo "Logs: $stdout_log et $stderr_log"