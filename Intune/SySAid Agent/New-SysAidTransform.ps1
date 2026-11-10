<#
.SYNOPSIS
Creates a SysAid MSI transform from a local configuration file without installing anything.
.NOTES
Author: UMD Libraries IT / Codex
Date: 2026-11-10
Version: 1.0.0
The transform contains the enrollment serial. Restrict access to it and the configuration.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$MsiPath,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$OutputPath
)
begin { $ErrorActionPreference = 'Stop' }
end {
    $temporaryDir = $null
    $original = $null
    $modified = $null
    $installer = $null
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        foreach ($name in @('ServerUrl', 'AccountId', 'Serial')) {
            $value = [string]$config.$name
            if ([string]::IsNullOrWhiteSpace($value) -or $value -match '(?i)REPLACE_|please update|your sysaid') {
                throw "Set $name in the local configuration file."
            }
            if ($value -match '[\x00-\x1F]') { throw "Control characters are not allowed in $name." }
        }
        $serverUri = [uri]$config.ServerUrl
        if (-not $serverUri.IsAbsoluteUri -or $serverUri.Scheme -ne 'https' -or $serverUri.UserInfo) {
            throw 'ServerUrl must be an absolute HTTPS URL without embedded credentials.'
        }
        $msiFullPath = (Resolve-Path -LiteralPath $MsiPath).Path
        $outputFullPath = [IO.Path]::GetFullPath($OutputPath)
        if (-not $PSCmdlet.ShouldProcess($outputFullPath, 'Generate SysAid enrollment transform')) { return }
        $buildRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Build'))
        $temporaryDir = Join-Path $buildRoot ('Transform-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $temporaryDir -Force | Out-Null
        $builderSid = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + ':(OI)(CI)F'
        & icacls.exe $temporaryDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' $builderSid | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not restrict access to the temporary transform directory.' }
        $temporaryMsi = Join-Path $temporaryDir 'Working.msi'
        Copy-Item -LiteralPath $msiFullPath -Destination $temporaryMsi
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $original = $installer.OpenDatabase($msiFullPath, 0)
        $modified = $installer.OpenDatabase($temporaryMsi, 1)
        # Reflection also works under PowerShell 7, which does not expose these indexed COM properties directly.
        $properties = [ordered]@{
            ACCOUNTID = [string]$config.AccountId
            SERVERURL = [string]$config.ServerUrl
            SERIAL = [string]$config.Serial
            MsiHiddenProperties = 'SERIAL;NEWSERIAL;SERVERPROXYPASSWORD;NEWSERVERPROXYPASSWORD;SERVERPROXYPASSWORDENCODED'
        }
        foreach ($name in $properties.Keys) {
            $view = $modified.OpenView("SELECT ``Property``,``Value`` FROM ``Property`` WHERE ``Property``='$name'")
            $view.Execute()
            $record = $view.Fetch()
            if ($record) {
                $record.GetType().InvokeMember('StringData', 'SetProperty', $null, $record, @(2, $properties[$name])) | Out-Null
                $view.Modify(2, $record) # msiViewModifyUpdate
            } else {
                $record = $installer.CreateRecord(2)
                $record.GetType().InvokeMember('StringData', 'SetProperty', $null, $record, @(1, $name)) | Out-Null
                $record.GetType().InvokeMember('StringData', 'SetProperty', $null, $record, @(2, $properties[$name])) | Out-Null
                $view.Modify(1, $record) # msiViewModifyInsert
            }
            $view.Close()
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) | Out-Null
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) | Out-Null
        }
        $modified.Commit()
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputFullPath) -Force | Out-Null
        if (Test-Path -LiteralPath $outputFullPath) { Remove-Item -LiteralPath $outputFullPath -Force }
        $modified.GenerateTransform($original, $outputFullPath) | Out-Null
        # Product, language, and all three MSI version fields must match the original package.
        $modified.CreateTransformSummaryInfo($original, $outputFullPath, 0, 291)
        if (-not (Test-Path -LiteralPath $outputFullPath)) { throw 'The transform was not created.' }
    } catch {
        # Do not echo COM exceptions: they can include SQL/property data containing the enrollment serial.
        throw 'SysAid transform creation failed. Check configuration, file access, and MSI identity. No enrollment values were printed.'
    } finally {
        foreach ($comObject in @($modified, $original, $installer)) {
            if ($null -ne $comObject) { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject) | Out-Null }
        }
        if ($temporaryDir -and (Test-Path -LiteralPath $temporaryDir)) {
            $resolvedTemporary = [IO.Path]::GetFullPath($temporaryDir)
            if ($resolvedTemporary.StartsWith(($buildRoot + '\Transform-'), [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
            }
        }
    }
}
