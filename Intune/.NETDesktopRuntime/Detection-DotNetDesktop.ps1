# Detect-DotNetDesktop10.ps1
$base = "$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App"
if (-not (Test-Path $base)) { exit 1 }

$found = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { $v = $null; if ([version]::TryParse($_.Name, [ref]$v)) { $v } } |
    Where-Object { $_.Major -eq 10 } |
    Sort-Object -Descending | Select-Object -First 1

if ($found) {
    Write-Output "Detected Microsoft.WindowsDesktop.App $found"
    exit 0
}
exit 1