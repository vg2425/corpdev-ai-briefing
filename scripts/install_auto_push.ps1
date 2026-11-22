<#
install_auto_push.ps1

Registers (or re-registers) the Windows scheduled task that runs
auto_push.ps1. Run it once from a normal, non-elevated PowerShell:

    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_auto_push.ps1

It is safe to run again; the task is replaced, not duplicated.

The task:
  * runs every 30 minutes, all day, every day (a Daily trigger at 00:00
    that repeats every 30 minutes for 1 day)
  * also runs when you log on
  * catches up on a missed run as soon as the machine is available again
    (StartWhenAvailable), e.g. after sleep
  * runs as you, only while you are logged on, so git can use the GitHub
    credential that Git Credential Manager already stores for you. No
    password is stored in the task.

To remove it:
    Unregister-ScheduledTask -TaskName 'corpdev-ai-briefing auto push' -Confirm:$false
#>

$ErrorActionPreference = 'Stop'

$TaskName = 'corpdev-ai-briefing auto push'
$Repo     = Split-Path -Parent $PSScriptRoot
$Script   = Join-Path $PSScriptRoot 'auto_push.ps1'
$User     = [Security.Principal.WindowsIdentity]::GetCurrent().Name   # e.g. AzureAD\you
$LogFile  = Join-Path $env:LOCALAPPDATA 'corpdev-ai-briefing\auto_push.log'

$action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`"" `
    -WorkingDirectory $Repo

# Every 30 minutes, around the clock. New-ScheduledTaskTrigger cannot put a
# repetition on a Daily trigger directly, so borrow it from a -Once trigger.
$every30 = New-ScheduledTaskTrigger -Daily -At '00:00'
$every30.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration (New-TimeSpan -Days 1)).Repetition

$atLogOn = New-ScheduledTaskTrigger -AtLogOn -User $User

# WakeToRun is deliberately off: the Cowork run that produces new files
# cannot run while the machine sleeps either, and StartWhenAvailable already
# runs a missed push right after wake.
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

# Interactive: runs in your logon session, which is what lets Git Credential
# Manager read your stored GitHub credential without a password in the task.
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($every30, $atLogOn) `
    -Settings $settings -Principal $principal -Force `
    -Description 'Commits briefing files written by the Cowork run and pushes main to GitHub. See docs/AUTOMATION.md.' |
    Out-Null

Write-Host "Registered '$TaskName' for $User. Starting one run now..."
Start-ScheduledTask -TaskName $TaskName

$deadline = (Get-Date).AddMinutes(3)
do {
    Start-Sleep -Seconds 2
    $state = (Get-ScheduledTask -TaskName $TaskName).State
} while ($state -eq 'Running' -and (Get-Date) -lt $deadline)

$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host ("LastRunTime {0}  LastTaskResult {1}  NextRunTime {2}" -f $info.LastRunTime, $info.LastTaskResult, $info.NextRunTime)
if (Test-Path $LogFile) {
    Write-Host "Last log line ($LogFile):"
    Get-Content $LogFile -Tail 1
}
