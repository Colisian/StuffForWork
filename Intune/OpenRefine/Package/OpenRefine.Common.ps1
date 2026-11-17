function Get-OpenRefineInstallation {
    <#
    .SYNOPSIS
    Reads machine-wide OpenRefine registrations in both registry views.
    .NOTES
    Author: UMD Libraries IT
    Date: 2026-11-17
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()
    begin { $ErrorActionPreference = 'Stop' }
    process {
        $subkey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{93542BFF-1616-4802-B3EF-316F701ADC06}_is1'
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
            $base = $null
            $entry = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                $entry = $base.OpenSubKey($subkey)
                if (-not $entry) { continue }
                $version = $null
                if (-not [version]::TryParse([string]$entry.GetValue('DisplayVersion'), [ref]$version)) {
                    throw "Invalid OpenRefine DisplayVersion in $view."
                }
                $directory = [string]$entry.GetValue('InstallLocation')
                if (-not $directory) { $directory = [string]$entry.GetValue('Inno Setup: App Path') }
                $command = [string]$entry.GetValue('UninstallString')
                $uninstaller = $null
                if ($command -match '^\s*"([^"]+\.exe)"') { $uninstaller = $Matches[1] }
                elseif ($command -match '^\s*(.+?\.exe)(?:\s|$)') { $uninstaller = $Matches[1] }
                if (-not $directory -and $uninstaller) { $directory = Split-Path -Parent $uninstaller }
                if (-not $directory) { throw "Missing OpenRefine install path in $view." }
                $directory = [IO.Path]::GetFullPath($directory).TrimEnd('\')
                $exe = Join-Path $directory 'openrefine.exe'
                $java = Join-Path $directory 'server\target\jre\bin\java.exe'
                $jar = Join-Path $directory "server\target\lib\openrefine-$($version.ToString(3))-server.jar"
                [pscustomobject]@{
                    Version = $version
                    Directory = $directory
                    Uninstaller = $uninstaller
                    RegistryView = $view.ToString()
                    Complete = ((Test-Path -LiteralPath $exe -PathType Leaf) -and
                        (Test-Path -LiteralPath $java -PathType Leaf) -and
                        (Test-Path -LiteralPath $jar -PathType Leaf))
                }
            }
            finally {
                if ($entry) { $entry.Dispose() }
                if ($base) { $base.Dispose() }
            }
        }
    }
}
