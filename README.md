# git-autosync

Keeps local git clones on macOS in sync with their remotes. Pulls are
automatic; pushes happen only on demand. Built as a companion for
[setup-docs](https://github.com/tiavelum/setup-docs) Cowork sessions —
Claude can edit and commit in a local clone but cannot push — yet it is
generic: it syncs any repo you list.

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
git clone git@github.com:tiavelum/git-autosync.git ~/git-autosync
cd ~/git-autosync && ./install.sh
```

Re-run `./install.sh` after editing the repo list — it regenerates and
reloads both jobs.

## Pushing

Three equivalent ways, use whichever fits the moment:

```sh
git push                                # classic, always works
touch <repo>/.git/autosync-push         # ask the watch job to push
~/git-autosync/bin/git-autosync.sh sync # pull + push all repos now
```

The trigger file is consumed by the run.

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
  `~/git-autosync` from the repo list and re-run `./install.sh`.
- **SSH key with passphrase?** Make sure it's in the keychain:
  `ssh-add --apple-use-keychain`, plus `UseKeychain yes` in
  `~/.ssh/config`.
- `ERROR … resolve manually` in the log = conflict or failed push; fix it
  in that repo, syncing of the others continues regardless.

## Uninstall

```sh
./uninstall.sh
```

Removes both jobs; config and log stay.
