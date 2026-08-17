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
# is reported (DIRTY) and never committed; it is briefly autostashed during
# a rebase (git pull --rebase --autostash) and re-applied afterwards —
# committing stays with whoever authored the change.

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

# An unrecognised mode used to fall through to the push branch and push every
# listed repo. Fail loudly instead.
case "$MODE" in
  pull|push|sync) ;;
  *)
    log "ERROR unknown mode '$MODE' — expected pull, push or sync; nothing synced"
    printf 'unknown mode: %s (expected pull, push or sync)\n' "$MODE" >&2
    exit 2
    ;;
esac

# Single-instance guard: agents may fire together. A lock left behind by a
# killed run would otherwise silence every later run forever — both agents
# then look healthy and nothing syncs — so an old one is taken over.
LOCK_MAX_AGE=3600
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  lock_mtime=$(stat -f %m "$LOCKDIR" 2>/dev/null || true)
  case "$lock_mtime" in ''|*[!0-9]*) lock_mtime=0 ;; esac
  lock_age=$(( $(date +%s) - lock_mtime ))
  if [ "$lock_age" -gt "$LOCK_MAX_AGE" ]; then
    log "WARN stale lock $LOCKDIR (${lock_age}s old) — taking it over"
    rm -rf "$LOCKDIR"
    if ! mkdir "$LOCKDIR" 2>/dev/null; then
      log "SKIP another git-autosync run took the lock — nothing done"
      exit 0
    fi
  else
    log "SKIP another git-autosync run is in progress (lock ${lock_age}s old) — nothing done"
    exit 0
  fi
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

  # In push mode, only act on repos whose trigger file is set. The trigger is
  # consumed further down, once the repo has passed its preconditions — a run
  # that cannot even start should not swallow the request silently.
  trigger="$repo/.git/autosync-push"
  if [ "$MODE" = "push" ]; then
    [ -f "$trigger" ] || continue
  fi

  if ! cd "$repo"; then
    log "SKIP $repo: cannot enter directory"
    status "SKIPPED: cannot enter $repo; nothing pulled or pushed."
    continue
  fi

  # Never touch a repo mid-rebase/merge.
  if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] || [ -f .git/MERGE_HEAD ]; then
    log "SKIP $repo: rebase/merge in progress"
    status "SKIPPED: rebase/merge in progress; nothing pulled or pushed. Finish or abort it, then trigger again."
    continue
  fi

  branch=$(git symbolic-ref --short -q HEAD)
  if [ -z "$branch" ]; then
    log "SKIP $repo: detached HEAD"
    status "SKIPPED: detached HEAD; nothing pulled or pushed. Check out a branch, then trigger again."
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
    status "FAILED: fetch failed (offline?); nothing pulled or pushed. Trigger again when the remote is reachable.$dirty"
    continue
  fi

  if ! git rev-parse --verify -q "@{u}" >/dev/null; then
    log "SKIP $repo: branch '$branch' has no upstream"
    status "SKIPPED: branch '$branch' has no upstream; nothing pulled or pushed. Set one with 'git push -u <remote> $branch'.$dirty"
    continue
  fi

  # The real upstream, not an assumed origin/<branch>: it is what the push
  # below actually targets, so it is what the log and status lines must name.
  upstream=$(git rev-parse --abbrev-ref "@{u}")

  # Preconditions passed — the request is being honoured, so consume it. A
  # trigger left over from a repo that never got this far stays in place.
  [ "$MODE" = "push" ] && rm -f "$trigger"

  behind=$(git rev-list --count "HEAD..@{u}")
  ahead=$(git rev-list --count "@{u}..HEAD")

  if [ "$behind" -gt 0 ]; then
    if git pull --rebase --autostash --quiet 2>>"$LOG"; then
      log "PULL $repo: $behind commit(s) from $upstream"
    else
      git rebase --abort 2>/dev/null
      log "ERROR $repo: pull --rebase failed, aborted — resolve manually"
      status "CONFLICT: rebase onto $upstream failed; $behind behind, $ahead ahead. Resolve in the clone, then trigger again.$dirty"
      continue
    fi
  fi

  if [ "$ahead" -gt 0 ]; then
    if [ "$MODE" = "pull" ]; then
      log "HOLD $repo: $ahead commit(s) ahead — not pushing (pull mode)"
      status "HOLD: $ahead commit(s) waiting; nothing pushed (pull mode).$dirty"
      continue
    fi
    if git push --quiet "${upstream%%/*}" "HEAD:${upstream#*/}" 2>>"$LOG"; then
      log "PUSH $repo: $ahead commit(s) to $upstream"
      status "OK: pushed $ahead commit(s) to $upstream.$dirty"
    else
      log "ERROR $repo: push failed — resolve manually"
      status "FAILED: push rejected; $ahead commit(s) still local. Rebase onto $upstream, then trigger again.$dirty"
    fi
  else
    status "OK: nothing to push; clone matches $upstream.$dirty"
  fi
done < "$CONFIG"
