<#
.SYNOPSIS
Removes ChemDraw 25.0.2 MSI products and their stale shortcuts.

.DESCRIPTION
Intended for the Intune native PowerShell uninstall field and SYSTEM context.
Removes both v25 MSI products, then deletes only version-25 shortcut names and
the version-25 ChemScript Start-menu folder. ChemDraw 26 shortcuts are retained.

.PARAMETER ShortcutsOnly
Skips MSI removal and cleans only known ChemDraw 25 shortcut locations.

.NOTES
Author: Oji / University of Maryland Libraries
Date: 2026-09-01
Version: 1.0.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$ShortcutsOnly)

begin {
    $ErrorActionPreference = 'Stop'
    $logRoot = 'C:\ProgramData\UMDLibraries\ChemDraw\Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
    $logPath = Join-Path $logRoot ("Remove-ChemDraw25_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $logPath -Force | Out-Null
    $script:rebootRequired = $false

    function Write-CleanupLog {
        <# .SYNOPSIS Writes a timestamped cleanup message. .NOTES Author: Oji; Version: 1.0.0 #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Message)
        Write-Output ("{0:u} {1}" -f (Get-Date), $Message)
    }

    function Test-MsiProduct {
        <# .SYNOPSIS Tests whether an MSI product code is registered. .NOTES Author: Oji; Version: 1.0.0 #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$ProductCode)
        return (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode") -or
               (Test-Path -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode")
    }

    function Invoke-MsiRemoval {
        <# .SYNOPSIS Silently removes one MSI product and verifies removal. .NOTES Author: Oji; Version: 1.0.0 #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [Parameter(Mandatory)][string]$ProductCode,
            [Parameter(Mandatory)][string]$DisplayName
        )
        if (-not (Test-MsiProduct -ProductCode $ProductCode)) {
            Write-CleanupLog "$DisplayName is not installed; skipping."
            return
        }
        $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $msiLog = Join-Path $logRoot ("Remove-{0}.msi.log" -f $ProductCode.Trim('{}'))
        if ($PSCmdlet.ShouldProcess($DisplayName, 'Uninstall MSI product')) {
            $arguments = @('/x',$ProductCode,'/qn','REBOOT=ReallySuppress','/L*v',('"{0}"' -f $msiLog))
            $process = Start-Process -FilePath $msiexec -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            Write-CleanupLog "$DisplayName uninstall exit code: $($process.ExitCode)"
            if ($process.ExitCode -in @(1641,3010)) { $script:rebootRequired = $true }
            if ($process.ExitCode -notin @(0,1605,1614,1641,3010)) { throw "$DisplayName uninstall failed with exit code $($process.ExitCode)." }
            if (Test-MsiProduct -ProductCode $ProductCode) { throw "$DisplayName remains registered after uninstall." }
        }
    }

    function Remove-StaleShortcut {
        <# .SYNOPSIS Removes one known ChemDraw 25 shortcut. .NOTES Author: Oji; Version: 1.0.0 #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([Parameter(Mandatory)][string]$Path)
        if ((Test-Path -LiteralPath $Path -PathType Leaf) -and $PSCmdlet.ShouldProcess($Path, 'Remove stale ChemDraw 25 shortcut')) {
            Remove-Item -LiteralPath $Path -Force
            Write-CleanupLog "Removed shortcut: $Path"
        }
    }
}

process {
    $exitCode = 0
    try {
        Write-CleanupLog "Starting ChemDraw 25 cleanup. ShortcutsOnly=$ShortcutsOnly"
        if (-not $ShortcutsOnly) {
            # Applications first, then the separately installed ChemDraw core MSI.
            Invoke-MsiRemoval -ProductCode '{47517D24-BB94-47FD-B4D6-9850F32C0312}' -DisplayName 'Revvity ChemDraw Applications 25.0.2 x64'
            Invoke-MsiRemoval -ProductCode '{4F50F27B-85D0-4916-85EA-4DEB5622504B}' -DisplayName 'Revvity ChemDraw 25.0.2 x64'
        }

        $shortcutNames = @(
            'ChemDraw 25.0.2 64-bit.lnk',
            'Chem3D 25.0.2 64-bit.lnk',
            'ChemFinder for Office 25.0.2 64-bit.lnk'
        )
        $programFolderName = 'ChemDraw Applications 64-bit'
        $roots = @(
            [Environment]::GetFolderPath('CommonDesktopDirectory'),
            (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) $programFolderName)
        )
        $profiles = Get-ChildItem -LiteralPath (Join-Path $env:SystemDrive 'Users') -Directory -Force -ErrorAction SilentlyContinue
        foreach ($profile in $profiles) {
            $roots += Join-Path $profile.FullName 'Desktop'
            $roots += Join-Path $profile.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\$programFolderName"
            $roots += Join-Path $profile.FullName 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
            Get-ChildItem -LiteralPath $profile.FullName -Directory -Filter 'OneDrive*' -ErrorAction SilentlyContinue |
                ForEach-Object { $roots += Join-Path $_.FullName 'Desktop' }
        }

        foreach ($root in @($roots | Where-Object { $_ } | Select-Object -Unique)) {
            foreach ($shortcutName in $shortcutNames) { Remove-StaleShortcut -Path (Join-Path $root $shortcutName) }
            $oldChemScriptFolder = Join-Path $root 'ChemScript 25.0.2 64-bit'
            if (Test-Path -LiteralPath $oldChemScriptFolder -PathType Container) {
                Get-ChildItem -LiteralPath $oldChemScriptFolder -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { Remove-StaleShortcut -Path $_.FullName }
                if (-not (Get-ChildItem -LiteralPath $oldChemScriptFolder -Force -ErrorAction SilentlyContinue)) {
                    if ($PSCmdlet.ShouldProcess($oldChemScriptFolder, 'Remove empty ChemDraw 25 Start-menu folder')) {
                        Remove-Item -LiteralPath $oldChemScriptFolder -Force
                    }
                }
            }
        }

        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class UmdShellRefresh { [DllImport("shell32.dll")] public static extern void SHChangeNotify(uint e, uint f, IntPtr a, IntPtr b); }' -ErrorAction SilentlyContinue
        [UmdShellRefresh]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
        Write-CleanupLog 'ChemDraw 25 MSI and shortcut cleanup completed.'
        if ($script:rebootRequired) { $exitCode = 3010 }
    }
    catch {
        Write-CleanupLog "ERROR: $($_.Exception.Message)"
        $exitCode = 1
    }
    finally { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
    exit $exitCode
}
