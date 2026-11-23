# Handoff: fix the auto push for corpdev-ai-briefing

Paste this whole file into Claude Code, opened at the repo root:
`C:\Users\VictoriaGeh\Documents\Github\corpdev-ai-briefing`

## Goal

New briefings should reach `origin/main` on GitHub with no manual steps. Right now they do not, and I have been pushing by hand.

## How the pipeline is supposed to work

1. A Cowork scheduled task runs Monday and Thursday mornings. It writes `briefings/vic_ai_briefing_YYYY-MM-DD.html`, runs `python scripts/generate_index.py`, and tries `git add / commit / push`. It runs in a Linux sandbox that **cannot reach GitHub** (proxy 403) and **cannot delete files in `.git/`**, so it often leaves empty `.git/*.lock` files behind.
2. A Windows scheduled task, `corpdev-ai-briefing auto push`, is meant to run `scripts/auto_push.ps1` every 30 minutes. That script clears stale locks, commits anything uncommitted and pushes. It was installed with `scripts/install_auto_push.ps1`.
3. `.github/workflows/publish.yml` runs on push. It is read only (a sanity check on `index.html`) and does not commit, so it should not cause divergence.

## Evidence it is broken (as of Nov 22 2026)

- `.git/HEAD.lock` (dated Nov 12) and `.git/index.lock` (dated Nov 16) still exist. Both are 0 bytes. If `auto_push.ps1` had run successfully even once since then, it would have deleted them.
- Local `main` is 1 commit ahead of `origin/main` (`a697bf0 briefing: 2026-11-12`), so nothing has been pushed since at least Nov 12.
- `briefings/vic_ai_briefing_2026-11-16.html` is staged but not committed. `briefings/vic_ai_briefing_2026-11-19.html` and `index.html` are modified but not committed.
- `git stash list` shows a leftover `stash@{0}: autostash`. It appears to come from the old `.bat` flow. `scripts/auto_push.log` (May 17) shows an autostash conflict.
- There are two competing push scripts: `scripts/auto_push.bat` (legacy, logs to `scripts/auto_push.log`, last entry May 17) and `scripts/auto_push.ps1` (current, logs to `%LOCALAPPDATA%\corpdev-ai-briefing\auto_push.log`, which the sandbox cannot read).
- The remote is HTTPS with a username (`https://vg2425@github.com/...`), so pushes rely on Git Credential Manager.

## Likely causes (unverified, check each)

1. **The task is not registered or never fires.** Possible reasons: the install script was never run, registration failed, or the trigger is bad. `-Once` with a `RepetitionDuration` of 3650 days is known to fail or be rejected on some Windows builds. The task uses `LogonType Interactive`, so it only runs while I am logged in.
2. **The task fires but the script throws early.** Possible reasons:
   - `$ErrorActionPreference = 'Stop'` with git writing to stderr can raise a NativeCommandError in Windows PowerShell 5.1.
   - `Remove-Item` on the locks fails because of permissions on files the sandbox created.
   - `Get-Process git` finds some long running git process (VS Code, GitHub Desktop), so locks are never cleared and every later git command fails.
3. **The push hangs on a credential prompt.** Git Credential Manager may try to show a login UI in a hidden, non interactive session, which hits the 5 minute execution limit.

## What I want you to do

### 1. Diagnose before changing anything

- `Get-ScheduledTask -TaskName 'corpdev-ai-briefing auto push'` and `Get-ScheduledTaskInfo` for that task. Report the trigger definition, `LastRunTime`, `LastTaskResult` and `NextRunTime`.
- Read `%LOCALAPPDATA%\corpdev-ai-briefing\auto_push.log` if it exists.
- Run `scripts/auto_push.ps1` in the foreground and capture the output. Tell me which of the causes above (or another one) is the real failure.

### 2. Recover the current backlog

- Confirm no git process is running, then delete the stale `.git/*.lock` files.
- Inspect `stash@{0}`. If it only holds an old `index.html` timestamp change, drop it. Otherwise show me the contents before doing anything.
- Make one commit per edition: `briefing: 2026-11-16` and `briefing: 2026-11-19`, each with its HTML file. Regenerate `index.html` with `python scripts/generate_index.py` and include it in the last commit.
- `git pull --rebase origin main`, then push.
- Verify that `origin/main` contains the Nov 12, Nov 16 and Nov 19 editions.

### 3. Harden `scripts/auto_push.ps1`

- Do not let git's stderr throw. Check `$LASTEXITCODE` after each native git call and log real failures.
- Log every run, including "nothing to push", so a dead task is obvious from the log.
- Set `GIT_TERMINAL_PROMPT=0` and `GCM_INTERACTIVE=never` so auth problems fail fast and get logged instead of hanging. Make sure a credential is stored for non interactive use: either a cached GCM credential, or switch the remote to SSH with a key. Recommend one and explain the tradeoff briefly.
- Lock cleanup: delete 0 byte `*.lock` files older than 10 minutes based on age alone. Drop the "no git process at all" condition, or narrow it to git processes whose working directory is this repo.
- Before pushing, run `git pull --rebase origin main`, and handle a rebase conflict by aborting and logging.
- Write a one line status file, `.push_status` in the repo root, containing the timestamp, result and HEAD SHA. Add it to `.gitignore`. The Cowork briefing run can read this file and report the last successful push in its summary.

### 4. Fix the scheduled task registration

- Rewrite `scripts/install_auto_push.ps1` with triggers that reliably repeat:
  - a Daily trigger repeating every 30 minutes for 1 day
  - an AtLogOn trigger
  - `StartWhenAvailable`
  - `WakeToRun` if reasonable
- Keep the task running as me so it uses my Git credentials. Do not store my password.
- Re-register the task, trigger one run with `Start-ScheduledTask`, and show me the log line it produced.

### 5. Clean up

- Delete `scripts/auto_push.bat` and the old `scripts/auto_push.log`, or move them to `scripts/legacy/`. There should be one push path.
- Update `README.md` and `docs/AUTOMATION.md` so they describe the real flow: Cowork writes files, and the Windows task commits and pushes.
- Commit these changes and push.

## Acceptance criteria

- `origin/main` on GitHub shows the Nov 12, Nov 16 and Nov 19 editions and an up to date `index.html`.
- The scheduled task shows `LastTaskResult` 0 and a `NextRunTime` within 30 minutes.
- No `.git/*.lock` files remain.
- Test: create a dummy uncommitted file and lock file, wait for (or manually start) the task, and confirm it commits, pushes and logs success. Then remove the dummy commit with a revert and push again.
- `.push_status` exists and shows success.

## Constraints

- Do not force push and do not rewrite published history.
- Do not change the briefing HTML content or `generate_index.py` output format.
- Ask before changing the git remote URL or anything in my global git or credential config.
