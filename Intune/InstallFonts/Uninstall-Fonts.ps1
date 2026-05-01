<#
.SYNOPSIS
    Removes Arial Unicode MS fonts deployed by InstallFonts.ps1.

.DESCRIPTION
    Unloads each font from the GDI session, deletes its HKLM registry entry,
    removes the font file from %WINDIR%\Fonts, and broadcasts WM_FONTCHANGE so
    running apps drop the font handles.

    Designed for SYSTEM-context execution from the Intune Management Extension.

.NOTES
    Author : Oji McLeod (cmcleod1@umd.edu)
    Date   : 2026-05-01
    Version: 1.0.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---- Manifest -----------------------------------------------------------
# Must stay in sync with InstallFonts.ps1.
$fontManifest = @(
    @{ File = 'arial unicode ms.otf';      RegName = 'Arial Unicode MS (OpenType)' }
    @{ File = 'arial unicode ms bold.otf'; RegName = 'Arial Unicode MS Bold (OpenType)' }
)

# ---- Configuration ------------------------------------------------------
$destinationDir = Join-Path $env:windir       'Fonts'
$registryPath   = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$logDir         = Join-Path $env:ProgramData  'UMDLibraries\Logs'
$logFile        = Join-Path $logDir           'UninstallFonts.log'

# ---- Logging ------------------------------------------------------------
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = "[{0}][{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $logFile -Value $line
    Write-Output $line
}

# ---- P/Invoke -----------------------------------------------------------
if (-not ('UMD.FontInterop' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace UMD {
    public static class FontInterop {
        [DllImport("gdi32.dll", CharSet = CharSet.Auto)]
        public static extern int AddFontResource(string lpFileName);
        [DllImport("gdi32.dll", CharSet = CharSet.Auto)]
        public static extern int RemoveFontResource(string lpFileName);
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam,
            uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
        public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);
        public const uint WM_FONTCHANGE    = 0x001D;
        public const uint SMTO_ABORTIFHUNG = 0x0002;
    }
}
"@
}

# ---- Main ---------------------------------------------------------------
Write-Log "==== UninstallFonts started ===="

$failed = 0
foreach ($entry in $fontManifest) {
    $destPath = Join-Path $destinationDir $entry.File

    try {
        # Unload from GDI. RemoveFontResource only succeeds if the path matches
        # what AddFontResource was originally called with.
        if (Test-Path -Path $destPath -PathType Leaf) {
            [void][UMD.FontInterop]::RemoveFontResource($destPath)
            Write-Log "Unloaded: $($entry.File)"
        }

        # Remove the registry value (ignore if already absent).
        if (Get-ItemProperty -Path $registryPath -Name $entry.RegName -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $registryPath -Name $entry.RegName -Force
            Write-Log "Unregistered: $($entry.RegName)"
        }

        # Delete the file.
        if (Test-Path -Path $destPath -PathType Leaf) {
            Remove-Item -Path $destPath -Force
            Write-Log "Deleted : $destPath"
        }
    } catch {
        $failed++
        Write-Log "Failed  : $($entry.File) - $($_.Exception.Message)" 'ERROR'
    }
}

# Notify running apps.
try {
    $result = [IntPtr]::Zero
    [void][UMD.FontInterop]::SendMessageTimeout(
        [UMD.FontInterop]::HWND_BROADCAST,
        [UMD.FontInterop]::WM_FONTCHANGE,
        [IntPtr]::Zero, [IntPtr]::Zero,
        [UMD.FontInterop]::SMTO_ABORTIFHUNG, 5000, [ref]$result)
    Write-Log "Broadcast WM_FONTCHANGE."
} catch {
    Write-Log "Failed to broadcast WM_FONTCHANGE: $($_.Exception.Message)" 'WARN'
}

if ($failed -gt 0) {
    Write-Log "==== UninstallFonts completed with $failed failure(s) ====" 'ERROR'
    exit 1
}
Write-Log "==== UninstallFonts completed successfully ===="
exit 0
