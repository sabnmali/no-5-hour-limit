<#
.SYNOPSIS
    Removes the Limitless 5-Hour scheduled task.

.PARAMETER TaskName
    Name of the scheduled task. Default "Limitless5Hour".

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install\uninstall-windows.ps1
#>
[CmdletBinding()]
param(
    [string] $TaskName = 'Limitless5Hour'
)

$ErrorActionPreference = 'Stop'

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "  Scheduled task '$TaskName' is not installed - nothing to do." -ForegroundColor Yellow
    exit 0
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host "  Scheduled task '$TaskName' removed." -ForegroundColor Green
Write-Host '  Your config.env, logs/ and state/ were left untouched.'
