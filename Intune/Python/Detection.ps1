# Detection script - checks if Python is in system PATH
$pythonPath = "C:\Program Files\Python312"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

if ($currentPath -split ';' | Where-Object { $_ -eq $pythonPath }) {
    Write-Output "Python found in PATH"
    exit 0
} else {
    exit 1
}