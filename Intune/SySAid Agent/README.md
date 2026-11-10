# SysAid Windows Agent Intune Deployment

Deploy the SysAid Windows x64 agent through an Intune Win32 app, starting with a small device pilot. The package targets `https://ticketing.lib.umd.edu` and account `umlibraryitd`.

The configured package is built locally. Successful installation proves the agent is present and configured; confirm asset check-in separately in SysAid before expanding the deployment.

## Table of Contents

- [[#Deployment Files]]
- [[#Intune App Setup]]
- [[#Pilot and Verification]]
- [[#Network and Security]]
- [[#Troubleshooting]]
- [[#Uninstall and Rollback]]
- [[#Rebuilding and Updating]]
- [[#Validation and Sources]]

---

## Deployment Files
> [[#Table of Contents|↑ Back to TOC]]

| Item | Location or value |
|---|---|
| Upload package | `Build\Output\Install-SysAidAgent.intunewin` in this project folder |
| Detection script to upload | `Intune\Detect-SysAidAgent.ps1` in this project folder |
| Install and uninstall scripts | `Source\Install-SysAidAgent.ps1`, `Source\Uninstall-SysAidAgent.ps1` |
| Staged package contents | `Build\Source` in this project folder |
| Local build configuration | `Build\BuildConfig.json` in this project folder |
| Build hashes and metadata | `Build\Output\Build-Manifest.json` in this project folder |
| Endpoint deployment logs | `C:\ProgramData\UMDLibraries\SysAid` |
| Reviewed MSI | `SysAidAgentx64_WIX.msi`, version `24.4.60.68`, x64 |
| Product code | `{18D93098-07C7-46E6-97DB-188335C3EB3F}` |
| MSI SHA256 | `8A3A973ACA0689C4965E4ED4C0EA5C8B52A78ECAE3B173FC8F6A263910CEB55F` |

The MSI has a valid SysAid Technologies signature. Its enrollment fields originally contain placeholders. The generated transform supplies `ACCOUNTID`, `SERVERURL`, and `SERIAL` without modifying the original signed MSI. **This MSI uses `ACCOUNTID`; the general vendor guide calls the field `ACCOUNT`.**

The staged source contains only the two deployment scripts, MSI, transform, and public deployment metadata. The serial is stored in the build configuration and transform, rather than in PowerShell code or the installation command line. Build configuration, transform, output, and review images are organized under this project folder. The populated `Build` folder is excluded from Git and retains restricted local access; it is inside OneDrive and subject to that folder's synchronization and sharing settings.

The original `install.cmd`, `uninstall.cmd`, `Configure-SysAid.ps1`, and root-level `Detect-SysAidAgent.ps1` are retained as reference. Use the new `Source` scripts and `Intune` detection script. The original installer references missing files; its uninstall command uses WMIC.

---

## Intune App Setup
> [[#Table of Contents|↑ Back to TOC]]

In the Intune admin center, create **Windows app (Win32)** and upload the package listed above.

### Method A Command line

This is the default deployment method. The scripts are versioned inside the package.

**Install command:**

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install-SysAidAgent.ps1
```

**Uninstall command:**

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Uninstall-SysAidAgent.ps1
```

Both scripts automatically enter 64-bit Windows PowerShell if Intune starts a 32-bit host. They require no PowerShell 7 installation.

| Setting | Value |
|---|---|
| Name | UMD Libraries SysAid Agent |
| Publisher | SysAid Technologies LTD |
| Install behavior | System |
| Installation time | 30 minutes |
| Device restart behavior | Determine behavior based on return codes |
| Allow available uninstall | No |
| Architecture | x64 only; exclude x86 and ARM64 |
| Minimum OS | Select the supported Windows 11 release baseline for your fleet |
| Dependencies | None added by these wrappers |
| Assignments | Required to a Windows pilot **device** group first |

The vendor installer determines its prerequisites. The wrapper does not automatically enable legacy .NET features. Confirm the chosen agent release is compatible with your SysAid server before broad deployment.

| Return code | Intune type | Meaning |
|---|---|---|
| 0 | Success | Installation or removal completed |
| 1 | Failed | Validation, configuration, or installer failure; inspect logs |
| 3010 | Soft reboot | Restart required; verify service after restarting |
| 1618 | Retry | Another MSI installation is running |

### Detection

Choose **Use a custom detection script** and upload the generated `Intune\Detect-SysAidAgent.ps1`.

- **Run script as 32-bit process on 64-bit clients:** No.
- **Enforce script signature check:** No for the supplied unsigned script, or sign it with your approved certificate before requiring signature validation.

Detection requires the completion marker, expected server/account, version `24.4.60.68` or later, agent executable, and service registration. It emits one success line with exit 0; otherwise it exits 1 without success output. It deliberately accepts a temporarily stopped service, so routine service restarts do not trigger repeated application installs. Service health belongs in verification or a separate Remediation.

Upload this custom script even if Intune offers an automatically inferred MSI rule. A product-code-only rule cannot verify the enrollment target or completion marker.

### Method B PowerShell script installer

Use the same `.intunewin`. Select the PowerShell script installer option and supply the complete contents of `Source\Install-SysAidAgent.ps1`; use `Source\Uninstall-SysAidAgent.ps1` for removal. Depending on the portal, this is an upload or script editor. Configure 64-bit execution where offered.

Both scripts are below 50 KB and locate bundled files through the script directory or extracted package working directory. The transform and metadata remain bundled files; neither the serial nor the MSI belongs in the script editor. Use the same System context, return codes, requirements, and custom detection as Method A.

Reference: [Microsoft Intune Win32 app setup](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32).

---

## Pilot and Verification
> [[#Table of Contents|↑ Back to TOC]]

1. Select 3-5 Windows x64 devices: a staff PC, a lab PC, and a laptop tested on campus and away from campus with the normal VPN workflow.
2. Include an existing agent installation if you plan to upgrade deployed agents. The wrapper stops for a different server/account or an existing x86 agent; handle these as separate migrations.
3. Assign the app as Required to the pilot device group. Sync the devices and review Intune installation status.
4. On each pilot device, run the read-only checks below in elevated PowerShell.
5. Confirm the asset appears in SysAid, reports the expected computer/user details, and continues checking in. Test after reboot and VPN reconnection. If absent after several minutes, inspect communication and proxy settings rather than repeatedly reinstalling.
6. Review hotkey, screenshot, and remote-control behavior with the pilot users. Then expand in stages: IT staff, one staff group, one lab, remaining fleet.

```powershell
Get-Service -Name SysAidAgent | Select-Object Name, Status, StartType

Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\SysAid\InstalledProducts\SysAid' |
    Select-Object DisplayVersion, ServerURL, AccountID, InstallLocation

Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\UMDLibraries\SysAidAgent' |
    Select-Object PackageRevision, ServerUrl, AccountId, InstalledAt

Resolve-DnsName ticketing.lib.umd.edu
Test-NetConnection ticketing.lib.umd.edu -Port 443
Invoke-WebRequest -Uri 'https://ticketing.lib.umd.edu' -Method Head -UseBasicParsing -TimeoutSec 20 |
    Select-Object StatusCode
```

Use **64-bit** PowerShell for these registry commands. The detection script itself explicitly selects the 64-bit registry view. The HTTP check can return an authentication or method-related status; distinguish that response from DNS, connection, or certificate failure. An interactive-user test does not prove SYSTEM can reach the server through the same proxy.

For a manual pilot, securely copy the five staged source files into `C:\ProgramData\UMDLibraries\SysAid\Pilot` on a designated test endpoint. Run elevated:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive `
    -ExecutionPolicy Bypass -File 'C:\ProgramData\UMDLibraries\SysAid\Pilot\Install-SysAidAgent.ps1'
$LASTEXITCODE
```

Restrict the pilot folder to administrators and SYSTEM, and remove the copied transform when the manual test is complete. Test the Intune assignment afterward as well; a manual test alone does not verify Intune delivery.

---

## Network and Security
> [[#Table of Contents|↑ Back to TOC]]

The installer adds no firewall rules. Ensure the endpoint can resolve the configured hostname and reach HTTPS on TCP 443, with a trusted server certificate and complete chain. Test connectivity as SYSTEM during the pilot if machine proxy or certificate behavior differs from the signed-in user.

The deployment-tool port and Remote Registry instructions in the vendor guide concern network-push deployment. This package installs locally through Intune. Confirm any additional agent or remote-control traffic against your actual SysAid configuration. If inbound 8193 is needed, implement a separate Intune firewall policy scoped to approved management sources and profiles after confirming TCP/UDP requirements. The supplied guide references UDP 8193; the old configuration script created an unrestricted TCP rule. [SysAid deployment guide](https://documentation.sysaid.com/docs/agent-deployment-guide)

Keep **AlwaysInstallElevated** disabled or unconfigured. Intune System context provides the needed rights for this managed install. Microsoft identifies AlwaysInstallElevated as a substantial privilege-escalation risk. [Microsoft security guidance](https://learn.microsoft.com/en-us/windows/win32/msi/alwaysinstallelevated)

The wrappers preserve the MSI's feature defaults and make no antivirus exclusions. Review SysAid's centrally managed remote-control consent and permissions, screenshot hotkey, scripting, and patch-management settings before expanding the pilot. Check CrowdStrike events for agent/service activity. If a verified conflict occurs, use a narrowly scoped approved exception; confirm Rapid7 continues reporting normally.

Treat the serial as enrollment material. The MST and `.intunewin` packaging are not secret storage; administrators can recover their contents, and the vendor stores agent configuration on the endpoint. Restrict build artifacts, logs, and package-sharing access. Property masking and standard MSI logging reduce accidental disclosure, but vendor custom actions may still log sensitive data. Review logs before sharing them. The deployment log folder is restricted to SYSTEM and local administrators.

---

## Troubleshooting
> [[#Table of Contents|↑ Back to TOC]]

Start with the service, expected enrollment target, and local logs:

```powershell
Get-ChildItem -LiteralPath 'C:\ProgramData\UMDLibraries\SysAid' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object Name, LastWriteTime, Length

Get-Content -LiteralPath 'C:\ProgramData\UMDLibraries\SysAid\Install-SysAidAgent.log' -Tail 60
```

| Symptom | Next action |
|---|---|
| Intune says installed; no asset check-in | Verify server URL/account, SYSTEM connectivity, certificate chain, VPN, and proxy. Use the vendor Agent Healthcheck Utility if needed. |
| Exit 1618 | Let the other MSI finish; Intune retries using the configured return-code mapping. |
| Exit 3010 | Restart at the approved time, then confirm Automatic startup, Running state, and asset check-in. |
| MSI exit 1603 | Review the newest protected `MSI-Install-*.log`, EDR events, prerequisites, and prior installation state. |
| MSI exit 1638 or downgrade message | Check the installed release. The wrapper accepts a healthy newer agent rather than downgrading it. |
| Different server/account or x86 agent | Stop the rollout for that device and plan its migration; no automatic re-enrollment or architecture removal is attempted. |
| Same baseline version but missing executable/service | The installer attempts an MSI repair with the bundled package. A damaged newer version needs its matching installer. |
| Agent is installed but Intune detection fails | Confirm the generated detection script is selected, the completion marker exists, and its expected target matches the deployed build. |
| Uninstall leaves a service | Check for a legacy EXE install, uninstall protection, or a pending restart. The wrapper fails rather than claiming successful removal. |

Intune delivery logs remain in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`; inspect `AppWorkload.log`, `AppActionProcessor.log`, and `IntuneManagementExtension.log` alongside the package logs. These Intune-managed paths are separate from the logs generated by these wrappers.

---

## Uninstall and Rollback
> [[#Table of Contents|↑ Back to TOC]]

1. Remove the device from the Required install assignment or exclude it from that assignment.
2. Assign Uninstall to the intended rollback device group. Avoid conflicting install/uninstall assignments.
3. Confirm removal, handle a 3010 restart, and review `Uninstall-SysAidAgent.log` and the matching MSI log.

The uninstaller discovers registered SysAid Agent MSI product GUIDs, so it can handle a product code changed by a later MSI upgrade. It validates the product name, publisher, and MSI registration, then uses `msiexec /x`. It never queries `Win32_Product` or executes arbitrary registry uninstall strings. Legacy EXE installations need their own reviewed removal method.

The completion marker is removed after successful removal or an MSI-reported pending restart. Deployment logs remain under ProgramData. Removal does not delete asset records from the SysAid server. To roll back an agent version, pilot uninstall followed by a reviewed server-compatible older installer; do not install an older MSI over a newer agent.

---

## Rebuilding and Updating
> [[#Table of Contents|↑ Back to TOC]]

The local configuration is already populated. To rebuild after a reviewed script change, open PowerShell in this project folder:

```powershell
.\Build-SysAidIntunePackage.ps1
```

Or invoke the builder with a different local configuration/tool path:

```powershell
.\Build-SysAidIntunePackage.ps1 `
    -ConfigPath '.\Build\BuildConfig.json' `
    -ContentPrepTool '..\.tools\IntuneWinAppUtil.exe'
```

The builder checks the original MSI hash and signature, generates the transform, stages the exact package files in `Build\Source`, generates matching detection, and runs Microsoft's Win32 Content Prep Tool with `-s Install-SysAidAgent.ps1`. Output is written to `Build\Output`, outside the staged source folder. Upload the package and detection file from the same build. Endpoint deployment logs continue to use `C:\ProgramData\UMDLibraries\SysAid`.

For a new MSI release, review its signature, architecture, product/upgrade codes, property names, version, and hash before updating `Package-Metadata.json`. Increment `PackageRevision` when a new wrapper configuration must run on devices that already meet the agent version baseline. Rebuild and pilot again. If the URL/account changes, update both metadata and local configuration, and plan existing-agent migration separately.

For another build machine, copy `SysAidConfig.example.json` to `Build\BuildConfig.json` in this project folder, restrict the build folder to the builder, SYSTEM, and administrators, and enter the serial from SysAid's Downloads page. Keep the populated file out of Git and shared documentation. [SysAid enrollment values](https://documentation.sysaid.com/docs/downloads)

---

## Validation and Sources
> [[#Table of Contents|↑ Back to TOC]]

Automated checks cover PowerShell 5.1 syntax, the original MSI signature/hash, actual transform generation/application with test enrollment data, mocked installation/removal, success/failure/retry/reboot codes, detection identity/version/completion checks, and `-WhatIf`. The tests never install the agent. Local launch checks exercise 32-bit and 64-bit command-line hosts and the script-editor form without making endpoint changes.

To rerun the automated checks from the project folder:

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive `
    -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script '.\Tests\SysAidAgent.Tests.ps1'"
```

The tests use Pester 3 or later and isolated HKCU registry fixtures. Test artifacts use temporary directories under `Tests\Artifacts` in this project folder and are removed afterward. Live installation, server registration, remote control, and fleet deployment still require the pilot.

- Local vendor reference: [[SysAid Agent Deployment Guide (1).pdf]]
- [SysAid Agent Deployment Guide](https://documentation.sysaid.com/docs/agent-deployment-guide)
- [SysAid Network Discovery Downloads](https://documentation.sysaid.com/docs/downloads)
- [Microsoft Intune Win32 app setup and custom detection](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Microsoft MSI transform generation](https://learn.microsoft.com/en-us/windows/win32/msi/database-generatetransform)
- [Microsoft MSI property masking](https://learn.microsoft.com/en-us/windows/win32/msi/msihiddenproperties)

macOS deployment is a separate Jamf package and privacy-permission workflow; this Windows package does not configure Macs.
