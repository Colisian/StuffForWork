<# 
Place this at the package root. Intune install command:
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
#>

#  Logging / Prep 
$LogFile = Join-Path $env:TEMP ("ChemDrawApps_x64_Install_" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
Start-Transcript -Path $LogFile -Force

$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
function Log($s) { Write-Output $s }

#  Helpers 
function Run-Exe([string]$exe, $arguments = $null) {
    $argsDisplay = if ($null -eq $arguments -or $arguments -eq "") { "<no-args>" } else {
        if ($arguments -is [array]) { $arguments -join " " } else { $arguments }
    }
    Log "RUN: $exe  $argsDisplay"

    try {
        if ($null -eq $arguments -or $arguments -eq "") {
            $p = Start-Process -FilePath $exe -Wait -PassThru -WindowStyle Hidden
        } else {
            if ($arguments -is [string]) { $argList = @($arguments) } else { $argList = $arguments }
            $p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden
        }

        $exit = 0
        if ($p -and $p.ExitCode -ne $null) { $exit = [int]$p.ExitCode }
        Log "ExitCode: $exit"
        return $exit
    } catch {
        Write-Warning "Run-Exe failed to start $exe : $($_.Exception.Message)"
        return 1
    }
}

function Find-File([string]$pattern) {
    return Get-ChildItem -Path $Root -Recurse -Filter $pattern -ErrorAction SilentlyContinue |
           Sort-Object FullName | Select-Object -First 1
}

function Get-MsiProperty([string]$msiPath, [string]$prop = "ProductVersion") {
    try {
        $msi = New-Object -ComObject WindowsInstaller.Installer
        $db = $msi.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$msi,(@($msiPath, 0)))
        $view = $db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,("SELECT `Value` FROM `Property` WHERE `Property`='$prop'"))
        $view.GetType().InvokeMember('Execute','InvokeMethod',$null,$view,$null)
        $rec = $view.GetType().InvokeMember('Fetch','InvokeMethod',$null,$view,$null)
        if ($rec) { return $rec.GetType().InvokeMember('StringData','GetProperty',$null,$rec,1) }
    } catch {}
    return $null
}

#  1) .NET 4.8 
$dotNet = Find-File "ndp48-x86-x64-allos-enu.exe"
if ($dotNet) {
    Log "Installing .NET 4.8 from $($dotNet.FullName)"
    $rc = Run-Exe $dotNet.FullName @("/q","/norestart")
    if ($rc -ne 0) { Write-Warning ".NET installer returned $rc (check logs)"; }
} else { Log ".NET installer not found - skipping" }

#  2) VC++ redist x64 
$vcred = Find-File "vcredist_x64.exe"
if ($vcred) {
    Log "Installing VC++ Redistributable x64"
    $rc = Run-Exe $vcred.FullName @("/q","/norestart")
    if ($rc -ne 0 -and $rc -ne 1638) { Write-Warning "vcredist_x64 returned $rc" }
} else { Log "vcredist_x64 not found - skipping" }

#  3) WebView2 x64 
$webview = Find-File "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
if ($webview) {
    Log "Installing WebView2 Runtime (x64)"
    $rc = Run-Exe $webview.FullName @("/silent","/install")
    if ($rc -ne 0) { Write-Warning "WebView2 installer returned $rc (you may need to run interactively to debug)" }
} else { Log "WebView2 installer not found - skipping" }

#  4) Python x64 (installer only) 
# Installs Python x64 silently if present. NO pywin32 or pip pywin32 actions.
$py310Installer = Find-File "python-3.10*.exe"
$pythonExe = "C:\Program Files\Python310\python.exe"

if (-not (Test-Path $pythonExe)) {
    if ($py310Installer) {
        Log "Installing Python x64 from $($py310Installer.FullName)"
        $rc = Run-Exe $py310Installer.FullName @("/quiet","InstallAllUsers=1","PrependPath=1","Include_pip=1")
        if ($rc -ne 0) { Write-Warning "Python installer returned $rc" }
    } else {
        Log "No Python x64 installer found in package - skipping Python install"
    }
} else {
    Log "Python x64 already installed at $pythonExe - skipping install"
}

#  5) Install Applications MSI 
$appMsi = Join-Path $Root "ChemDrawApplications_x64.msi"
if (-not (Test-Path $appMsi)) {
    $appMsiObj = Get-ChildItem -Path $Root -Recurse -Filter "*ChemDraw*Applications*_x64*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($appMsiObj) { $appMsi = $appMsiObj.FullName }
}

if (Test-Path $appMsi) {
    Log "Installing ChemDraw Applications MSI: $appMsi"
    $msiArgs = @('/i', $appMsi, 'REBOOT=ReallySuppress', 'ALLUSERS=1', '/qn')
    $rc = Run-Exe "msiexec.exe" $msiArgs
    $rc = [int]$rc
    if ($rc -ne 0) {
        if ($rc -eq 3010) {
            Log "msiexec returned 3010 (reboot required) - treating as success"
        } else {
            Write-Error "Applications MSI failed with exit code $rc"
            Stop-Transcript
            Exit $rc
        }
    } else {
        Log "Applications MSI installed successfully (exit 0)"
    }
} else {
    Write-Error "Applications MSI not found in package (expected ChemDrawApplications_x64.msi or similar)"
    Stop-Transcript
    Exit 1603
}

#  6) Activation 
$activateExe = Join-Path $Root "Activation\Activate.exe"
$activateIni = Join-Path $Root "Activation\Activate.ini"
if (Test-Path $activateExe -and Test-Path $activateIni) {
    $msiVer = $null
    try { $msiVer = Get-MsiProperty -msiPath $appMsi -prop "ProductVersion" } catch {}
    if ($msiVer -and $msiVer -match "^(\d+)\.(\d+)") {
        $ver = "$($matches[1]).$($matches[2])"
    } else {
        $fname = (Split-Path $appMsi -Leaf)
        if ($fname -match "(\d+)\.(\d+)") { $ver = "$($matches[1]).$($matches[2])" } else { $ver = "25.0" }
    }

    Log "Running activation: $activateExe $ver IsInstaller Silent"
    $rc = Run-Exe $activateExe @($ver, "IsInstaller", "Silent")
    $rc = [int]$rc
    if ($rc -ne 0) { Write-Warning "Activation returned $rc - activation may require interactive sign-in for some license types" }
} else {
    Log "Activation tool/ini not found - skipping activation"
}

Stop-Transcript
Exit 0