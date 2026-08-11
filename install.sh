#!/bin/bash
# Install git-autosync launchd agents for the current user.
#
# Reads ~/.config/git-autosync/repos (created with a default on first run),
# then generates and loads two launchd agents:
#   com.tiavelum.git-autosync.watch    — fires when a repo's branch refs change
#   com.tiavelum.git-autosync.interval — fires every 15 minutes (pulls)
#
# Re-run after editing the repos config to regenerate the watch list.

set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$REPO_DIR/bin/git-autosync.sh"
CONFIG_DIR="$HOME/.config/git-autosync"
CONFIG="$CONFIG_DIR/repos"
AGENTS="$HOME/Library/LaunchAgents"
WATCH_PLIST="$AGENTS/com.tiavelum.git-autosync.watch.plist"
INTERVAL_PLIST="$AGENTS/com.tiavelum.git-autosync.interval.plist"

mkdir -p "$CONFIG_DIR" "$AGENTS" "$HOME/Library/Logs"
chmod +x "$SCRIPT"

if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" <<'EOF'
# git-autosync: one repo path per line. Lines starting with # are ignored.
~/setup-docs
~/git-autosync
EOF
  echo "Created default config: $CONFIG"
fi

watch_paths=""
while IFS= read -r repo; do
  case "$repo" in ''|\#*) continue ;; esac
  repo="${repo/#\~/$HOME}"
  if [ -d "$repo/.git/refs/heads" ]; then
    watch_paths="$watch_paths
    <string>$repo/.git/refs/heads</string>"
  else
    echo "WARNING: $repo has no .git/refs/heads — not watching it" >&2
  fi
done < "$CONFIG"

cat > "$WATCH_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tiavelum.git-autosync.watch</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SCRIPT</string>
  </array>
  <key>WatchPaths</key>
  <array>$watch_paths
  </array>
  <key>ThrottleInterval</key>
  <integer>10</integer>
</dict>
</plist>
EOF

cat > "$INTERVAL_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tiavelum.git-autosync.interval</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SCRIPT</string>
  </array>
  <key>StartInterval</key>
  <integer>900</integer>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF

uid=$(id -u)
for plist in "$WATCH_PLIST" "$INTERVAL_PLIST"; do
  launchctl bootout "gui/$uid" "$plist" 2>/dev/null || true
  launchctl bootstrap "gui/$uid" "$plist"
  echo "Loaded $(basename "$plist")"
done

echo "Done. Log: ~/Library/Logs/git-autosync.log"
