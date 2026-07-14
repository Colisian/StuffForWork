<#
.SYNOPSIS
    Uninstall stub for the RemoveMicrosoft365 Win32 app.

.DESCRIPTION
    "Uninstalling" a removal app has no meaningful action — we do not
    reinstall consumer Office. This stub exists because Intune requires an
    uninstall command for every Win32 app. It logs the invocation and
    exits 0 so uninstall assignments report success.

.NOTES
    Author  : Colin McLeod (cmcleod1@umd.edu)
    Date    : 2026-07-14
    Version : 1.0.0
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$logDir = 'C:\ProgramData\OfficeRemoval'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Add-Content -Path (Join-Path $logDir 'Uninstall.log') `
    -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Uninstall invoked - no action taken (removal apps are not reversible)."

exit 0
