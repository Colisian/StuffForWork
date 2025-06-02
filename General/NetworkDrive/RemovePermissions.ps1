param(
    [Parameter(Mandatory=$true)]
    [string] $RootPath,

    [Parameter(Mandatory=$false)]
    [switch] $WhatIf,

    [Parameter(Mandatory=$false)]
    [string] $LogPath = ".\RemovePermissions_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

function Write-Log {
    param(
        [string] $Message,
        [string] $Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Colorize the console output
    Write-Host $logEntry -ForegroundColor $(
        switch ($Level) {
            "ERROR"   { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default   { "White" }
        }
    )

    # Append to log file
    Add-Content -Path $LogPath -Value $logEntry
}

function Remove-UserPermissions {
    param(
        [string] $DirectoryPath,
        [switch] $WhatIf
    )

    try {
        # Retrieve the existing ACL
        $acl = Get-Acl -Path $DirectoryPath
        $originalCount = $acl.Access.Count

        # Accounts we want to keep
        $preserveAccounts = @(
            'BUILTIN\Administrators',
            'NT AUTHORITY\SYSTEM',
            'CREATOR OWNER',
            'BUILTIN\Backup Operators',
            'DOMAIN\Domain Admins',  # ← replace DOMAIN
            'DOMAIN\IT Admins'       # ← replace DOMAIN
        )

        # Build a fresh DirectorySecurity object
        $newAcl = New-Object System.Security.AccessControl.DirectorySecurity

        foreach ($ace in $acl.Access) {
            $identityValue = $ace.IdentityReference.Value
            $keepPermission = $false

            foreach ($preserveAccount in $preserveAccounts) {
                if ($identityValue -like $preserveAccount) {
                    $keepPermission = $true
                    break
                }
            }

            if ($keepPermission) {
                $newAcl.SetAccessRule($ace)
                Write-Log "PRESERVING: $identityValue - $($ace.FileSystemRights)" "INFO"
            }
            else {
                Write-Log "REMOVING:  $identityValue - $($ace.FileSystemRights)" "WARNING"
            }
        }

        # Preserve inheritance/protection flags
        $newAcl.SetAccessRuleProtection($acl.AreAccessRulesProtected, $true)

        if ($WhatIf) {
            $removed = $originalCount - $newAcl.Access.Count
            Write-Log "WHAT-IF: Would remove $removed permission entries from $DirectoryPath" "INFO"
        }
        else {
            # Apply the filtered ACL
            Set-Acl -Path $DirectoryPath -AclObject $newAcl
            $removed = $originalCount - $newAcl.Access.Count
            Write-Log "SUCCESS: Removed $removed permission entries from $DirectoryPath" "SUCCESS"
        }

        return $true
    }
    catch {
        Write-Log "ERROR: Failed to process $DirectoryPath - $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# --- Main execution ---

try {
    Write-Log "Starting permission removal process..." "INFO"
    Write-Log "Root Path: $RootPath" "INFO"
    Write-Log "WhatIf Mode: $WhatIf" "INFO"
    Write-Log "Log Path: $LogPath" "INFO"

    if (-not (Test-Path -Path $RootPath)) {
        throw "Root path '$RootPath' does not exist"
    }

    # Gather all subdirectories under $RootPath
    $userDirectories = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue

    if ($userDirectories.Count -eq 0) {
        Write-Log "No subdirectories found in $RootPath" "WARNING"
        exit 0
    }

    Write-Log "Found $($userDirectories.Count) user directories to process" "INFO"

    if (-not $WhatIf) {
        Write-Host "`nWARNING: This will remove user permissions from $($userDirectories.Count) directories!" `
            -ForegroundColor Red
        Write-Host "Press 'Y' to continue or any other key to exit: " -NoNewline -ForegroundColor Yellow
        $confirmation = Read-Host
        if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
            Write-Log "Operation cancelled by user" "INFO"
            exit 0
        }
    }

    $successCount = 0
    $failureCount = 0

    foreach ($directory in $userDirectories) {
        Write-Log "Processing: $($directory.FullName)" "INFO"
        if (Remove-UserPermissions -DirectoryPath $directory.FullName -WhatIf:$WhatIf) {
            $successCount++
        }
        else {
            $failureCount++
        }
    }

    Write-Log "=== OPERATION COMPLETE ===" "INFO"
    Write-Log "Directories processed successfully: $successCount" "SUCCESS"
    Write-Log "Directories with errors: $failureCount" "$(if ($failureCount -gt 0) { 'ERROR' } else { 'INFO' })"
    Write-Log "Log file saved to: $LogPath" "INFO"

    if ($WhatIf) {
        Write-Host "`nTo execute the changes, run the script again without the -WhatIf parameter" `
            -ForegroundColor Cyan
    }
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Script Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
