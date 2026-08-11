#!/bin/bash
# git-autosync — keep local clones in sync with their remotes.
#
# For each repo listed in ~/.config/git-autosync/repos:
#   1. fetch
#   2. pull --rebase --autostash  (only when it is safe)
#   3. push                       (only if local is ahead)
#
# Triggered by launchd: WatchPaths on each repo's .git/refs/heads gives an
# instant push after every commit; StartInterval gives periodic pulls.
# Safe to run at any time; it skips anything that looks risky.

set -u

CONFIG="${HOME}/.config/git-autosync/repos"
LOG="${HOME}/Library/Logs/git-autosync.log"
LOCKDIR="${TMPDIR:-/tmp}/git-autosync.lock"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# Single-instance guard: watch + interval jobs may fire together.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCKDIR"' EXIT

[ -f "$CONFIG" ] || { log "no config at $CONFIG — nothing to do"; exit 0; }

while IFS= read -r repo; do
  case "$repo" in ''|\#*) continue ;; esac
  repo="${repo/#\~/$HOME}"

  if [ ! -d "$repo/.git" ]; then
    log "SKIP $repo: not a git repo"
    continue
  fi

  cd "$repo" || continue

  # Never touch a repo mid-rebase/merge.
  if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] || [ -f .git/MERGE_HEAD ]; then
    log "SKIP $repo: rebase/merge in progress"
    continue
  fi

  branch=$(git symbolic-ref --short -q HEAD)
  if [ -z "$branch" ]; then
    log "SKIP $repo: detached HEAD"
    continue
  fi

  if ! git fetch --quiet 2>>"$LOG"; then
    log "WARN $repo: fetch failed (offline?)"
    continue
  fi

  if ! git rev-parse --verify -q "@{u}" >/dev/null; then
    log "SKIP $repo: branch '$branch' has no upstream"
    continue
  fi

  behind=$(git rev-list --count "HEAD..@{u}")
  ahead=$(git rev-list --count "@{u}..HEAD")

  if [ "$behind" -gt 0 ]; then
    if git pull --rebase --autostash --quiet 2>>"$LOG"; then
      log "PULL $repo: $behind commit(s) from origin/$branch"
    else
      git rebase --abort 2>/dev/null
      log "ERROR $repo: pull --rebase failed, aborted — resolve manually"
      continue
    fi
  fi

  if [ "$ahead" -gt 0 ]; then
    upstream=$(git rev-parse --abbrev-ref "@{u}")
    if git push --quiet "${upstream%%/*}" "HEAD:${upstream#*/}" 2>>"$LOG"; then
      log "PUSH $repo: $ahead commit(s) to origin/$branch"
    else
      log "ERROR $repo: push failed — resolve manually"
    fi
  fi
done < "$CONFIG"
