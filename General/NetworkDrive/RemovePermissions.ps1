
param(
    [Parameter(Mandatory=$true)]
    [string]$RootPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\RemovePermissions_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor $(
        switch($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
    Add-Content -Path $LogPath -Value $logEntry
}

function Remove-UserPermissions {
    param(
        [string]$DirectoryPath,
        [switch]$WhatIf
    )
    
    try {
        # Get current ACL
        $acl = Get-Acl -Path $DirectoryPath
        $originalCount = $acl.Access.Count
        
        # Define accounts to preserve (adjust these as needed for your environment)
        $preserveAccounts = @(
            'BUILTIN\Administrators',
            'NT AUTHORITY\SYSTEM',
            'CREATOR OWNER',
            'BUILTIN\Backup Operators'
        )
        
        # Add your domain admin groups (replace DOMAIN with your actual domain)
        $preserveAccounts += @(
            'DOMAIN\Domain Admins',
            'DOMAIN\IT Admins'  # Adjust to your actual admin groups
        )
        
        # Create new ACL with only preserved accounts
        $newAcl = New-Object System.Security.AccessControl.DirectorySecurity
        
        # Copy preserved permissions
        foreach ($ace in $acl.Access) {
            $keepPermission = $false
            
            foreach ($preserveAccount in $preserveAccounts) {
                if ($ace.IdentityReference.Value -like $preserveAccount -or 
                    $ace.IdentityReference.Translate([System.Security.Principal.NTAccount]).Value -like $preserveAccount) {
                    $keepPermission = $true
                    break
                }
            }
            
            if ($keepPermission) {
                $newAcl.SetAccessRule($ace)
                Write-Log "PRESERVING: $($ace.IdentityReference) - $($ace.FileSystemRights)" "INFO"
            } else {
                Write-Log "REMOVING: $($ace.IdentityReference) - $($ace.FileSystemRights)" "WARNING"
            }
        }
        
        # Preserve inheritance settings
        $newAcl.SetAccessRuleProtection($acl.AreAccessRulesProtected, $true)
        
        if ($WhatIf) {
            Write-Log "WHAT-IF: Would remove $($originalCount - $newAcl.Access.Count) permission entries from $DirectoryPath" "INFO"
        } else {
            # Apply the new ACL
            Set-Acl -Path $DirectoryPath -AclObject $newAcl
            Write-Log "SUCCESS: Removed $($originalCount - $newAcl.Access.Count) permission entries from $DirectoryPath" "SUCCESS"
        }
        
        return $true
    }
    catch {
        Write-Log "ERROR: Failed to process $DirectoryPath - $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main script execution
try {
    Write-Log "Starting permission removal process..." "INFO"
    Write-Log "Root Path: $RootPath" "INFO"
    Write-Log "WhatIf Mode: $WhatIf" "INFO"
    Write-Log "Log Path: $LogPath" "INFO"
    
    # Verify root path exists
    if (-not (Test-Path -Path $RootPath)) {
        throw "Root path '$RootPath' does not exist"
    }
    
    # Get all subdirectories (employee home folders)
    $userDirectories = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue
    
    if ($userDirectories.Count -eq 0) {
        Write-Log "No subdirectories found in $RootPath" "WARNING"
        exit 0
    }
    
    Write-Log "Found $($userDirectories.Count) user directories to process" "INFO"
    
    # Confirm before proceeding (unless in WhatIf mode)
    if (-not $WhatIf) {
        Write-Host "`nWARNING: This will remove user permissions from $($userDirectories.Count) directories!" -ForegroundColor Red
        Write-Host "Press 'Y' to continue or any other key to exit: " -NoNewline -ForegroundColor Yellow
        $confirmation = Read-Host
        if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
            Write-Log "Operation cancelled by user" "INFO"
            exit 0
        }
    }
    
    $successCount = 0
    $failureCount = 0
    
    # Process each user directory
    foreach ($directory in $userDirectories) {
        Write-Log "Processing: $($directory.FullName)" "INFO"
        
        if (Remove-UserPermissions -DirectoryPath $directory.FullName -WhatIf:$WhatIf) {
            $successCount++
        } else {
            $failureCount++
        }
    }
    
    # Summary
    Write-Log "=== OPERATION COMPLETE ===" "INFO"
    Write-Log "Directories processed successfully: $successCount" "SUCCESS"
    Write-Log "Directories with errors: $failureCount" "$(if($failureCount -gt 0){'ERROR'}else{'INFO'})"
    Write-Log "Log file saved to: $LogPath" "INFO"
    
    if ($WhatIf) {
        Write-Host "`nTo execute the changes, run the script again without the -WhatIf parameter" -ForegroundColor Cyan
    }
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Script Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}