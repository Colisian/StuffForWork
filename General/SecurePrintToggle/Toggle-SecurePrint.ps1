<#
.SYNOPSIS
    Toggles Secure Print on/off for all Canon printers by modifying DevMode byte.
    
.DESCRIPTION
    This script toggles the Secure Print setting for Canon printers connected via
    print server. It modifies byte offset 1202 in the DevMode blob:
      - 0x01 = Secure Print OFF
      - 0x10 = Secure Print ON
    
    NO ADMIN RIGHTS REQUIRED - modifies user-level registry only.
    
.NOTES
    Author: UMD Libraries IT
    Version: 3.0
    Tested with: Canon Generic Plus UFR II driver
    Print Server: LIBRPS403v.ad.umd.edu
#>

# Configuration - byte offset and values for Secure Print toggle
$SecurePrintByteOffset = 1202
$SecurePrintOFF = 0x01
$SecurePrintON = 0x10

# Function to show message box
function Show-MessageBox {
    param(
        [string]$Message,
        [string]$Title,
        [string]$Icon = "Information"
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Message, 
        $Title, 
        [System.Windows.Forms.MessageBoxButtons]::OK, 
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    ) | Out-Null
}

# Get all printer connections from registry
$connectionsPath = "HKCU:\Printers\Connections"

if (-not (Test-Path $connectionsPath)) {
    Show-MessageBox -Message "No network printer connections found." -Title "Secure Print Toggle" -Icon "Warning"
    exit
}

$printerConnections = Get-ChildItem -Path $connectionsPath -ErrorAction SilentlyContinue

if ($printerConnections.Count -eq 0) {
    Show-MessageBox -Message "No network printer connections found." -Title "Secure Print Toggle" -Icon "Warning"
    exit
}

# Track results
$toggledPrinters = @()
$skippedPrinters = @()
$newStatusText = ""
$newStatus = $null

foreach ($connection in $printerConnections) {
    $printerPath = $connection.PSPath
    $printerName = $connection.PSChildName -replace ',', '\'
    
    # Check if this is a Canon printer by checking if DevMode exists and has expected size
    try {
        $devMode = (Get-ItemProperty -Path $printerPath -Name "DevMode" -ErrorAction SilentlyContinue).DevMode
        
        if (-not $devMode) {
            continue
        }
        
        # Verify the DevMode is large enough to contain our offset
        if ($devMode.Length -le $SecurePrintByteOffset) {
            $skippedPrinters += "$printerName (DevMode too small - may not be Canon)"
            continue
        }
        
        # Read current value at the Secure Print byte offset
        $currentValue = $devMode[$SecurePrintByteOffset]
        
        # Check if this looks like a Canon printer (byte should be 0x01 or 0x10)
        if ($currentValue -ne $SecurePrintOFF -and $currentValue -ne $SecurePrintON) {
            # Not a Canon printer or different driver version
            $skippedPrinters += "$printerName (not Canon UFR II)"
            continue
        }
        
        # Determine toggle direction (first Canon printer sets direction for all)
        if ($null -eq $newStatus) {
            if ($currentValue -eq $SecurePrintOFF) {
                $newStatus = $SecurePrintON
                $newStatusText = "ENABLED"
            } else {
                $newStatus = $SecurePrintOFF
                $newStatusText = "DISABLED"
            }
        }
        
        # Modify the byte
        $devMode[$SecurePrintByteOffset] = $newStatus
        
        # Write back to registry
        Set-ItemProperty -Path $printerPath -Name "DevMode" -Value $devMode -Type Binary
        
        $toggledPrinters += $printerName
        
    } catch {
        $skippedPrinters += "$printerName (error: $($_.Exception.Message))"
    }
}

# Display results
if ($toggledPrinters.Count -gt 0) {
    $printerList = $toggledPrinters | ForEach-Object { "  • $_" }
    $message = @"
Secure Print has been $newStatusText for:

$($printerList -join "`n")

Close and reopen your application for changes to take effect in print dialogs.
"@
    
    if ($skippedPrinters.Count -gt 0) {
        $message += "`n`nSkipped (non-Canon or incompatible):`n"
        $message += ($skippedPrinters | ForEach-Object { "  - $_" }) -join "`n"
    }
    
    Show-MessageBox -Message $message -Title "Secure Print Toggle"
} else {
    $message = "No compatible Canon printers were found.`n`n"
    
    if ($skippedPrinters.Count -gt 0) {
        $message += "Skipped printers:`n"
        $message += ($skippedPrinters | ForEach-Object { "  - $_" }) -join "`n"
    }
    
    $message += "`n`nThis tool works with Canon Generic Plus UFR II printers connected via print server."
    
    Show-MessageBox -Message $message -Title "Secure Print Toggle" -Icon "Warning"
}