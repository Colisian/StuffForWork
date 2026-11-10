<#
.SYNOPSIS
Validates SysAid scripts with isolated fixtures and mocked endpoint changes; never installs the agent.
.NOTES
Author: UMD Libraries IT / Codex
Date: 2026-11-10
Version: 1.0.0
Run with Windows PowerShell 5.1 and Pester 3 or later. Test registry data is isolated under HKCU.
#>
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$testId = [guid]::NewGuid().ToString()
$testArtifactsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Artifacts'))
$testDir = Join-Path $testArtifactsRoot $testId
$registryRelative = 'SOFTWARE\UMDLibraries\SysAidTests\' + $testId
$registryRoot = 'HKCU:\' + $registryRelative
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$testSid = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + ':(OI)(CI)F'
& icacls.exe $testDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' $testSid | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Test directory ACL failed.' }
try {
    Describe 'SysAid source validation' {
        It 'parses all new PowerShell scripts in Windows PowerShell 5.1' {
            $files = @(Get-ChildItem -LiteralPath (Join-Path $projectDir 'Source') -Filter '*.ps1')
            $files += Get-Item -LiteralPath (Join-Path $projectDir 'Build-SysAidIntunePackage.ps1'), (Join-Path $projectDir 'New-SysAidTransform.ps1')
            foreach ($file in $files) {
                $tokens = $null; $parseErrors = $null
                [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
                $parseErrors.Count | Should Be 0
            }
        }
        It 'keeps the original reviewed MSI unchanged and signed' {
            $metadata = Get-Content -LiteralPath (Join-Path $projectDir 'Package-Metadata.json') -Raw | ConvertFrom-Json
            (Get-FileHash -LiteralPath (Join-Path $projectDir $metadata.MsiFile)).Hash | Should Be $metadata.MsiSha256
            (Get-AuthenticodeSignature -LiteralPath (Join-Path $projectDir $metadata.MsiFile)).Status | Should Be 'Valid'
        }
        It 'creates a transform with ACCOUNTID and applies it to an MSI database without installing' {
            $configFile = Join-Path $testDir 'Fixture.json'
            @{ ServerUrl = 'https://fixture.invalid'; AccountId = "fixture'account"; Serial = 'TEST-ONLY-DO-NOT-DEPLOY' } |
                ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8
            $msiPath = Join-Path $projectDir 'SysAidAgentx64_WIX.msi'
            $mstPath = Join-Path $testDir 'Fixture.mst'
            & (Join-Path $projectDir 'New-SysAidTransform.ps1') -MsiPath $msiPath -ConfigPath $configFile -OutputPath $mstPath
            $installer = New-Object -ComObject WindowsInstaller.Installer
            $copyPath = Join-Path $testDir 'Fixture.msi'
            Copy-Item -LiteralPath $msiPath -Destination $copyPath
            $database = $installer.OpenDatabase($copyPath, 1)
            try {
                $database.ApplyTransform($mstPath, 0)
                foreach ($name in @('ACCOUNTID', 'SERVERURL', 'SERIAL', 'MsiHiddenProperties')) {
                    $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$name'")
                    $view.Execute(); $record = $view.Fetch()
                    $value = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
                    switch ($name) {
                        'ACCOUNTID' { $value | Should Be "fixture'account" }
                        'SERVERURL' { $value | Should Be 'https://fixture.invalid' }
                        'SERIAL' { $value | Should Be 'TEST-ONLY-DO-NOT-DEPLOY' }
                        'MsiHiddenProperties' { $value | Should Match '(^|;)SERIAL(;|$)' }
                    }
                    $view.Close()
                    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) | Out-Null
                    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) | Out-Null
                }
            } finally {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($database) | Out-Null
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) | Out-Null
            }
        }
    }
    Describe 'SysAid installer return codes and verification' {
        BeforeEach {
            $global:sysAidFixture = @{ Installed = $false; ExitCode = 0; WrongAccount = $false; StartFails = $false }
            $global:sysAidFakeConfig = '{"MsiFile":"Fixture.msi","MsiSha256":"test","TransformSha256":"test","MinimumVersion":"24.4.60.68","ServerUrl":"https://ticketing.lib.umd.edu","AccountId":"umlibraryitd","PackageRevision":1}'
            $source = Get-Content -LiteralPath (Join-Path $projectDir 'Source\Install-SysAidAgent.ps1') -Raw
            # Only the elevation check is bypassed in this test copy. Every endpoint mutation is mocked.
            $source = $source.Replace('if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))', 'if ($false)')
            $script:installFixture = Join-Path $testDir 'Install-Fixture.ps1'
            Set-Content -LiteralPath $installFixture -Value $source -Encoding UTF8
            Mock Get-Content { $global:sysAidFakeConfig } -ParameterFilter { $LiteralPath -like '*Deployment.json' }
            Mock Get-FileHash { [pscustomobject]@{ Hash = 'test' } }
            Mock Test-Path { $global:sysAidFixture.Installed } -ParameterFilter { $LiteralPath -eq 'HKLM:\SOFTWARE\SysAid\InstalledProducts\SysAid' }
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*WOW6432Node*' }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SysAidAgent.exe' }
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'HKLM:\SOFTWARE\UMDLibraries\SysAidAgent' }
            Mock Get-ItemProperty { [pscustomobject]@{ DisplayVersion = '24.4.60.68'; ServerURL = 'https://ticketing.lib.umd.edu'; AccountID = $(if ($global:sysAidFixture.WrongAccount) { 'different' } else { 'umlibraryitd' }); InstallLocation = 'C:\Program Files\SysAid' } }
            Mock Get-Service {
                if ($global:sysAidFixture.Installed) {
                    $service = [pscustomobject]@{ Status = 'Running' }
                    $service | Add-Member ScriptMethod WaitForStatus { param($Status, $Timeout) }
                    $service
                }
            }
            Mock Start-Process { if ($global:sysAidFixture.ExitCode -in @(0, 3010)) { $global:sysAidFixture.Installed = $true }; [pscustomobject]@{ ExitCode = $global:sysAidFixture.ExitCode } }
            Mock Start-Service { if ($global:sysAidFixture.StartFails) { throw 'Fixture service start failure' } }
            Mock Set-Service {}
            Mock Set-ItemProperty {}
            Mock New-Item {}
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Write-Error {}
            Mock icacls.exe { $global:LASTEXITCODE = 0 }
        }
        It 'returns 0 only after successful install verification and completion marker' {
            & $installFixture | Out-Null
            $LASTEXITCODE | Should Be 0
            Assert-MockCalled Set-ItemProperty -Times 4 -Exactly -Scope It
        }
        It 'preserves MSI retry code 1618 without writing a completion marker' {
            $global:sysAidFixture.ExitCode = 1618
            & $installFixture | Out-Null
            $LASTEXITCODE | Should Be 1618
            Assert-MockCalled Set-ItemProperty -Times 0 -Exactly -Scope It
        }
        It 'preserves MSI reboot code 3010 when the service needs a reboot' {
            $global:sysAidFixture.ExitCode = 3010; $global:sysAidFixture.StartFails = $true
            & $installFixture -WarningAction SilentlyContinue | Out-Null
            $LASTEXITCODE | Should Be 3010
            Assert-MockCalled Set-ItemProperty -Times 4 -Exactly -Scope It
        }
        It 'reports failure and does not mark an MSI failure complete' {
            $global:sysAidFixture.ExitCode = 1603
            & $installFixture | Out-Null
            $LASTEXITCODE | Should Be 1
            Assert-MockCalled Set-ItemProperty -Times 0 -Exactly -Scope It
        }
        It 'refuses an existing installation enrolled in another account' {
            $global:sysAidFixture.Installed = $true; $global:sysAidFixture.WrongAccount = $true
            & $installFixture | Out-Null
            $LASTEXITCODE | Should Be 1
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        }
        It 'makes no endpoint changes with WhatIf' {
            & $installFixture -WhatIf | Out-Null
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-ItemProperty -Times 0 -Exactly -Scope It
            Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
        }
    }
    Describe 'SysAid uninstaller safety and return codes' {
        BeforeEach {
            $global:sysAidRemovalFixture = @{ Product = $true; Removed = $false; ExitCode = 0 }
            $source = Get-Content -LiteralPath (Join-Path $projectDir 'Source\Uninstall-SysAidAgent.ps1') -Raw
            $source = $source.Replace('if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))', 'if ($false)')
            $script:uninstallFixture = Join-Path $testDir 'Uninstall-Fixture.ps1'
            Set-Content -LiteralPath $uninstallFixture -Value $source -Encoding UTF8
            Mock Get-ChildItem { if ($global:sysAidRemovalFixture.Product) { [pscustomobject]@{ PSPath = 'HKLM:\FixtureProduct' } } } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            Mock Get-ItemProperty { [pscustomobject]@{
                DisplayName = 'SysAid Agent'; Publisher = 'SysAid'; WindowsInstaller = 1
                PSChildName = '{18D93098-07C7-46E6-97DB-188335C3EB3F}'; PSPath = 'HKLM:\FixtureProduct'
            } }
            Mock Test-Path {
                if ($LiteralPath -like '*WOW6432Node*') { return $false }
                if ($LiteralPath -eq 'HKLM:\FixtureProduct') { return (-not $global:sysAidRemovalFixture.Removed) }
                return $true
            } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            Mock Get-Service {
                if ($global:sysAidRemovalFixture.Product -and -not $global:sysAidRemovalFixture.Removed) { [pscustomobject]@{ Status = 'Running' } }
            }
            Mock Start-Process {
                if ($global:sysAidRemovalFixture.ExitCode -in @(0, 1605, 1614)) { $global:sysAidRemovalFixture.Removed = $true }
                [pscustomobject]@{ ExitCode = $global:sysAidRemovalFixture.ExitCode }
            }
            Mock New-Item {}
            Mock Remove-Item {}
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Write-Error {}
            Mock icacls.exe { $global:LASTEXITCODE = 0 }
        }
        It 'removes the MSI by GUID and clears the marker after verification' {
            & $uninstallFixture | Out-Null
            $LASTEXITCODE | Should Be 0
            Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $ArgumentList -like '/x {18D93098-07C7-46E6-97DB-188335C3EB3F}*' }
            Assert-MockCalled Remove-Item -Times 1 -Exactly -Scope It
        }
        It 'returns 0 if the agent is already absent' {
            $global:sysAidRemovalFixture.Product = $false
            & $uninstallFixture | Out-Null
            $LASTEXITCODE | Should Be 0
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        }
        It 'preserves retry code 1618 and the completion marker' {
            $global:sysAidRemovalFixture.ExitCode = 1618
            & $uninstallFixture | Out-Null
            $LASTEXITCODE | Should Be 1618
            Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
        }
        It 'preserves reboot code 3010 even if removal is pending a restart' {
            $global:sysAidRemovalFixture.ExitCode = 3010
            & $uninstallFixture | Out-Null
            $LASTEXITCODE | Should Be 3010
        }
        It 'reports failure and retains the marker for an MSI uninstall failure' {
            $global:sysAidRemovalFixture.ExitCode = 1603
            & $uninstallFixture | Out-Null
            $LASTEXITCODE | Should Be 1
            Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
        }
        It 'does not remove anything with WhatIf' {
            & $uninstallFixture -WhatIf | Out-Null
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
            Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
        }
    }
    Describe 'SysAid detection against isolated user registry fixtures' {
        BeforeEach {
            $script:agentPath = Join-Path $registryRoot 'Agent'
            $script:markerPath = Join-Path $registryRoot 'Marker'
            New-Item -Path $agentPath, $markerPath -Force | Out-Null
            foreach ($path in @($agentPath, $markerPath)) {
                Set-ItemProperty -LiteralPath $path -Name ServerUrl -Value 'https://ticketing.lib.umd.edu'
                Set-ItemProperty -LiteralPath $path -Name AccountId -Value 'umlibraryitd'
            }
            Set-ItemProperty -LiteralPath $agentPath -Name DisplayVersion -Value '24.4.60.68'
            Set-ItemProperty -LiteralPath $agentPath -Name InstallLocation -Value $testDir
            Set-ItemProperty -LiteralPath $markerPath -Name PackageRevision -Value 1
            Set-Content -LiteralPath (Join-Path $testDir 'SysAidAgent.exe') -Value 'Non-executable test fixture'
            $detection = Get-Content -LiteralPath (Join-Path $projectDir 'Intune\Detect-SysAidAgent.ps1') -Raw
            $detection = $detection.Replace("::OpenBaseKey('LocalMachine', 'Registry64')", "::OpenBaseKey('CurrentUser', 'Registry64')")
            $detection = $detection.Replace('SOFTWARE\SysAid\InstalledProducts\SysAid', ($registryRelative + '\Agent')).Replace('SOFTWARE\UMDLibraries\SysAidAgent', ($registryRelative + '\Marker'))
            $script:detectionFixture = Join-Path $testDir 'Detect-Fixture.ps1'
            Set-Content -LiteralPath $detectionFixture -Value $detection -Encoding UTF8
            Mock Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        }
        It 'detects the configured agent even when the service is temporarily stopped' {
            $output = @(& $detectionFixture)
            $LASTEXITCODE | Should Be 0
            $output.Count | Should Be 1
        }
        It 'accepts a newer agent after a SysAid-managed update' {
            Set-ItemProperty -LiteralPath $agentPath -Name DisplayVersion -Value '25.1.0.0'
            & $detectionFixture | Out-Null
            $LASTEXITCODE | Should Be 0
        }
        It 'rejects another server with no success output' {
            Set-ItemProperty -LiteralPath $agentPath -Name ServerUrl -Value 'https://wrong.invalid'
            $output = @(& $detectionFixture)
            $LASTEXITCODE | Should Be 1
            $output.Count | Should Be 0
        }
        It 'rejects an older agent' {
            Set-ItemProperty -LiteralPath $agentPath -Name DisplayVersion -Value '23.1.0.0'
            & $detectionFixture | Out-Null
            $LASTEXITCODE | Should Be 1
        }
        It 'rejects missing completion markers' {
            Remove-Item -LiteralPath $markerPath -Recurse -Force
            & $detectionFixture | Out-Null
            $LASTEXITCODE | Should Be 1
        }
        It 'rejects a missing agent executable' {
            Remove-Item -LiteralPath (Join-Path $testDir 'SysAidAgent.exe') -Force
            & $detectionFixture | Out-Null
            $LASTEXITCODE | Should Be 1
        }
    }
} finally {
    Remove-Variable -Name sysAidFixture, sysAidFakeConfig, sysAidRemovalFixture -Scope Global -ErrorAction SilentlyContinue
    if ($registryRoot.StartsWith('HKCU:\SOFTWARE\UMDLibraries\SysAidTests\')) {
        if (Test-Path -LiteralPath $registryRoot) { Remove-Item -LiteralPath $registryRoot -Recurse -Force }
    }
    $resolvedTest = [IO.Path]::GetFullPath($testDir)
    if ($resolvedTest.StartsWith(($testArtifactsRoot + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $resolvedTest) { Remove-Item -LiteralPath $resolvedTest -Recurse -Force }
    }
}
