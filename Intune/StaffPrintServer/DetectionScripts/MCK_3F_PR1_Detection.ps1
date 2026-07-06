<#
.SYNOPSIS
    Detection script for MCK_3F_PR1 printer (registry-based).

.DESCRIPTION
    Detects whether the MCK_3F_PR1 per-user printer connection exists by checking the
    user's registry hive instead of Get-Printer. Intune Win32 detection scripts always
    run as SYSTEM, and Get-Printer under SYSTEM cannot see per-user printer connections
    created by Add-Printer -ConnectionName - the registry key below is the authoritative
    record of the connection and is readable from any context.
    Returns exit code 0 if the printer connection exists, 1 if not found.

.NOTES
    Printer Name: MCK_3F_PR1
    Print Server: LIBRPS403v.ad.umd.edu
    Key checked:  <user hive>\Printers\Connections\,,LIBRPS403v.ad.umd.edu,MCK_3F_PR1
#>

$PrinterName   = "MCK_3F_PR1"
$PrintServer   = "LIBRPS403v.ad.umd.edu"
$connectionKey = ",,$PrintServer,$PrinterName"

try {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        # Running as SYSTEM (Intune Win32 detection) - resolve the logged-on user's SID
        $consoleUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        if (-not $consoleUser) {
            # Fall back to the owner of an explorer.exe process (e.g. RDP sessions)
            $explorer = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
                Where-Object UserName | Select-Object -First 1
            if ($explorer) { $consoleUser = $explorer.UserName }
        }
        if (-not $consoleUser) {
            # No user session - cannot evaluate a per-user connection yet.
            # Exit 1 so the user-context install runs at next user logon.
            Write-Host "NOT DETECTED: No user logged on; per-user printer state unknown"
            exit 1
        }
        $sid = ([System.Security.Principal.NTAccount]$consoleUser).Translate(
            [System.Security.Principal.SecurityIdentifier]).Value
        $keyPath = "Registry::HKEY_USERS\$sid\Printers\Connections\$connectionKey"
    } else {
        # Running as a user - check our own hive
        $keyPath = "Registry::HKEY_CURRENT_USER\Printers\Connections\$connectionKey"
    }

    if (Test-Path -LiteralPath $keyPath) {
        Write-Host "SUCCESS: Printer connection '$PrinterName' is installed"
        exit 0  # Detected
    } else {
        Write-Host "NOT FOUND: Printer connection '$PrinterName' is not installed for the current user"
        exit 1  # Not detected
    }
} catch {
    Write-Host "ERROR: Failed to detect printer '$PrinterName': $($_.Exception.Message)"
    exit 1  # Not detected
}