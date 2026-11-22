# Briefing publishing automation

Two pieces, kept separate so each can fail or be re-run on its own. Cowork writes files. A Windows scheduled task commits and pushes them.

```
Cowork task (Mon/Thu)            Windows task (every 30 min + at logon)        GitHub
  write briefings/*.html   --->    scripts/auto_push.ps1                 --->   origin/main
  run generate_index.py            clear stale .git/*.lock                      publish.yml
                                   commit one edition per commit                (read only check)
                                   pull --rebase, push
                                   write .push_status + log
```

## Piece 1 · Generation (Cowork)

A Cowork scheduled task runs Monday and Thursday mornings. It:

1. Runs the standing briefing prompt.
2. Writes `briefings/vic_ai_briefing_YYYY-MM-DD.html` in this repo.
3. Runs `python scripts/generate_index.py` to refresh `index.html`.

The Cowork sandbox **cannot reach GitHub** (its proxy returns 403) and **cannot delete files in `.git/`**. Any `git add`, `git commit` or `git push` it attempts either fails or leaves empty `.git/*.lock` files behind. That is expected and handled by Piece 2. The Cowork run does not need to run git at all. Writing the files is enough.

The Cowork run can read `.push_status` in the repo root to report the last push in its summary (see below).

## Piece 2 · Commit and push (Windows scheduled task)

Task name: `corpdev-ai-briefing auto push`. It runs `scripts/auto_push.ps1`:

- **Triggers:** daily at 00:00, repeating every 30 minutes for 1 day (so all day, every day), plus at logon. `StartWhenAvailable` runs a missed slot right after the machine wakes. `WakeToRun` is off on purpose, because the Cowork run cannot produce files while the machine sleeps either.
- **Runs as Victoria, only while logged on** (`LogonType Interactive`). This is what lets Git Credential Manager use the stored GitHub credential. No password is stored in the task.
- **Time limit:** 10 minutes. With the settings below, auth or network problems fail in seconds, not minutes.

Each run of `auto_push.ps1`:

1. Deletes empty `*.lock` files under `.git/` older than 10 minutes, based on age alone. A non-empty stale lock is left in place and logged as `WARN`.
2. Stops with an error if the repo is mid rebase, merge, cherry-pick or revert, or is not on `main`.
3. If `briefings/` or `index.html` have uncommitted changes, re-runs `generate_index.py`, then makes one `briefing: YYYY-MM-DD` commit per new or changed edition, with `index.html` in the last one. Only `briefings/` and `index.html` are ever staged. Local edits to anything else are left alone.
4. Fetches `origin main`. If GitHub is ahead, it fast-forwards when there is nothing local to push, and otherwise runs `git pull --rebase origin main`. On a rebase conflict it runs `git rebase --abort` and logs an error, leaving local `main` as it was. There is no autostash, so nothing ends up stranded in `git stash`.
5. Pushes `main` if it is ahead of `origin/main`.
6. Writes `.push_status` and the log, and exits 0 on success or 1 on failure. The exit code shows up as `LastTaskResult`.

Git is run with `GIT_TERMINAL_PROMPT=0` and `GCM_INTERACTIVE=never`, so a missing or expired credential fails immediately and is logged instead of waiting on an invisible login window. Git's stderr output (CRLF warnings, `remote:` lines) never counts as failure. Only exit codes do.

### Status file and log

`.push_status` (repo root, gitignored) holds one line, rewritten on every run:

```
time=2026-11-22T09:30:02-05:00 result=pushed head=c0560c5 last_push=2026-11-22T09:30:02-05:00 detail="pushed 1 commit(s): briefing: 2026-11-23"
```

`result` is `pushed`, `up-to-date` or `error`. `last_push` is the last time the script itself pushed, carried forward across runs.

`%LOCALAPPDATA%\corpdev-ai-briefing\auto_push.log` gets a line for every action and always one `RESULT` line per run, including `RESULT up-to-date` when there is nothing to push. If the newest line is more than about 30 minutes old while the machine has been on, the task is not firing. The log rolls over to `auto_push.log.1` at 1 MB.

Suggested line for the Cowork prompt: *"Read `.push_status` in the repo root and include its `time`, `result` and `last_push` in the summary. If `result=error`, quote `detail`."*

### Install or repair the task

From a normal (not elevated) PowerShell in the repo root:

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_auto_push.ps1
```

It replaces any existing task with the same name, starts one run, and prints `LastTaskResult`, `NextRunTime` and the last log line. Check it at any time with:

```
Get-ScheduledTaskInfo -TaskName 'corpdev-ai-briefing auto push'
```

To remove it: `Unregister-ScheduledTask -TaskName 'corpdev-ai-briefing auto push' -Confirm:$false`

### GitHub credentials

The remote is HTTPS (`https://vg2425@github.com/vg2425/corpdev-ai-briefing.git`). Pushes use the credential Git Credential Manager (GCM) stores in Windows Credential Manager. This is the recommended setup: nothing to install, and nothing secret on disk outside Windows' own store.

If the log shows an authentication error (for example `could not read Username` or `Authentication failed`), the stored credential expired or was revoked. Refresh it once interactively, from any terminal in the repo:

```
git fetch origin
```

Sign in when GCM asks. The next task run picks up the new credential.

The alternative is SSH. Its key never expires and needs no GCM, but it means creating a key, adding it to GitHub, and either running ssh-agent or keeping a key without a passphrase on disk. It also requires changing the remote URL. It is only worth it if GCM credentials keep expiring.

## Piece 3 · GitHub Actions (read only)

`.github/workflows/publish.yml` runs on every push to `main`. It regenerates `index.html` as a sanity check and warns if the committed copy is missing editions. It never commits, so it cannot make local `main` fall behind. Optional GitHub Pages deploy steps are included but commented out. Pages from a private repo needs a paid GitHub plan.

## Troubleshooting

| Symptom | Check |
|---|---|
| New edition not on GitHub | Last lines of the log, and `.push_status`. |
| Log not updated recently | `Get-ScheduledTaskInfo` for the task. Re-run `install_auto_push.ps1`. |
| `RESULT error ... cannot pull with rebase: You have unstaged changes` | GitHub has commits that local `main` lacks, and a tracked file has local edits. Commit or stash them. The next run pushes. |
| `RESULT error rebase onto origin/main hit a conflict` | Run `git pull --rebase origin main` by hand and resolve. Usually it is `index.html`: take either side and re-run `generate_index.py`. |
| `WARN stale lock is not empty` | Make sure no git command is running, then delete the named file. |
| `RESULT error checked out branch is '...'` | `git switch main`. |
