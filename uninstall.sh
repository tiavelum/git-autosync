#!/bin/bash
# Remove git-autosync launchd agents. Config and log are left in place.

set -eu

AGENTS="$HOME/Library/LaunchAgents"
uid=$(id -u)

for name in com.tiavelum.git-autosync.watch com.tiavelum.git-autosync.interval; do
  plist="$AGENTS/$name.plist"

  # Boot the label out regardless of the plist. A job whose plist was deleted
  # by hand is still loaded and still running; only deleting files would leave
  # it that way while this script printed "Done".
  if launchctl bootout "gui/$uid/$name" 2>/dev/null; then
    unloaded=1
  else
    unloaded=0
  fi

  if [ -f "$plist" ]; then
    rm "$plist"
    removed=1
  else
    removed=0
  fi

  if [ "$unloaded" -eq 1 ] && [ "$removed" -eq 1 ]; then
    echo "Removed $name (unloaded, plist deleted)"
  elif [ "$unloaded" -eq 1 ]; then
    echo "Removed $name (unloaded; no plist file was present)"
  elif [ "$removed" -eq 1 ]; then
    echo "Removed $name (plist deleted; job was not loaded)"
  else
    echo "Not installed: $name (nothing loaded, no plist)"
  fi
done

echo "Done. Config (~/.config/git-autosync) and log kept."
