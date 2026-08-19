<#
.SYNOPSIS
    Silently removes the UMD Libraries ConnectWise Access agent.

.DESCRIPTION
    Locates the currently registered MSI product by its stable ConnectWise instance
    display name and uninstalls it under the SYSTEM account. The product code is resolved
    dynamically because ConnectWise self-updates can replace the original MSI product code.

    The script accepts both supported Intune methods without modification:
      A) Command line: powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-ConnectWiseAccess.ps1
      B) Pasted into the Intune Win32 PowerShell script uninstaller box.

.EXAMPLE
    .\Uninstall-ConnectWiseAccess.ps1

    Removes the registered ConnectWise Access agent silently.

.EXAMPLE
    .\Uninstall-ConnectWiseAccess.ps1 -WhatIf

    Reports the products that would be removed without uninstalling them.

.NOTES
    Author  : Oji McLeod - ITFO / Digital Services & Technologies, UMD Libraries
    Date    : 2026-08-18
    Version : 1.0.0
    Exit    : 0 = success/already absent, 3010 = success/reboot required, 1 = failure
#>
[CmdletBinding(SupportsShouldProcess)]
param()

begin {
    function Get-ConnectWiseAccessProduct {
    <#
    .SYNOPSIS
        Gets registered MSI products for the UMD Libraries ConnectWise Access agent.

    .PARAMETER DisplayName
        Exact Add/Remove Programs display name to locate.

    .NOTES
        Author  : Oji McLeod - ITFO / Digital Services & Technologies, UMD Libraries
        Date    : 2026-08-18
        Version : 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $uninstallRoots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
    }

    process {
        foreach ($uninstallRoot in $uninstallRoots) {
            if (-not (Test-Path -LiteralPath $uninstallRoot)) { continue }

            Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $product = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                    if ($product.DisplayName -eq $DisplayName) {
                        $product
                    }
                }
        }
    }
    }

    $ErrorActionPreference = 'Stop'
    $script:result = 1
    $script:transcriptStarted = $false

    $componentRoot = 'C:\ProgramData\ConnectWiseAccess'
    if (-not (Test-Path -LiteralPath $componentRoot)) {
        New-Item -Path $componentRoot -ItemType Directory -Force | Out-Null
    }

    Start-Transcript -Path (Join-Path $componentRoot 'Uninstall-ConnectWiseAccess.log') -Append | Out-Null
    $script:transcriptStarted = $true

    $expectedDisplayName = 'ScreenConnect Client (f81fbe41367f771e)'
    $expectedServiceName = 'ScreenConnect Client (f81fbe41367f771e)'
}

process {
    try {
        Write-Output "[$(Get-Date -Format s)] ConnectWise Access removal starting."

        $registeredProducts = @(
            Get-ConnectWiseAccessProduct -DisplayName $expectedDisplayName |
                Sort-Object PSChildName -Unique
        )

        if ($registeredProducts.Count -eq 0) {
            $installedService = Get-Service -Name $expectedServiceName -ErrorAction SilentlyContinue
            if ($installedService) {
                throw "Service '$expectedServiceName' exists, but no matching MSI registration was found."
            }

            Write-Output 'ConnectWise Access is already absent.'
            $script:result = 0
            return
        }

        $rebootRequired = $false
        $actionSkipped = $false

        foreach ($registeredProduct in $registeredProducts) {
            $productCode = $registeredProduct.PSChildName
            if ($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
                throw "Unexpected MSI product code '$productCode' for '$expectedDisplayName'."
            }

            if (-not $PSCmdlet.ShouldProcess("$expectedDisplayName $($registeredProduct.DisplayVersion)", "Uninstall MSI $productCode")) {
                Write-Output "ShouldProcess declined for $productCode."
                $actionSkipped = $true
                continue
            }

            $safeProductCode = $productCode.Trim('{}')
            $nativeLog = Join-Path $componentRoot "ConnectWiseAccess-MSI-Uninstall-$safeProductCode.log"
            $msiArguments = @(
                '/x'
                $productCode
                '/qn'
                '/norestart'
                '/l*v'
                "`"$nativeLog`""
            )

            $installerProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArguments -Wait -PassThru
            $installerExitCode = $installerProcess.ExitCode
            Write-Output "Windows Installer exit code for $productCode`: $installerExitCode"

            switch ($installerExitCode) {
                0     { }
                1605  { Write-Output "$productCode is already absent from Windows Installer." }
                1641  { $rebootRequired = $true }
                3010  { $rebootRequired = $true }
                default {
                    throw "ConnectWise Access removal failed with exit code $installerExitCode. See '$nativeLog'."
                }
            }
        }

        if ($actionSkipped) {
            $script:result = 0
            return
        }

        if ($rebootRequired) {
            Write-Output 'ConnectWise Access removal completed; a restart is required.'
            $script:result = 3010
            return
        }

        $remainingProducts = @(Get-ConnectWiseAccessProduct -DisplayName $expectedDisplayName)
        $remainingService = Get-Service -Name $expectedServiceName -ErrorAction SilentlyContinue
        if ($remainingProducts.Count -gt 0 -or $remainingService) {
            throw 'Removal returned success, but the ConnectWise MSI registration or service is still present.'
        }

        Write-Output 'ConnectWise Access removed successfully.'
        $script:result = 0
    }
    catch {
        Write-Output "ERROR: $($_.Exception.Message)"
        Write-Output $_.ScriptStackTrace
        $script:result = 1
    }
}

end {
    Write-Output "[$(Get-Date -Format s)] Exiting with code $script:result"
    if ($script:transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
    exit $script:result
}
