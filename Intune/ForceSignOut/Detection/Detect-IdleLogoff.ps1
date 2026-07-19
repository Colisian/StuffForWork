# Detect-IdleLogoff.ps1
$TaskName    = 'LabIdleLogoff'
$VersionTag  = 'C:\ProgramData\LabIdleLogoff\version.txt'
$ExpectedVer = '1.0.0'   # keep in sync with Install-IdleLogoff.ps1

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) { exit 0 }  # not found → not installed (no output)

if (Test-Path $VersionTag) {
    $ver = (Get-Content $VersionTag -Raw).Trim()
    if ($ver -eq $ExpectedVer) {
        Write-Output "LabIdleLogoff v$ver present"
        exit 0
    }
}
exit 0  # task exists but version mismatch/missing tag → not installed