<#
.SYNOPSIS
    Silently removes every installed Foxit PDF Reader product.

.DESCRIPTION
    Resolves the installed ProductCode(s) from the stable Foxit PDF Reader UpgradeCode
    {9D148992-FACF-4107-84A3-C48F19CF0B57} and removes them with msiexec. This survives
    version changes, because the ProductCode is rebuilt each release but the UpgradeCode
    is not.

    Falls back to the bundled bootstrapper (FoxitPDFReader*.exe /uninstall /quiet) when no
    MSI registration can be resolved, and finally to any registered QuietUninstallString.

    Designed to run non-interactively as SYSTEM. Logs to
    C:\ProgramData\FoxitReader\Uninstall-FoxitReader.log.

    Authored for dual-method Intune use:
      A) Command line: powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-FoxitReader.ps1
      B) Pasted into the Intune Win32 "PowerShell script installer" box (no edits required).

.PARAMETER RemoveUserData
    Also delete user data and Foxit registry state. Uses msiexec property CLEAN=1 and the
    bootstrapper's /clean switch. Destructive - user preferences and stamps are lost.

.EXAMPLE
    .\Uninstall-FoxitReader.ps1

.EXAMPLE
    .\Uninstall-FoxitReader.ps1 -RemoveUserData

.NOTES
    Author  : Oji McLeod (cmcleod1@umd.edu) - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-12
    Version : 1.0.0
    Exit    : 0 = removed (or already absent), 3010 = removed/reboot required, 1 = failure
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveUserData
)

begin {
    $ErrorActionPreference = 'Stop'

    $componentRoot = 'C:\ProgramData\FoxitReader'
    if (-not (Test-Path -LiteralPath $componentRoot)) {
        New-Item -Path $componentRoot -ItemType Directory -Force | Out-Null
    }
    Start-Transcript -Path (Join-Path $componentRoot 'Uninstall-FoxitReader.log') -Append | Out-Null

    $scriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $upgradeCode = '{9D148992-FACF-4107-84A3-C48F19CF0B57}'

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    function Get-FoxitReaderInstall {
        foreach ($root in $uninstallRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if ($p.DisplayName -like 'Foxit PDF Reader*' -or $p.DisplayName -like 'Foxit Reader*') {
                    [pscustomobject]@{
                        DisplayName            = $p.DisplayName
                        DisplayVersion         = $p.DisplayVersion
                        ProductCode            = $_.PSChildName
                        QuietUninstallString   = $p.QuietUninstallString
                        UninstallString        = $p.UninstallString
                    }
                }
            }
        }
    }
}

process {
    try {
        Write-Output "[$(Get-Date -f s)] Foxit PDF Reader uninstall starting. ScriptDir='$scriptDir'"

        # Ask Windows Installer which ProductCodes are related to the stable UpgradeCode.
        $productCodes = @()
        try {
            $wi = New-Object -ComObject WindowsInstaller.Installer
            $related = $wi.GetType().InvokeMember(
                'RelatedProducts', 'GetProperty', $null, $wi, @($upgradeCode))
            foreach ($pc in $related) { $productCodes += $pc }
        }
        catch {
            Write-Output "UpgradeCode lookup returned nothing: $($_.Exception.Message)"
        }
        finally {
            if ($wi) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wi) }
        }

        $registered = @(Get-FoxitReaderInstall)
        if (-not $productCodes -and $registered) {
            # Fall back to ARP-registered GUID-shaped keys.
            $productCodes = @($registered | Where-Object { $_.ProductCode -match '^\{[0-9A-Fa-f\-]{36}\}$' } |
                              Select-Object -ExpandProperty ProductCode -Unique)
        }

        if (-not $productCodes -and -not $registered) {
            Write-Output 'Foxit PDF Reader is not installed. Nothing to do.'
            $script:result = 0
            return
        }

        foreach ($r in $registered) {
            Write-Output "Found: $($r.DisplayName) $($r.DisplayVersion) [$($r.ProductCode)]"
        }

        $script:result = 0
        $removedAny    = $false

        foreach ($code in ($productCodes | Select-Object -Unique)) {
            if (-not $PSCmdlet.ShouldProcess($code, 'Uninstall via msiexec')) { continue }

            $msiArgs = @('/x', $code, '/qn', '/norestart',
                         '/l*v', "`"$componentRoot\foxit_uninstall.log`"")
            if ($RemoveUserData) { $msiArgs += 'CLEAN=1' }

            Write-Output "Running: msiexec.exe $($msiArgs -join ' ')"
            $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
            $code2 = $proc.ExitCode
            Write-Output "msiexec exit code: $code2"

            switch ($code2) {
                0    { $removedAny = $true }
                3010 { $removedAny = $true; $script:result = 3010 }
                1641 { $removedAny = $true; $script:result = 3010 }
                1605 { Write-Output 'Product not installed (1605) - treating as removed.'; $removedAny = $true }
                default { throw "msiexec failed removing $code with exit code $code2." }
            }
        }

        # Fallback: bundled bootstrapper, then QuietUninstallString.
        if (-not $removedAny) {
            $setup = Get-ChildItem -LiteralPath $scriptDir -Filter 'FoxitPDFReader*.exe' -File -ErrorAction SilentlyContinue |
                     Sort-Object Length -Descending | Select-Object -First 1
            if ($setup -and $PSCmdlet.ShouldProcess($setup.FullName, 'Uninstall via bootstrapper')) {
                $bArgs = @('/uninstall', '/quiet', '/DISABLE_UNINSTALL_SURVEY',
                           '/log', "`"$componentRoot\foxit_uninstall.log`"")
                if ($RemoveUserData) { $bArgs += '/clean' }
                Write-Output "Running: $($setup.Name) $($bArgs -join ' ')"
                $proc = Start-Process -FilePath $setup.FullName -ArgumentList $bArgs -Wait -PassThru
                Write-Output "Bootstrapper exit code: $($proc.ExitCode)"
                if ($proc.ExitCode -in 0, 3010, 1641) {
                    $removedAny = $true
                    if ($proc.ExitCode -ne 0) { $script:result = 3010 }
                }
            }
        }

        if (-not $removedAny) {
            throw 'Foxit PDF Reader is registered but no uninstall method succeeded.'
        }

        if (@(Get-FoxitReaderInstall).Count -gt 0) {
            Write-Output 'WARNING: a Foxit PDF Reader registration is still present after uninstall.'
        }
        Write-Output 'Uninstall completed.'
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
