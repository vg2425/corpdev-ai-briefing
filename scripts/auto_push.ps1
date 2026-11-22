<#
auto_push.ps1

Commits briefing files that the Cowork run wrote but could not commit, then
pushes main to origin. The Cowork sandbox cannot reach GitHub and cannot
delete files in .git/, so the git work happens here, on Windows.

Run by the scheduled task 'corpdev-ai-briefing auto push' every 30 minutes
and at logon (see install_auto_push.ps1). Safe to run by hand at any time:

    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\auto_push.ps1

Every run:
  * appends to %LOCALAPPDATA%\corpdev-ai-briefing\auto_push.log and always
    ends with one "RESULT" line, so a task that stopped firing is obvious
  * rewrites .push_status in the repo root (gitignored) with one line:
    time, result, HEAD, time of the last push this script made, detail
  * exits 0 on success (pushed, or already up to date) and 1 on failure,
    which shows up as LastTaskResult on the scheduled task

Only briefings/ and index.html are ever staged or committed. Local edits to
scripts, docs or anything else are left alone.
#>

[CmdletBinding()]
param(
    # Empty *.lock files older than this are treated as left over by the
    # Cowork sandbox and deleted.
    [int]$LockAgeMinutes = 10
)

$ErrorActionPreference = 'Stop'

$Branch     = 'main'
$Remote     = 'origin'
$Repo       = Split-Path -Parent $PSScriptRoot
$GitDir     = Join-Path $Repo '.git'
$StatusFile = Join-Path $Repo '.push_status'
$LogDir     = Join-Path $env:LOCALAPPDATA 'corpdev-ai-briefing'
$LogFile    = Join-Path $LogDir 'auto_push.log'

# Fail fast instead of hanging on a credential prompt nobody can see.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE     = 'never'

# Abort network operations that stall (under 1 KB/s for 60 s).
$NetOpts = @('-c', 'http.lowSpeedLimit=1000', '-c', 'http.lowSpeedTime=60')

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) {
    Move-Item -LiteralPath $LogFile -Destination "$LogFile.1" -Force
}

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Format-OneLine([string]$Text, [int]$MaxLines = 4) {
    $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notlike 'hint:*' } | Select-Object -Last $MaxLines)
    ($lines -join ' | ') -replace '"', "'"
}

# Runs git without letting stderr turn into a PowerShell error. Git writes
# progress and warnings (CRLF notices, "remote:" lines) to stderr even when
# it succeeds, so success is judged by the exit code alone.
function Invoke-Git {
    $ErrorActionPreference = 'Continue'
    $output = & git -C $Repo @args 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{
        Code   = $LASTEXITCODE
        Output = (@($output) -join "`n").Trim()
    }
}

# Same, but throws with git's own message when the exit code is not 0.
function Invoke-GitChecked {
    $r = Invoke-Git @args
    if ($r.Code -ne 0) {
        $cmd = ($args | Where-Object { $_ -notlike 'http.*' -and $_ -ne '-c' }) -join ' '
        throw "git $cmd exited $($r.Code): $(Format-OneLine $r.Output)"
    }
    $r.Output
}

# Paths under briefings/ and index.html that differ from HEAD, including
# untracked files.
function Get-PendingPaths {
    $out = Invoke-GitChecked -c core.quotepath=off status --porcelain=v1 --untracked-files=all '--' briefings index.html
    @($out -split "`n" | Where-Object { $_.Length -gt 3 } | ForEach-Object {
        $p = $_.Substring(3)
        if ($p -like '* -> *') { $p = ($p -split ' -> ')[-1] }
        $p.Trim('"')
    })
}

function Update-Index {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) {
        Write-Log 'WARN python not found; committing index.html as the Cowork run left it'
        return
    }
    $ErrorActionPreference = 'Continue'
    $out = & $py.Source (Join-Path $Repo 'scripts\generate_index.py') 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Log "WARN generate_index.py exited $LASTEXITCODE; committing index.html as the Cowork run left it: $(Format-OneLine ($out -join "`n"))"
    } else {
        Write-Log 'Regenerated index.html'
    }
}

# Stages and commits only the given paths, leaving anything else that
# happens to be staged alone. Returns $false if there was nothing to commit.
function Save-Commit([string]$Message, [string[]]$Paths) {
    Invoke-GitChecked add -A '--' @Paths | Out-Null
    if ((Invoke-Git diff --cached --quiet '--' @Paths).Code -eq 0) { return $false }
    Invoke-GitChecked commit --quiet -m $Message --only '--' @Paths | Out-Null
    Write-Log "Committed '$Message'"
    return $true
}

function Write-PushStatus([string]$Result, [string]$Detail) {
    $now  = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    $head = (Invoke-Git rev-parse --short HEAD).Output
    $lastPush = 'none'
    if (Test-Path $StatusFile) {
        $m = [regex]::Match([IO.File]::ReadAllText($StatusFile), 'last_push=(\S+)')
        if ($m.Success) { $lastPush = $m.Groups[1].Value }
    }
    if ($Result -eq 'pushed') { $lastPush = $now }
    $line = 'time={0} result={1} head={2} last_push={3} detail="{4}"' -f $now, $Result, $head, $lastPush, (Format-OneLine $Detail)
    [IO.File]::WriteAllText($StatusFile, $line + "`n")
}

# One run at a time, even if the task and a manual run overlap.
$mutex = New-Object System.Threading.Mutex($false, 'Local\corpdev-ai-briefing-auto-push')
try { $haveMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $haveMutex = $true }
if (-not $haveMutex) {
    Write-Log 'RESULT skipped: another run is in progress'
    exit 0
}

$exitCode = 0
try {
    Set-Location -LiteralPath $Repo
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is not on PATH' }

    # 1. Clear lock files the Cowork sandbox created but could not delete.
    #    Decided on age alone: no git operation here holds a lock for minutes.
    $cutoff = (Get-Date).AddMinutes(-$LockAgeMinutes)
    $locks = @(Get-ChildItem -LiteralPath $GitDir -Recurse -Force -File -Filter '*.lock' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff })
    foreach ($lock in $locks) {
        $rel = $lock.FullName.Substring($Repo.Length + 1)
        if ($lock.Length -gt 0) {
            Write-Log "WARN stale lock is not empty, left in place: $rel ($($lock.Length) bytes, $($lock.LastWriteTime))"
            continue
        }
        try {
            Remove-Item -LiteralPath $lock.FullName -Force
            Write-Log "Removed stale lock $rel (dated $($lock.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
        } catch {
            Write-Log "WARN could not remove $rel : $($_.Exception.Message)"
        }
    }

    # 2. Leave the repo alone if it is mid-operation or on another branch.
    foreach ($marker in 'rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD') {
        if (Test-Path (Join-Path $GitDir $marker)) {
            throw "a git operation is in progress (.git/$marker); finish or abort it by hand"
        }
    }
    $current = (Invoke-Git symbolic-ref --quiet --short HEAD).Output
    if ($current -ne $Branch) { throw "checked out branch is '$current', not '$Branch'; nothing committed or pushed" }

    # 3. Commit briefing output the Cowork run could not commit: one commit
    #    per edition, with index.html in the last one.
    $pending = Get-PendingPaths
    if ($pending.Count -gt 0) {
        if ($pending | Where-Object { $_ -like 'briefings/*' }) { Update-Index }
        $editions = @($pending | ForEach-Object {
            if ($_ -match '^briefings/vic_ai_briefing_(\d{4}-\d{2}-\d{2})\.html$' -and (Test-Path -LiteralPath (Join-Path $Repo $_))) {
                [pscustomobject]@{ Path = $_; Date = $Matches[1] }
            }
        } | Sort-Object Date)
        for ($i = 0; $i -lt $editions.Count - 1; $i++) {
            Save-Commit "briefing: $($editions[$i].Date)" @($editions[$i].Path) | Out-Null
        }
        $lastMessage = if ($editions.Count -gt 0) { "briefing: $($editions[-1].Date)" } else { 'briefing: update index (auto)' }
        Save-Commit $lastMessage @('briefings', 'index.html') | Out-Null
    }

    # 4. Sync with GitHub and push.
    Invoke-GitChecked @NetOpts fetch --quiet $Remote $Branch | Out-Null
    $ahead  = [int](Invoke-GitChecked rev-list --count "$Remote/$Branch..HEAD")
    $behind = [int](Invoke-GitChecked rev-list --count "HEAD..$Remote/$Branch")

    if ($behind -gt 0 -and $ahead -eq 0) {
        # Nothing local to replay: fast-forward. Unlike pull --rebase, this
        # works with unrelated local edits in the working tree.
        Invoke-GitChecked merge --ff-only --quiet "$Remote/$Branch" | Out-Null
        Write-Log "Fast-forwarded to $Remote/$Branch ($behind new remote commit(s))"
    }
    elseif ($behind -gt 0) {
        # No autostash on purpose: a failed autostash pop is what left the
        # old stash@{0} behind. A dirty tree is reported instead.
        $r = Invoke-Git @NetOpts pull --rebase --quiet $Remote $Branch
        if ($r.Code -ne 0) {
            if ((Test-Path (Join-Path $GitDir 'rebase-merge')) -or (Test-Path (Join-Path $GitDir 'rebase-apply'))) {
                Invoke-Git rebase --abort | Out-Null
                throw "rebase onto $Remote/$Branch hit a conflict and was aborted; local main is unchanged, resolve by hand: $(Format-OneLine $r.Output)"
            }
            throw "git pull --rebase exited $($r.Code): $(Format-OneLine $r.Output)"
        }
        Write-Log "Rebased onto $Remote/$Branch ($behind new remote commit(s))"
        $ahead = [int](Invoke-GitChecked rev-list --count "$Remote/$Branch..HEAD")
    }

    if ($ahead -eq 0) {
        $result = 'up-to-date'
        $detail = "nothing to push; $Remote/$Branch matches HEAD"
    } else {
        $subjects = (Invoke-GitChecked log --reverse --format=%s "$Remote/$Branch..HEAD") -split "`n"
        Invoke-GitChecked @NetOpts push --quiet $Remote "HEAD:refs/heads/$Branch" | Out-Null
        $result = 'pushed'
        $detail = "pushed $ahead commit(s): $($subjects -join '; ')"
    }

    Write-PushStatus $result $detail
    Write-Log "RESULT $result head=$((Invoke-Git rev-parse --short HEAD).Output) $detail"
}
catch {
    $exitCode = 1
    $msg = $_.Exception.Message
    Write-Log "RESULT error $msg"
    try { Write-PushStatus 'error' $msg } catch { Write-Log "WARN could not write .push_status: $($_.Exception.Message)" }
}
finally {
    $mutex.ReleaseMutex()
}
exit $exitCode
