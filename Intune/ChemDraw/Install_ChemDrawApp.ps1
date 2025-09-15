# install.ps1 - Applications-only flow (5.1.3)
# Uninstall Code: msiexec /x "{47517D24-BB94-47FD-B4D6-9850F32C0312}" /qn
# Detection Code: {47517D24-BB94-47FD-B4D6-9850F32C0312}

$LogFile = Join-Path $env:TEMP ("ChemDrawApps_x64_Install_" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
Start-Transcript -Path $LogFile -Force

$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Log($s){ Write-Output $s }
function Run-Exe($exe, $args) {
    Log "RUN: $exe $args"
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    Log "ExitCode: $($p.ExitCode)"
    return $p.ExitCode
}
function Find-File($pattern){
    return Get-ChildItem -Path $Root -Recurse -Filter $pattern -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
}

#1 .NET 4.8 (ndp48-x86-x64-allos-enu.exe)
$dotNet = Find-File "ndp48-x86-x64-allos-enu.exe"
if ($dotNet) {
    Log "Installing .NET 4.8 from $($dotNet.FullName)"
    $rc = Run-Exe $dotNet.FullName "/q /norestart"
    if ($rc -ne 0) { Write-Warning ".NET installer returned $rc" }
} else { Log ".NET installer not found — skipping" }

#2 VC++ redist x64
$vcred = Find-File "vcredist_x64.exe"
if ($vcred) {
    Log "Installing VC++ Redistributable x64"
    $rc = Run-Exe $vcred.FullName "/q /norestart"
    if ($rc -ne 0) { Write-Warning "vcredist_x64 returned $rc" }
} else { Log "vcredist_x64 not found — skipping" }

#3 WebView2 x64
$webview = Find-File "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
if ($webview) {
    Log "Installing WebView2 Runtime (x64)"
    $rc = Run-Exe $webview.FullName "/silent /install"
    if ($rc -ne 0) { Write-Warning "WebView2 returned $rc" }
} else { Log "WebView2 installer not found — skipping" }

#4 Python 3.10 x64 + pywin32 amd64 (x64-only branch)
$py310 = Find-File "python-3.10.11-amd64.exe"
$pywin32_x64 = Find-File "pywin32-306.win-amd64-py3.10.exe"

# helper to detect installed python 3.10 x64
function Python310Installed {
    try {
        $out = & py -0p 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            foreach ($line in $out) {
                if ($line -match "3\.10") { return $true }
            }
        }
    } catch {}
    # fallback - look for common install dir
    return Test-Path "C:\Program Files\Python310\python.exe"
}

if (-not (Python310Installed)) {
    if ($py310) {
        Log "Installing Python 3.10 (x64)"
        # Typical silent args for official python installer
        $args = "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1"
        $rc = Run-Exe $py310.FullName $args
        if ($rc -ne 0) { Write-Warning "Python 3.10 installer returned $rc" }
    } else {
        Log "Python 3.10 installer not found in package — skipping Python install"
    }
} else { Log "Python 3.10 appears installed — skipping" }

# pywin32 installer (registers COM DLLs; may require postinstall step)
if ($pywin32_x64) {
    Log "Installing pywin32 (amd64 for Python 3.10)"
    $rc = Run-Exe $pywin32_x64.FullName "/quiet"
    if ($rc -ne 0) { Write-Warning "pywin32 installer returned $rc" }
    # Run postinstall registration if python exists
    $pythonExe = "C:\Program Files\Python310\python.exe"
    if (Test-Path $pythonExe) {
        $post = Join-Path (Split-Path $pythonExe) "Scripts\pywin32_postinstall.py"
        if (Test-Path $post) {
            Log "Running pywin32 postinstall registration"
            $rc2 = Run-Exe $pythonExe "`"$post`" -install"
            if ($rc2 -ne 0) { Write-Warning "pywin32 postinstall returned $rc2" }
        } else {
            # try module based postinstall
            Log "Attempting module registration via: python -m pywin32_postinstall -install"
            $rc3 = Run-Exe $pythonExe "-m pywin32_postinstall -install"
            if ($rc3 -ne 0) { Write-Warning "pywin32 module postinstall returned $rc3" }
        }
    } else {
        Log "Python executable not found; will not run pywin32 postinstall now"
    }
} else { Log "pywin32 (amd64) not found — skipping" }

#5 Install ChemDraw Applications MSI (your renamed file)
# prefer explicit filename if present, else fallback to pattern
$appMsi = Join-Path $Root "ChemDrawApplications_x64.msi"
if (-not (Test-Path $appMsi)) {
    $appMsiObj = Get-ChildItem -Path $Root -Recurse -Filter "*ChemDraw*Applications*_x64*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($appMsiObj) { $appMsi = $appMsiObj.FullName }
}

if (Test-Path $appMsi) {
    Log "Installing ChemDraw Applications MSI: $appMsi"
    $rc = Run-Exe "msiexec.exe" "/i `"$appMsi`" REBOOT=ReallySuppress /qn ALLUSERS=1"
    if ($rc -ne 0) { Write-Error "Applications MSI failed with exit code $rc"; Exit $rc }
} else {
    Write-Error "Applications MSI not found in package (expected ChemDrawApplications_x64.msi or similar)"
    Exit 1603
}

#6 Activation (if provided)
$activateExe = Join-Path $Root "Activation\Activate.exe"
$activateIni = Join-Path $Root "Activation\Activate.ini"
if (Test-Path $activateExe -and Test-Path $activateIni) {
    # infer a version token, fallback to 25.0
    $ver = "25.0"
    if ((Split-Path $appMsi -Leaf) -match "(\d+\.\d+\.\d+)") { $ver = $matches[1] }
    Log "Running activation: $activateExe $ver IsInstaller Silent"
    $rc = Run-Exe $activateExe "$ver IsInstaller Silent"
    if ($rc -ne 0) { Write-Warning "Activation returned $rc — activation may require interactive sign-in for some license types" }
} else {
    Log "Activation tool/ini not found — skipping activation"
}

Stop-Transcript
Exit 0