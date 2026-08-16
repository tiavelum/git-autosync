#!/bin/bash
# git-autosync — keep local clones in sync with their remotes.
#
# Usage: git-autosync.sh [mode]
#   pull  — fetch + pull --rebase only; never pushes (interval agent default)
#   push  — pull, then push — but only repos with a trigger file
#           <repo>/.git/autosync-push (consumed on run; watch agent default)
#   sync  — pull + push everything that is ahead (manual full run)
#
# Repos are listed in ~/.config/git-autosync/repos, which may be a symlink
# into a repo so the list itself is versioned.
# Safe to run at any time; it skips anything that looks risky.
#
# This script transports commits; it never creates them. Uncommitted work
# is reported (DIRTY) and otherwise left strictly alone — committing stays
# with whoever authored the change.

set -u

MODE="${1:-sync}"
CONFIG="${HOME}/.config/git-autosync/repos"
LOG="${HOME}/Library/Logs/git-autosync.log"
LOCKDIR="${TMPDIR:-/tmp}/git-autosync.lock"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# Per-repo outcome of the last run, readable from inside the repo itself:
# <repo>/.git/autosync-status. Lets a Claude session (or a human) verify
# what happened instead of assuming the trigger worked.
status() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" > "$repo/.git/autosync-status"
}

# Single-instance guard: agents may fire together.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCKDIR"' EXIT

# A dangling symlink is a different problem from an absent config — the
# list exists, its clone does not. Do not report it as "nothing to do".
if [ -L "$CONFIG" ] && [ ! -e "$CONFIG" ]; then
  log "ERROR config $CONFIG is a symlink to a missing target ($(readlink "$CONFIG")) — nothing synced; clone that repo"
  exit 1
fi

[ -f "$CONFIG" ] || { log "no config at $CONFIG — nothing to do"; exit 0; }

# `|| [ -n "$repo" ]`: read returns non-zero on a last line without a
# trailing newline, but has already assigned it. Without this guard the
# final repo in the list is silently never synced.
while IFS= read -r repo || [ -n "$repo" ]; do
  case "$repo" in ''|\#*) continue ;; esac
  repo="${repo/#\~/$HOME}"

  if [ ! -d "$repo/.git" ]; then
    log "SKIP $repo: not a git repo"
    continue
  fi

  # In push mode, only act on repos whose trigger file is set.
  trigger="$repo/.git/autosync-push"
  if [ "$MODE" = "push" ]; then
    [ -f "$trigger" ] || continue
    rm -f "$trigger"
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

  # Uncommitted work is invisible to the ahead/behind counts below, so a
  # repo full of unsaved edits would otherwise be reported as "OK".
  # Report it on every status line; never act on it.
  tracked=$(git status --porcelain --untracked-files=no 2>/dev/null | grep -c '^' || true)
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null | grep -c '^' || true)
  if [ "$tracked" -gt 0 ] || [ "$untracked" -gt 0 ]; then
    dirty=" | DIRTY: $tracked uncommitted change(s), $untracked untracked file(s) — not versioned anywhere; commit them."
    log "DIRTY $repo: $tracked uncommitted, $untracked untracked"
  else
    dirty=""
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
      status "CONFLICT: rebase onto origin/$branch failed; $behind behind, $ahead ahead. Resolve in the clone, then trigger again.$dirty"
      continue
    fi
  fi

  if [ "$ahead" -gt 0 ]; then
    if [ "$MODE" = "pull" ]; then
      log "HOLD $repo: $ahead commit(s) ahead — not pushing (pull mode)"
      status "HOLD: $ahead commit(s) waiting; nothing pushed (pull mode).$dirty"
      continue
    fi
    upstream=$(git rev-parse --abbrev-ref "@{u}")
    if git push --quiet "${upstream%%/*}" "HEAD:${upstream#*/}" 2>>"$LOG"; then
      log "PUSH $repo: $ahead commit(s) to origin/$branch"
      status "OK: pushed $ahead commit(s) to $upstream.$dirty"
    else
      log "ERROR $repo: push failed — resolve manually"
      status "FAILED: push rejected; $ahead commit(s) still local. Rebase onto origin/$branch, then trigger again.$dirty"
    fi
  else
    status "OK: nothing to push; clone matches $branch.$dirty"
  fi
done < "$CONFIG"
