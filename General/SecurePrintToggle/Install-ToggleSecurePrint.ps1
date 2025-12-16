<#
.SYNOPSIS
    Intune Installation Script for Toggle Secure Print utility
    
.DESCRIPTION
    Deploys the Toggle Secure Print PowerShell script and creates a desktop
    shortcut. Can be deployed in User OR System context.
    
    - User context: Installs to user's AppData, shortcut on user desktop
    - System context: Installs to ProgramData, shortcut on public desktop
    
    The toggle script modifies DevMode byte 1202 in HKCU registry:
      - 0x01 = Secure Print OFF
      - 0x10 = Secure Print ON
    
.NOTES
    Deploy as: User context (preferred) or System context
    Install command: powershell.exe -ExecutionPolicy Bypass -File Install-ToggleSecurePrint.ps1
    
    NO ADMIN RIGHTS REQUIRED when deployed in User context
    Tested with: Canon Generic Plus UFR II driver on LIBRPS403v.ad.umd.edu
#>

$ErrorActionPreference = "Stop"

$scriptName = "Toggle-SecurePrint.ps1"

# Detect if running as System or User
$isSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Set paths based on context
if ($isSystem -or $isAdmin) {
    # System context - install for all users
    $installDir = "$env:ProgramData\UMDLibraries\SecurePrintToggle"
    $desktopPath = "$env:PUBLIC\Desktop"
} else {
    # User context - install for current user only
    $installDir = "$env:LOCALAPPDATA\UMDLibraries\SecurePrintToggle"
    $desktopPath = [Environment]::GetFolderPath("Desktop")
}

try {
    # Create installation directory
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
    }

    # Find the source script
    $sourcePath = $null
    $searchPaths = @(
        (Join-Path $PSScriptRoot $scriptName),
        (Join-Path (Get-Location) $scriptName),
        (Join-Path $env:TEMP $scriptName)
    )
    
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $sourcePath = $path
            break
        }
    }
    
    if (-not $sourcePath) {
        throw "Could not find $scriptName in any expected location"
    }

    # Copy the PowerShell script to the installation directory
    Copy-Item -Path $sourcePath -Destination $installDir -Force

    # Create desktop shortcut
    $shortcutPath = Join-Path $desktopPath "Toggle Secure Print.lnk"
    $targetScript = Join-Path $installDir $scriptName

    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetScript`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = "Toggle Secure Print on/off for all Canon printers"
    $shortcut.IconLocation = "shell32.dll,16"  # Printer icon
    $shortcut.Save()

    Write-Host "Toggle Secure Print installed successfully to: $installDir"
    Write-Host "Shortcut created at: $shortcutPath"
    exit 0
}
catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    exit 1
}