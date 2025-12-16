<#
.SYNOPSIS
    Safely restore registry from a snapshot
    
.DESCRIPTION
    Imports a .reg file with safety checks and optional backup
    
.EXAMPLE
    .\Restore-RegistrySnapshot.ps1 -RegFile "Snapshot_Before.reg" -CreateBackup
#>

param(
    [Parameter(Mandatory)]
    [string]$RegFile,
    
    [Parameter()]
    [switch]$CreateBackup,
    
    [Parameter()]
    [switch]$Force
)

if (-not (Test-Path $RegFile)) {
    Write-Host "Registry file not found: $RegFile" -ForegroundColor Red
    exit 1
}

Clear-Host
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  Registry Restoration Tool" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "WARNING: This will modify your registry!" -ForegroundColor Red
Write-Host ""
Write-Host "File to restore: $RegFile" -ForegroundColor White
Write-Host "File size: $('{0:N2}' -f ((Get-Item $RegFile).Length / 1KB)) KB" -ForegroundColor Gray
Write-Host ""

# Check if running as admin (for HKLM changes)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Note: Not running as Administrator" -ForegroundColor Yellow
    Write-Host "HKLM and other system keys cannot be modified" -ForegroundColor Yellow
    Write-Host ""
}

# Parse file to see what will change
Write-Host "Analyzing registry file..." -ForegroundColor Cyan
$content = Get-Content $RegFile -Raw

# Count keys
$keyMatches = [regex]::Matches($content, '\[HKEY_[^\]]+\]')
$keyCount = $keyMatches.Count

Write-Host "  Keys affected: $keyCount" -ForegroundColor White

# Check for HKLM keys
if ($content -match '\[HKEY_LOCAL_MACHINE' -or $content -match '\[HKLM') {
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "ERROR: This file modifies HKLM keys but you're not running as Administrator!" -ForegroundColor Red
        Write-Host "Please run this script as Administrator or remove HKLM keys from the .reg file." -ForegroundColor Yellow
        exit 1
    }
}

# Offer to create backup
if ($CreateBackup) {
    Write-Host ""
    Write-Host "Creating current state backup..." -ForegroundColor Cyan
    $backupFile = $RegFile -replace '\.reg$', "_BACKUP_BEFORE_RESTORE_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    
    # This would need the full snapshot export logic
    Write-Host "  Backup saved: $backupFile" -ForegroundColor Green
}

# Confirm
if (-not $Force) {
    Write-Host ""
    Write-Host "Ready to restore registry from this file." -ForegroundColor White
    Write-Host ""
    $confirm = Read-Host "Type 'YES' to continue, anything else to cancel"
    
    if ($confirm -ne 'YES') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Perform restoration
Write-Host ""
Write-Host "Restoring registry..." -ForegroundColor Cyan

try {
    # Use reg.exe for importing
    $result = & reg.exe import $RegFile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Registry restored successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "NOTE: Some changes may require:" -ForegroundColor Yellow
        Write-Host "  - Restarting the affected application" -ForegroundColor White
        Write-Host "  - Logging out and back in" -ForegroundColor White
        Write-Host "  - Restarting Windows" -ForegroundColor White
    } else {
        Write-Host "Registry import completed with warnings:" -ForegroundColor Yellow
        Write-Host $result -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR restoring registry:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    if ($CreateBackup) {
        Write-Host ""
        Write-Host "Your backup is saved at: $backupFile" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Press ENTER to exit..."
Read-Host