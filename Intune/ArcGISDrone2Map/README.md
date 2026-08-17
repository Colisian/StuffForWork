# ArcGIS Drone2Map 2026.1 — Intune Win32 App

## Package summary

| Setting | Value |
|---|---|
| Application | ArcGIS Drone2Map |
| Package version | `2026.1.0.1901` |
| MSI ProductCode | `{E4CA5C88-DD5C-4686-8070-CF6CAC6B6FDA}` |
| MSI UpgradeCode | `{A88EC12B-58F4-4B3F-BF83-1292E455C1E9}` |
| Install context | Device / SYSTEM / all users |
| Architecture | 64-bit |
| Default licensing | Named User; user changes permitted |
| Logs | `C:\ProgramData\ArcGISDrone2Map` |

The original Esri download was extracted into `Source\Drone2Map`. Packaging the MSI and CAB
files directly avoids starting the download wrapper interactively in the SYSTEM session.

## Required Intune dependencies

The requirements below were read from the bundled 2026.1 MSI and should be assigned as Win32
app dependencies before Drone2Map:

1. **Microsoft .NET Desktop Runtime 10.0.x (x64)**
2. **Microsoft Edge WebView2 Runtime 132 or later (x64, per-machine)**

Do not rely on a per-user WebView2 installation. The per-machine Drone2Map installation requires
WebView2 in the per-machine context.

## Build the `.intunewin`

From this directory, run:

```powershell
New-Item -ItemType Directory -Path .\Output -Force | Out-Null
IntuneWinAppUtil.exe -c .\Source -s Install-ArcGISDrone2Map.ps1 -o .\Output -q
```

The `-s` value is the required setup-file placeholder. The actual Intune install command invokes
the PowerShell wrapper below.

## Intune Program settings

### Method A — command line (recommended)

Install command:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-ArcGISDrone2Map.ps1
```

Uninstall command:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-ArcGISDrone2Map.ps1
```

Additional settings:

- Install behavior: **System**
- Device restart behavior: **App install may force a device restart**
- Return codes: keep `0` as success; configure `3010` as soft reboot
- Installation time required: allow at least **60 minutes** for slower devices
- Require a 64-bit operating system

### Method B — PowerShell script installer boxes

Paste the install and uninstall script contents into their respective boxes. Use the default
parameter values and configure the scripts to run in the **64-bit** PowerShell host. The source
files (`Drone2Map.msi` and both CAB files) must remain bundled in the `.intunewin` package.

## Detection rule

Use **Custom detection script** and upload:

`Source\Detect-ArcGISDrone2Map.ps1`

Set **Run script as 32-bit process on 64-bit clients** to **No**.

Detection requires both:

- `HKLM\SOFTWARE\UMD\Intune\ArcGISDrone2Map` sentinel values written after successful install
- Exact MSI registration for ProductCode `{E4CA5C88-DD5C-4686-8070-CF6CAC6B6FDA}`

## Default security and update posture

- Esri User Experience Improvement reporting: disabled
- Automatic Esri error reporting: disabled
- In-app update checks: disabled; Intune owns patching and supersedence
- No credentials, tokens, or license secrets are stored in the package
- ArcGIS Online connectivity remains available for Named User licensing

Disabling in-app update checks means the Intune app owner must monitor Esri releases and publish
superseding packages. CrowdStrike or Rapid7 may observe the large MSI extraction/install workload;
validate first in a pilot device group before broad assignment.

## Verification on a pilot device

Run in 64-bit Windows PowerShell as administrator:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{E4CA5C88-DD5C-4686-8070-CF6CAC6B6FDA}' |
    Select-Object DisplayName, DisplayVersion, Publisher

Get-ItemProperty 'HKLM:\SOFTWARE\UMD\Intune\ArcGISDrone2Map'

& .\Source\Detect-ArcGISDrone2Map.ps1
$LASTEXITCODE
```

Review these logs after install or uninstall:

```text
C:\ProgramData\ArcGISDrone2Map\Install-ArcGISDrone2Map.log
C:\ProgramData\ArcGISDrone2Map\Drone2Map-MSI-Install.log
C:\ProgramData\ArcGISDrone2Map\Uninstall-ArcGISDrone2Map.log
C:\ProgramData\ArcGISDrone2Map\Drone2Map-MSI-Uninstall.log
```

## Licensing alternatives

Method A can override the default without editing the package:

```powershell
# Let each user select licensing on first launch
.\Install-ArcGISDrone2Map.ps1 -AuthorizationType UserChoice

# Set an ArcGIS Enterprise Named User licensing portal
.\Install-ArcGISDrone2Map.ps1 -AuthorizationType NamedUser -LicenseUrl 'https://portal.example.edu'
```

The uninstall intentionally retains user projects and per-user sign-in preferences.
