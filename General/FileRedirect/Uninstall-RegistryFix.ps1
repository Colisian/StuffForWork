<#
.SYNOPSIS
    Uninstall script for folder redirection registry fix
.DESCRIPTION
    Removes marker file to allow fix to be re-applied
#>

$LogDir = "$env:ProgramData\FolderRedirectionFix"

try {
    if (Test-Path $LogDir) {
        Remove-Item -Path $LogDir -Recurse -Force
        Write-Output "Marker files removed"
        exit 0
    }
    else {
        Write-Output "Nothing to uninstall"
        exit 0
    }
}
catch {
    Write-Output "Error during uninstall: $($_.Exception.Message)"
    exit 1
}