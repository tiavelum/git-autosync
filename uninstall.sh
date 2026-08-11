#!/bin/bash
# Remove git-autosync launchd agents. Config and log are left in place.

set -eu

AGENTS="$HOME/Library/LaunchAgents"
uid=$(id -u)

for name in com.tiavelum.git-autosync.watch com.tiavelum.git-autosync.interval; do
  plist="$AGENTS/$name.plist"
  if [ -f "$plist" ]; then
    launchctl bootout "gui/$uid" "$plist" 2>/dev/null || true
    rm "$plist"
    echo "Removed $name"
  fi
done

echo "Done. Config (~/.config/git-autosync) and log kept."
