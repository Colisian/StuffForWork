<#
.SYNOPSIS
    Silently installs Foxit PDF Reader from the Foxit multi-language Setup Bootstrapper.

.DESCRIPTION
    Wraps FoxitPDFReader.exe (Foxit Setup Bootstrapper 2026.1.2.36540) for Intune Win32
    deployment. The bootstrapper unpacks Setup.msi (2025.2.0.33046), applies Setup.msp to
    bring the product to 2026.1.2.36540, and applies the selected language transform.

    Designed to run non-interactively as SYSTEM. Transcript is written to
    C:\ProgramData\FoxitReader\Install-FoxitReader.log and the native Foxit installer log
    to C:\ProgramData\FoxitReader\foxit_setup.log.

    Authored for dual-method Intune use:
      A) Command line: powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-FoxitReader.ps1
      B) Pasted into the Intune Win32 "PowerShell script installer" box (no edits required).

    IMPORTANT - the parameter defaults ARE the intended UMD Libraries build, because method B
    has no command line and therefore cannot receive arguments. Running this script with no
    parameters at all produces: desktop shortcut created, uninstall survey suppressed, English
    UI, internet features left enabled. Every switch below opts OUT of that baseline, so a
    pasted copy and a bare command-line call behave identically.

.PARAMETER NoDesktopShortcut
    Passes /noshortcut so no desktop shortcut is created. By default a shortcut IS created
    (MSI property DESKTOP_SHORTCUT=1), which is the desired UMD Libraries behaviour.

.PARAMETER DisableInternet
    Passes /DisableInternet, which turns off every feature requiring an outbound connection
    (auto-update check, ConnectedPDF, cloud storage plug-ins, telemetry). Recommended for
    lab and kiosk builds where Intune owns the patch cycle.

.PARAMETER EnableUninstallSurvey
    Re-enables Foxit's uninstall survey. By default the survey is suppressed
    (/DISABLE_UNINSTALL_SURVEY) so no browser window opens when the product is removed.

.PARAMETER Language
    /lang value. Defaults to English. Set to another shipped language (Deutsch, Nederlands,
    Italiano, ...) to override, or to an empty string to let the bootstrapper choose from the
    OS locale.

.PARAMETER ExtraArguments
    Additional raw switches appended verbatim to the bootstrapper command line.

.EXAMPLE
    .\Install-FoxitReader.ps1

    Standard UMD Libraries build. Identical to the pasted-script deployment.

.EXAMPLE
    .\Install-FoxitReader.ps1 -DisableInternet -NoDesktopShortcut

    Lab/kiosk build: no desktop shortcut, no outbound Foxit traffic.

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu) - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-12
    Version : 1.1.0
    Exit    : 0 = success, 3010 = success/reboot required, 1 = failure

    1.1.0 - Defaults reworked to be paste-safe: survey switch inverted to -EnableUninstallSurvey,
            -Language now defaults to English.
    1.0.0 - Initial release.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$NoDesktopShortcut,
    [switch]$DisableInternet,
    [switch]$EnableUninstallSurvey,
    [string]$Language = 'English',
    [string[]]$ExtraArguments
)

begin {
    $ErrorActionPreference = 'Stop'

    $componentRoot = 'C:\ProgramData\FoxitReader'
    if (-not (Test-Path -LiteralPath $componentRoot)) {
        New-Item -Path $componentRoot -ItemType Directory -Force | Out-Null
    }
    Start-Transcript -Path (Join-Path $componentRoot 'Install-FoxitReader.log') -Append | Out-Null

    # $PSScriptRoot is empty when the script is pasted into Intune, but the working directory
    # is the unpacked package either way. Never rely on $PSScriptRoot alone.
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}

process {
    try {
        Write-Output "[$(Get-Date -f s)] Foxit PDF Reader install starting. ScriptDir='$scriptDir'"

        $setup = Get-ChildItem -LiteralPath $scriptDir -Filter 'FoxitPDFReader*.exe' -File |
                 Sort-Object Length -Descending |
                 Select-Object -First 1
        if (-not $setup) {
            throw "Foxit bootstrapper (FoxitPDFReader*.exe) not found in '$scriptDir'."
        }
        Write-Output "Installer  : $($setup.FullName)"
        Write-Output "FileVersion: $($setup.VersionInfo.FileVersion)"

        # /quiet is the bootstrapper's silent switch. It suppresses reboot internally by
        # stripping the SuppressReboot custom action and setting MSIRESTARTMANAGERCONTROL,
        # so /norestart is neither needed nor documented by the bootstrapper.
        # Defaults are the intended build (see .NOTES): shortcut on, survey off, English.
        $argList = @('/quiet', '/log', "`"$componentRoot\foxit_setup.log`"")
        if ($NoDesktopShortcut)       { $argList += '/noshortcut' }
        if ($DisableInternet)         { $argList += '/DisableInternet' }
        if (-not $EnableUninstallSurvey) { $argList += '/DISABLE_UNINSTALL_SURVEY' }
        if ($Language)                { $argList += @('/lang', $Language) }
        if ($ExtraArguments)          { $argList += $ExtraArguments }

        Write-Output "Arguments  : $($argList -join ' ')"

        if (-not $PSCmdlet.ShouldProcess($setup.FullName, 'Install Foxit PDF Reader silently')) {
            Write-Output 'ShouldProcess declined - nothing installed.'
            return
        }

        $proc = Start-Process -FilePath $setup.FullName -ArgumentList $argList -Wait -PassThru
        $code = $proc.ExitCode
        Write-Output "Bootstrapper exit code: $code"

        switch ($code) {
            0     { Write-Output 'Install succeeded.';                       $script:result = 0 }
            3010  { Write-Output 'Install succeeded - reboot required.';     $script:result = 3010 }
            1641  { Write-Output 'Install succeeded - reboot initiated.';    $script:result = 3010 }
            default {
                throw "Foxit bootstrapper returned non-success exit code $code. See $componentRoot\foxit_setup.log."
            }
        }
    }
    catch {
        Write-Output "ERROR: $($_.Exception.Message)"
        Write-Output $_.ScriptStackTrace
        $script:result = 1
    }
}

end {
    if ($null -eq $script:result) { $script:result = 0 }
    Write-Output "[$(Get-Date -f s)] Exiting with code $script:result"
    try { Stop-Transcript | Out-Null } catch { }
    exit $script:result
}
