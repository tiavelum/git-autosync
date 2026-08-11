# git-autosync

Keeps local git clones in sync with their GitHub remotes on macOS — commits
made locally get pushed automatically, and remote changes get pulled in.

Built as a companion for [setup-docs](https://github.com/tiavelum/setup-docs)
Cowork sessions: Claude can edit and commit in a local clone but has no
network path to GitHub, so this tool closes the gap. It is generic, though —
it syncs any repo you list.

## How it works

Two launchd user agents run `bin/git-autosync.sh`:

| Agent | Trigger | Purpose |
|---|---|---|
| `…git-autosync.watch` | a watched repo's `.git/refs/heads` changes | push seconds after every commit |
| `…git-autosync.interval` | every 15 min + at login | pull remote changes |

For each repo listed in `~/.config/git-autosync/repos` the script fetches,
then `pull --rebase --autostash` if behind, then pushes if ahead. It skips
repos that are mid-rebase/merge, on a detached HEAD, or without upstream,
and aborts cleanly on conflicts (logged, never destructive).

## Install

```sh
git clone git@github.com:tiavelum/git-autosync.git ~/git-autosync
cd ~/git-autosync && ./install.sh
```

Edit `~/.config/git-autosync/repos` (one path per line, `~` allowed), then
re-run `./install.sh` to regenerate the watch list.

## Verify / troubleshoot

```sh
tail -f ~/Library/Logs/git-autosync.log
launchctl list | grep git-autosync
```

- Pushes need your SSH key. If it has a passphrase, make sure it is in the
  keychain: `ssh-add --apple-use-keychain` and `UseKeychain yes` in
  `~/.ssh/config`.
- `ERROR … resolve manually` in the log means a conflict or failed push —
  fix it in the repo yourself; the tool will resume afterwards.

## Uninstall

```sh
./uninstall.sh
```
