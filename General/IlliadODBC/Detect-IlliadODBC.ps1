# Detect-IlliadODBC.ps1
# Detection script for Intune/Company Portal deployment
# Checks if ILLiad ODBC User DSN is configured
#
# Exit 0 with output = Detected (installed)
# Exit 1 or no output = Not detected (not installed)

$dsnName = "ILLiadLink"
$regPath = "HKCU:\SOFTWARE\ODBC\ODBC.INI\$dsnName"

try {
    # Check if the DSN registry key exists
    if (Test-Path $regPath) {
        # Verify critical settings are present
        $driver = Get-ItemProperty -Path $regPath -Name "Driver" -ErrorAction SilentlyContinue
        $server = Get-ItemProperty -Path $regPath -Name "Server" -ErrorAction SilentlyContinue
        $database = Get-ItemProperty -Path $regPath -Name "Database" -ErrorAction SilentlyContinue

        if ($driver -and $server -and $database) {
            Write-Output "ILLiad ODBC User DSN '$dsnName' is configured"
            exit 0
        }
    }

    # DSN not found or incomplete
    exit 1

} catch {
    # Any error means not properly configured
    exit 1
}
