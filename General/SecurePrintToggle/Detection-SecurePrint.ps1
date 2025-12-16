<#
.SYNOPSIS
    Intune Detection Script for Toggle Secure Print utility
    
.DESCRIPTION
    Checks if the Toggle Secure Print shortcut exists on any desktop location.
    Returns exit code 0 if found (installed), 1 if not found (not installed)
    
    Checks both:
    - Public Desktop (System context install)
    - User Desktop (User context install)
#>

$shortcutPaths = @(
    "$env:PUBLIC\Desktop\Toggle Secure Print.lnk",
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "Toggle Secure Print.lnk")
)

foreach ($path in $shortcutPaths) {
    if (Test-Path $path) {
        Write-Host "Toggle Secure Print shortcut found at: $path"
        exit 0
    }
}

Write-Host "Toggle Secure Print shortcut not found"
exit 1