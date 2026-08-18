# git-autosync

Keeps local git clones on macOS in sync with their remotes. Pulls are
automatic; pushes happen only on demand. Built for assistant sessions
(Claude Cowork) that can edit and commit in a local clone but cannot push —
yet it is generic: it syncs any repo you list.

It transports commits. It never creates them: committing stays with
whoever authored the change (you, or a Claude session). Uncommitted work
is reported and never committed; during a pull it is briefly autostashed
and re-applied (`git pull --rebase --autostash`).

## How it works

Two launchd jobs run `bin/git-autosync.sh` on the repos listed in
`~/.config/git-autosync/repos` (one path per line, `~` allowed):

| Job | Fires | Does |
|---|---|---|
| interval | every 15 min + login | pull; never pushes |
| watch | `<repo>/.git/autosync-push` appears | push that repo |

Pulls are `--rebase --autostash`. The script skips repos that are
mid-rebase/merge, on a detached HEAD, or without upstream. On a conflict
it aborts and logs — never destructive. Unpushed commits show as `HOLD`
lines in the log.

## Install

```sh
git clone git@github.com:tiavelum/git-autosync.git ~/vc/git-autosync
cd ~/vc/git-autosync && ./install.sh
```

Re-run `./install.sh` after editing the sync list — it regenerates and
reloads both jobs. This is required, not cosmetic: the watch job's
`WatchPaths` array is baked into the plist at install time, so a newly
listed repo is not watched until you regenerate it.

## Pushing

Three equivalent ways, use whichever fits the moment:

```sh
git push                                # classic, always works
touch <repo>/.git/autosync-push         # ask the watch job to push
~/vc/git-autosync/bin/git-autosync.sh sync # pull + push all repos now
```

The trigger file is consumed once the repo has passed its preconditions —
whether the push then succeeds or not. A repo that never got that far
(mid-rebase, detached HEAD, no upstream, fetch failed) keeps its trigger.
Either way, check the outcome instead of assuming:

```sh
cat <repo>/.git/autosync-status
```

It is written on every run that reached that repo, including the runs that
did nothing, and reports `OK`, `HOLD` (commits waiting, pull mode),
`FAILED` (push rejected, or fetch failed), `SKIPPED` (a precondition was
not met — the line says which) or `CONFLICT` (rebase aborted — the clone
diverged from the remote and needs a human or a session to reconcile it).

Two cases leave no status behind, so an old line can survive there: a
listed path that is not a git repo at all (there is no `.git` to write
into), and, in push mode, a repo whose trigger was not set — it is passed
over untouched. Check the timestamp the status line carries.

Any of those may carry a trailing `DIRTY: …` note — see below.

## Committed vs. merely saved

The `OK` / `HOLD` / `FAILED` outcomes are about **commits**. A file you
edited and saved but never committed is not a commit, so it cannot be
pushed and does not make the repo "ahead". Such a change lives on exactly
one disk, in no history — and a clean `OK: nothing to push` would sit right
on top of it.

So every status line carries a `DIRTY: n uncommitted change(s), m
untracked file(s)` note when the working tree is not clean. It is a
warning only — the script will not stage, commit or stash on your behalf,
because a robot-written commit of a half-finished edit is worse than an
honest warning. Fix it the normal way:

```sh
cd <repo> && git status && git add -A && git commit -m "…"
touch .git/autosync-push
```

## Use by Claude

A Cowork session works in your connected clone: it edits, commits, and
pulls arrive automatically via the interval job. It cannot push — no
credentials, no SSH route. When you tell Claude to push, it creates the
trigger file (`touch <repo>/.git/autosync-push`); your Mac then pushes
with your keys seconds later. So the publish decision stays on your side,
Claude only requests it.

## SSH or HTTPS?

Both work here. Pushes run on your Mac, so the tool simply uses whatever
transport the clone's remote is set to (`git remote -v`): SSH remotes use
your SSH key, HTTPS remotes your stored token. Your credentials never
leave the machine — which is exactly why this tool exists instead of
handing a token to the sandbox.

## Inspect

```sh
launchctl list | grep git-autosync      # "-" = registered but idle
tail -f ~/Library/Logs/git-autosync.log
```

The jobs are dormant plists in `~/Library/LaunchAgents/`; a process only
exists for the seconds a sync takes. macOS announces them once as
"background items added" after install.

## Good to know

- **Pushing stays a decision** — commits accumulate locally until someone
  pushes or sets the trigger. Anything that can write into a watched
  repo's `.git/` can request a push.
- **The tool syncs itself**: updates pushed to this repo are auto-pulled
  and become the running script. Prefer manual updates? Remove
  `~/vc/git-autosync` from the sync list and re-run `./install.sh`.
- **SSH key with passphrase?** Make sure it's in the keychain:
  `ssh-add --apple-use-keychain`, plus `UseKeychain yes` in
  `~/.ssh/config`.
- `ERROR … resolve manually` in the log = conflict or failed push; fix it
  in that repo, syncing of the others continues regardless.
- **Diverged clone** (behind *and* ahead) happens when something writes to
  GitHub directly — e.g. a Claude session using the GitHub connector API,
  which never passes through the clone. Reconcile with
  `git rebase origin/main`, resolve conflicts, then trigger again.
- **End the sync list with a newline.** The scripts tolerate a missing one,
  but `printf '%s\n'` when appending is the safe habit. In zsh a trailing
  `%` after `cat`-ing the file is the tell that it is missing.

## Uninstall

```sh
./uninstall.sh
```

Removes both jobs; config and log stay.

## Which publishing route to use

The three routes above are equivalent for a human at a keyboard, and a plain
`git push` from your own terminal is always legitimate.

The trigger file is the one to teach an assistant, for one reason: it is
the only route that works from a process holding **no credentials**.
An assistant session commits in the clone and touches the trigger; this agent
pushes with your keys. That separation is the point — not a preference about
which command is nicer.

### `FAILED: push rejected` on one repository only

Check the remote first: `git -C <repo> remote get-url origin`. A clone on an
`https://` remote needs a credential helper and a live token, while an
`ssh://` one uses the key `gh auth login` set up — so a single HTTPS clone
among SSH ones fails to push while every other repository succeeds, and the
symptom looks like divergence rather than authentication. Fix it once:

```bash
git -C <repo> remote set-url origin git@github.com:<owner>/<repo>.git
```
