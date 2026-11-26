<#
  Registers a Windows scheduled task that runs Sync-ConvrgeForever.ps1 at
  logon and every few minutes, so the addon folder follows main on GitHub.

  Run from an elevated (Administrator) PowerShell, because the WoW folder is
  under Program Files:
    powershell -ExecutionPolicy Bypass -File .\Install-AutoUpdate.ps1
  Remove it again:
    powershell -ExecutionPolicy Bypass -File .\Install-AutoUpdate.ps1 -Uninstall
#>
#Requires -RunAsAdministrator
param(
    [string]$AddonDir = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ConvrgeForever',
    [int]$Minutes = 10,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$TaskName = 'ConvrgeForever Auto-Update'
$StateDir = Join-Path $env:LOCALAPPDATA 'ConvrgeForever-Sync'
$Script   = Join-Path $StateDir 'Sync-ConvrgeForever.ps1'

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed scheduled task '$TaskName'. Log and state are left in $StateDir."
    return
}

# Keep a copy outside the download folder so the task survives it being moved.
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'Sync-ConvrgeForever.ps1') -Destination $Script -Force

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`" -AddonDir `"$AddonDir`""

$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"),
    (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $Minutes))
)

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "Installed '$TaskName': checks GitHub at logon and every $Minutes minutes."
Write-Host "Addon folder: $AddonDir"
Write-Host "Log: $StateDir\sync.log"
