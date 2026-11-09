# auto_push.ps1
# Pushes any unpushed briefing commits in this repo to origin/main.
# Runs on Windows (outside the Claude sandbox, which cannot reach GitHub).
# Safe to run repeatedly: does nothing if there is nothing to push.

$ErrorActionPreference = 'Stop'
$repo   = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $env:LOCALAPPDATA 'corpdev-ai-briefing'
$log    = Join-Path $logDir 'auto_push.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Add-Content -Path $log
}

try {
    Set-Location $repo

    # The sandbox leaves empty lock files it cannot delete. Clear them only
    # if they are stale (older than 2 minutes) and no git process is running.
    $gitRunning = Get-Process git -ErrorAction SilentlyContinue
    if (-not $gitRunning) {
        Get-ChildItem -Path (Join-Path $repo '.git') -Recurse -Force -Filter '*.lock' -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -eq 0 -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-2) } |
            ForEach-Object { Remove-Item $_.FullName -Force; Log "Removed stale lock $($_.FullName)" }
    }

    # Commit anything the run wrote but could not commit (e.g. a lock blocked it).
    $dirty = git status --porcelain
    if ($dirty) {
        git add -A
        git commit -m "briefing: $(Get-Date -Format 'yyyy-MM-dd') (auto)" | Out-Null
        Log "Committed uncommitted changes"
    }

    git fetch origin main --quiet
    $ahead = [int](git rev-list --count origin/main..HEAD)
    if ($ahead -eq 0) { exit 0 }

    git push origin main --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git push exited $LASTEXITCODE" }
    Log "Pushed $ahead commit(s)"
}
catch {
    Log "ERROR: $_"
    exit 1
}
