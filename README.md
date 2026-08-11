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

## Good to know

- **macOS "background items added" notice** — that's these two launchd
  agents. They run as your user, open no ports, and do nothing but git
  operations on the repos you listed. Inspect them anytime:
  `~/Library/LaunchAgents/com.tiavelum.git-autosync.*.plist`.
- **Auto-push means auto-publish.** Every commit in a watched repo reaches
  GitHub within seconds — including mistaken ones. Don't commit secrets;
  there is no review window anymore.
- **The tool syncs itself.** `~/git-autosync` is in the default watch list,
  so updates pushed to this repo become the running script on your Mac.
  If you'd rather update manually, remove `~/git-autosync` from
  `~/.config/git-autosync/repos` and re-run `./install.sh`.
- **Editing the repo list**: one path per line in
  `~/.config/git-autosync/repos`, then re-run `./install.sh` (it
  regenerates the watch list; a repo without upstream is skipped and
  logged, nothing breaks).
- **Conflicts are never resolved automatically.** On a failed rebase the
  script aborts and logs `ERROR … resolve manually`; the repo is left as
  it was, syncing of other repos continues.

## Uninstall

```sh
./uninstall.sh
```
