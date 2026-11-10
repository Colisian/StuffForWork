<#
.SYNOPSIS
    Intune Remediations DETECTION script for the Trellix (FireEye) HX Agent.

.DESCRIPTION
    Exit 1 = HX agent found  -> Intune runs the remediation (Remove-TrellixHX.ps1)
    Exit 0 = HX agent absent -> device is compliant
#>

$Pattern = 'FireEye Endpoint Agent|Endpoint Security \(HX\) Agent|^FireEye Agent$'
$Keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$app = Get-ItemProperty -Path $Keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match $Pattern } | Select-Object -First 1
$svc = Get-Service -Name 'xagt' -ErrorAction SilentlyContinue

if ($app -or $svc) {
    $name = if ($app) { "$($app.DisplayName) $($app.DisplayVersion)" } else { 'xagt service' }
    Write-Output "Trellix HX present: $name"
    exit 1
}

Write-Output "Trellix HX not present"
exit 0