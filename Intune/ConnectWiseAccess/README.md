# ConnectWise Access — Intune Win32 Package

## Package contents

```text
ConnectWiseAccess/
├── Source/
│   ├── ScreenConnect.ClientSetup.msi
│   ├── Install-ConnectWiseAccess.ps1
│   ├── Uninstall-ConnectWiseAccess.ps1
│   └── Detect-ConnectWiseAccess.ps1
├── Output/
└── README.md
```

The bundled MSI is the UMD Libraries instance-specific Access agent:

- Product: `ScreenConnect Client (f81fbe41367f771e)`
- Package version: `26.4.3.9662`
- Product code: `{33143B60-ADC0-D411-4224-40773C2F862B}`
- Upgrade code: `{DEE813CA-1A58-192F-F81F-BE41367F771E}`
- SHA-256: `462D1EE9994B028908A07D91613C2CDA78A83F30440A030EC50D41792B31B864`
- Service: `ScreenConnect Client (f81fbe41367f771e)`

The MSI contains its relay enrollment configuration and the organizational properties
`McKeldin Library`, `MCK`, and `GIS LAB - Shared`. Treat the MSI and resulting
`.intunewin` as restricted administrative software; do not publish either in a public
repository or broadly accessible share.

## Build the `.intunewin`

Run from the directory containing `IntuneWinAppUtil.exe`. Keep `Output` outside `Source`
so a previous `.intunewin` is never included in a later package.

```powershell
$packageRoot = 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\ConnectWiseAccess'

.\IntuneWinAppUtil.exe `
    -c (Join-Path $packageRoot 'Source') `
    -s 'Install-ConnectWiseAccess.ps1' `
    -o (Join-Path $packageRoot 'Output') `
    -q
```

For script-driven installations, `-s` is a required packaging placeholder. Using the
install wrapper as the setup entry point prevents Intune from treating the vendor MSI as
the app's direct installer while still bundling the MSI alongside all PowerShell scripts.

## Intune app configuration

Create a **Windows app (Win32)** and upload the generated `.intunewin`.

### Program

Install command — Method A, recommended:

```text
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-ConnectWiseAccess.ps1
```

Uninstall command:

```text
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-ConnectWiseAccess.ps1
```

PowerShell upload — Method B, confirmed in the current Intune tenant UI:

- Installer type: **PowerShell script**
- Install script: upload `Source\Install-ConnectWiseAccess.ps1`
- Uninstaller type: **PowerShell script**
- Uninstall script: upload `Source\Uninstall-ConnectWiseAccess.ps1`

Both scripts are authored for the upload workflow without modification and are well below
Intune's 50 KB script limit. The command-line fields above are not used when the matching
PowerShell script types are selected.

- Install behavior: **System**
- Device restart behavior: **No specific action**
- Success codes: `0`, `3010`

The wrappers normalize Windows Installer code `1641` to Intune's soft-reboot code `3010`.

Logs are written under `C:\ProgramData\ConnectWiseAccess`.

### Requirements

- Operating system architecture: select the architecture used by the lab fleet
- Minimum operating system: match the currently supported lab Windows baseline
- The MSI accepts .NET Framework 2.0 or .NET Framework 4.x; supported Windows 10/11
  lab images normally satisfy this with .NET Framework 4.x.

### Detection rule

Use **Custom detection script** and upload `Source\Detect-ConnectWiseAccess.ps1`.

- Run script as 32-bit process on 64-bit clients: **No**
- Enforce script signature check: follow the tenant's current script-signing policy

The rule requires the instance-specific service and version `26.4.3.9662` or newer.
It does not hardcode the MSI product code because ConnectWise self-updates can change it.

### Assignment

1. Assign as **Required** to a small pilot device group of two to five lab PCs.
2. Verify ConnectWise console placement and remote connectivity.
3. Expand the assignment to the production lab-PC device group.
4. Exclude any device groups that use a different ConnectWise organizational mapping.

## Verification commands

Validate the source before packaging:

```powershell
$source = 'C:\Users\cmcleod1\OneDrive - University of Maryland\Documents\Work\StuffForWork\Intune\ConnectWiseAccess\Source'

Get-FileHash -LiteralPath (Join-Path $source 'ScreenConnect.ClientSetup.msi') -Algorithm SHA256
Get-AuthenticodeSignature -LiteralPath (Join-Path $source 'ScreenConnect.ClientSetup.msi')
powershell.exe -ExecutionPolicy Bypass -NoProfile -File (Join-Path $source 'Install-ConnectWiseAccess.ps1') -WhatIf
```

After a pilot installation:

```powershell
Get-Service -Name 'ScreenConnect Client (f81fbe41367f771e)'

& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -ExecutionPolicy Bypass `
    -NoProfile `
    -File '.\Detect-ConnectWiseAccess.ps1'
```

Expected detection output resembles:

```text
Detected: ConnectWise Access 26.4.3.9662
```

Coordinate the pilot with the CrowdStrike/Rapid7 owners. The Access agent installs a
remote-administration service, Backstage components, and a Windows credential provider,
all of which may generate security telemetry.

When replacing the MSI with a future build, update the expected version and SHA-256 in
`Install-ConnectWiseAccess.ps1`, the minimum version in `Detect-ConnectWiseAccess.ps1`,
and the package metadata in this runbook before rebuilding the `.intunewin`.
