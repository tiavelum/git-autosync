#!/bin/bash
# Install git-autosync launchd agents for the current user.
#
# Reads ~/.config/git-autosync/repos, then generates and loads two
# launchd agents:
#   com.tiavelum.git-autosync.watch    — fires when a repo's branch refs change
#   com.tiavelum.git-autosync.interval — fires every 15 minutes (pulls)
#
# Re-run after editing the repos config to regenerate the watch list.
#
# The config may be a symlink into a repo (recommended — that is how the
# list itself gets versioned). This script never overwrites an existing
# config, and refuses to replace a symlink whose target is missing.

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

# A symlink to a repo that is not cloned yet: `[ ! -f ]` is true here, so
# without this check the link would be replaced by a regular file and the
# versioned list would be quietly disconnected.
if [ -L "$CONFIG" ] && [ ! -e "$CONFIG" ]; then
  echo "ERROR: $CONFIG is a symlink pointing at something that does not exist:" >&2
  echo "         -> $(readlink "$CONFIG")" >&2
  echo "       Clone the repo holding your repo list, then re-run this script." >&2
  echo "       Refusing to replace the link with a default file." >&2
  exit 1
fi

# Deliberately NOT seeded with a working default: a plausible-looking list
# on a fresh machine syncs the wrong repos and reports success while doing
# it. An empty list syncs nothing, loudly.
if [ ! -e "$CONFIG" ]; then
  cat > "$CONFIG" <<'EOF'
# git-autosync: one repo path per line. Lines starting with # are ignored.
#
# Created empty on purpose. Add the repos you want synced, one per line,
# e.g. ~/vc/my-repo — and keep the trailing newline on the last line.
#
# Better: keep this list in a repo so it is versioned, and symlink it:
#   ln -sfn ~/vc/dotfiles/git-autosync-repos ~/.config/git-autosync/repos
EOF
  echo "WARNING: no repo list found — created an empty one at $CONFIG" >&2
  echo "         git-autosync will sync NOTHING until you list repos there," >&2
  echo "         or point it at your versioned list with a symlink." >&2
fi

# `|| [ -n "$repo" ]`: without it, a last line lacking a trailing newline
# is read but never processed — that repo would silently not be watched.
watch_paths=""
listed=0
while IFS= read -r repo || [ -n "$repo" ]; do
  case "$repo" in ''|\#*) continue ;; esac
  listed=$((listed + 1))
  repo="${repo/#\~/$HOME}"
  if [ -d "$repo/.git" ]; then
    watch_paths="$watch_paths
    <string>$repo/.git/autosync-push</string>"
  else
    echo "WARNING: $repo is not a git repo — not watching it" >&2
  fi
done < "$CONFIG"

if [ "$listed" -eq 0 ]; then
  echo "WARNING: $CONFIG lists no repos — the agents will be installed but idle" >&2
fi

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
    <string>push</string>
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
    <string>pull</string>
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

echo "Done ($listed repo(s) listed). Log: ~/Library/Logs/git-autosync.log"
