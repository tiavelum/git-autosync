# git-autosync

Keeps local git clones on macOS in sync with their remotes: pulls
automatically, pushes on demand. Built for assistant sessions that can
commit in a local clone but hold no credentials — yet generic: it syncs any
repo you list. It transports commits and never creates them; uncommitted
work is reported, autostashed around a rebase, and left alone.

## Install

```sh
git clone git@github.com:tiavelum/git-autosync.git ~/vc/git-autosync
cd ~/vc/git-autosync && ./install.sh          # ./uninstall.sh removes the agents
```

`install.sh` reads the sync list — `~/.config/git-autosync/repos`, one path
per line, `~` allowed, best a symlink into a versioned file — and loads two
launchd user agents:

| Agent | Fires | Does |
|---|---|---|
| interval | every 15 min and at login | `pull --rebase --autostash`; never pushes |
| watch | `<repo>/.git/autosync-push` appears | pushes that repo with your keys |

**Re-run `install.sh` after editing the list**: the watch paths are baked
into the agent at install time. It refuses to run with a list that names no
clone, and never seeds a default list.

## Publishing, and reading what happened

```sh
touch <repo>/.git/autosync-push            # ask the watch agent to push
cat   <repo>/.git/autosync-status          # the outcome of the last run
```

`git push` and `bin/git-autosync.sh sync` (pull + push everything now) are
equivalent for a person at the keyboard; the trigger file is the one route
that works for a process holding **no credentials** — a session commits and
touches the file, your Mac pushes.

The status line reads `OK`, `HOLD` (commits waiting, pull mode), `FAILED`
(push rejected or fetch failed), `SKIPPED` (a precondition — mid-rebase,
detached HEAD, no upstream — the line says which) or `CONFLICT` (rebase
aborted; the clone diverged and needs a person). Any of them carries a
trailing `DIRTY: …` when the working tree has uncommitted work — the tool
will not commit or stash on your behalf. The trigger file disappearing
proves nothing; read the status. Full log: `~/Library/Logs/git-autosync.log`.

## Good to know

- Pushes use whatever transport the clone's remote has: an `https://`
  remote needs a stored token, `git@github.com:` uses your SSH key — one
  HTTPS clone among SSH ones is the usual cause of a lone `FAILED`
  (`git remote set-url origin git@github.com:<owner>/<repo>.git`).
- SSH key with a passphrase? `ssh-add --apple-use-keychain` and
  `UseKeychain yes` in `~/.ssh/config`, or the agent cannot push.
- A **diverged** clone (behind *and* ahead) means something wrote to GitHub
  directly, e.g. a session using the GitHub API. `git rebase origin/main`,
  resolve, trigger again.
- The tool syncs itself if listed; drop it from the list to update by hand.
- The agents appear in System Settings → Login Items as two entries named
  `bash` from an unidentified developer — expected, they are shell scripts.
  `launchctl list | grep git-autosync` shows both.
