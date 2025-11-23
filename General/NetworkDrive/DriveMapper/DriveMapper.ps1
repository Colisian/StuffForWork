# Define the hierarchical drive structure
$driveStructure = @{
    "1" = @{
        Name = "libdcr"
        HasSubfolders = $true
        Subfolders = @{
            "1" = @{Name = "Audio"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\Audio"}
            "2" = @{Name = "dcr_projects"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\dcr_projects"}
            "3" = @{Name = "diamondback"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\diamondback"}
            "4" = @{Name = "FilmsUMDvd"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\FilmsUMDvd"}
            "5" = @{Name = "footballfilm"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\footballfilm"}
            "6" = @{Name = "Gblood"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\Gblood"}
            "7" = @{Name = "MassMedia"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\MassMedia"}
            "8" = @{Name = "NewsPaper"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\NewsPaper"}
            "9" = @{Name = "Scratch"; Path = "\\cifs.isip01.nas.umd.edu\libdcr\Scratch"}
        }
    }
    "2" = @{
        Name = "BornDigital"
        HasSubfolders = $true
        Subfolders = @{
            "1" = @{Name = "BDigital"; Path = "\\cifs.isip01.nas.umd.edu\BornDigital\BDigital"}
            "2" = @{Name = "BDigital_Archive"; Path = "\\cifs.isip01.nas.umd.edu\BornDigital\BDigital_Archive"}
            "3" = @{Name = "Exhibits"; Path = "\\cifs.isip01.nas.umd.edu\BornDigital\Exhibits"}
            "4" = @{Name = "Exhibits Records"; Path = "\\cifs.isip01.nas.umd.edu\BornDigital\Exhibits Records"}
            "5" = @{Name = "Special Collections"; Path = "\\cifs.isip01.nas.umd.edu\BornDigital\Special Collections"}
        }
    }
    "3" = @{
        Name = "ussshare"
        HasSubfolders = $true
        Subfolders = @{
            "1" = @{Name = "RSS"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\RSS"}
            "2" = @{Name = "DST Share"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\DST Share"}
            "3" = @{Name = "MarylandRoom"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\MarylandRoom"}
            "4" = @{Name = "DSTShareData"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\DSTShareData"}
            "5" = @{
                Name = "Database Files"
                HasSubfolders = $true
                Subfolders = @{
                    "1" = @{Name = "ACRDS"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\Database Files\ACRDS"}
                    "2" = @{Name = "Cataloging and Metadata"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\Database Files\Cataloging and Metadata"}
                    "3" = @{Name = "Logistics and Periodicals"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\Database Files\Logistics and Periodicals"}
                    "4" = @{Name = "SCUA"; Path = "\\cifs.isip01.nas.umd.edu\ussshare\Database Files\SCUA"}
                }
            }
        }
    }
}

function Show-Menu {
    param(
        [hashtable]$MenuItems,
        [string]$Title = "Network Drive Mapper"
    )
    
    Clear-Host
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    Write-Host "Please select an option:`n" -ForegroundColor Yellow
    
    foreach ($key in ($MenuItems.Keys | Sort-Object {[int]$_})) {
        $item = $MenuItems[$key]
        if ($item.HasSubfolders) {
            Write-Host "$key. $($item.Name) >" -ForegroundColor White
        } else {
            Write-Host "$key. $($item.Name)" -ForegroundColor White
        }
    }
    
    Write-Host "`nB. Back" -ForegroundColor Gray
    Write-Host "Q. Quit" -ForegroundColor Gray
    Write-Host "`n===========================" -ForegroundColor Cyan
    
    $selection = Read-Host "`nEnter your choice"
    return $selection
}

function Get-AvailableDriveLetter {
    $usedLetters = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
    $availableLetters = 68..90 | ForEach-Object { [char]$_ } | Where-Object { $_ -notin $usedLetters }
    
    if ($availableLetters.Count -gt 0) {
        return $availableLetters[0]
    }
    return $null
}

function Map-NetworkDrive {
    param(
        [string]$Path,
        [string]$Name
    )
    
    $driveLetter = Get-AvailableDriveLetter
    
    if ($null -eq $driveLetter) {
        Write-Host "`nNo available drive letters. Please disconnect a network drive first." -ForegroundColor Red
        return $false
    }
    
    Write-Host "`nMapping '$Name' to ${driveLetter}: ..." -ForegroundColor Yellow
    Write-Host "Path: $Path" -ForegroundColor Gray
    
    try {
        # Remove existing mapping if it exists
        if (Test-Path "${driveLetter}:") {
            net use "${driveLetter}:" /delete /y 2>$null | Out-Null
        }
        
        # Map the drive
        $result = net use "${driveLetter}:" "$Path" /persistent:yes 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`nSuccessfully mapped '$Name' to ${driveLetter}:" -ForegroundColor Green
            
            # Optional: Open the drive in Explorer
            $openDrive = Read-Host "`nWould you like to open the drive? (Y/N)"
            if ($openDrive.ToUpper() -eq "Y") {
                Start-Process "${driveLetter}:"
            }
            return $true
        } else {
            Write-Host "`nError mapping drive: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "`nError mapping drive: $_" -ForegroundColor Red
        return $false
    }
}

function Navigate-Menu {
    param(
        [hashtable]$CurrentLevel,
        [string]$Title = "Network Drive Mapper"
    )
    
    while ($true) {
        $selection = Show-Menu -MenuItems $CurrentLevel -Title $Title
        
        if ($selection.ToUpper() -eq "Q") {
            Write-Host "`nExiting..." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            return "QUIT"
        }
        
        if ($selection.ToUpper() -eq "B") {
            return "BACK"
        }
        
        if ($CurrentLevel.ContainsKey($selection)) {
            $selectedItem = $CurrentLevel[$selection]
            
            if ($selectedItem.HasSubfolders) {
                # Navigate to subfolder menu
                $newTitle = "$Title > $($selectedItem.Name)"
                $result = Navigate-Menu -CurrentLevel $selectedItem.Subfolders -Title $newTitle
                
                if ($result -eq "QUIT") {
                    return "QUIT"
                }
                # If BACK, continue loop to show current menu again
            } else {
                # Map the drive
                $mapped = Map-NetworkDrive -Path $selectedItem.Path -Name $selectedItem.Name
                
                if ($mapped) {
                    Write-Host "`nPress any key to return to menu..."
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                } else {
                    Write-Host "`nPress any key to try again..."
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            }
        } else {
            Write-Host "`nInvalid selection. Press any key to try again..." -ForegroundColor Red
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}

# Start the navigation
Navigate-Menu -CurrentLevel $driveStructure

Write-Host "`nThank you for using Network Drive Mapper!" -ForegroundColor Cyan
Start-Sleep -Seconds 2