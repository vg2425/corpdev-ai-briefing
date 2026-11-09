# install_auto_push.ps1
# One time setup: registers a Windows scheduled task that runs auto_push.ps1
# every 30 minutes while you are logged in. Run once from PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\install_auto_push.ps1
# To remove later:
#   Unregister-ScheduledTask -TaskName 'corpdev-ai-briefing auto push' -Confirm:$false

$script = Join-Path $PSScriptRoot 'auto_push.ps1'
$name   = 'corpdev-ai-briefing auto push'

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
# Runs as you, only when logged in, so it uses your existing Git credentials.
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Registered '$name'. Running it once now..."
Start-ScheduledTask -TaskName $name
Write-Host "Log: $env:LOCALAPPDATA\corpdev-ai-briefing\auto_push.log"
