# Define paths
$BasePath = "H:\userhome"
$CsvOutputFile = "C:\Scripts\DiscoveryUsage.csv"  # CSV file for structured data
$ErrorLogFile = "C:\Scripts\DiscoveryUsageError.txt"
$TranscriptFile = "C:\Scripts\DiscoveryUsageTranscript.txt"

# Start transcript logging in a separate file
Start-Transcript -Path $TranscriptFile -Append

# Function to calculate directory size safely
function Get-DirectorySize {
    param (
        [string]$Path
    )
    try {
        # Ensure path is properly formatted
        $CleanPath = $Path -replace '\s+$', ''  # Trim any trailing spaces

        # Get total size of all files in the directory (excluding empty directories)
        $Files = Get-ChildItem -Path $CleanPath -Recurse -File -ErrorAction SilentlyContinue

        # Handle cases where the directory is empty
        if ($Files.Count -eq 0) {
            return 0
        }

        # Measure total size
        $Size = ($Files | Measure-Object -Property Length -Sum).Sum

        # Ensure the value is valid
        if ($Size -is [double] -or $Size -is [int]) {
            return [math]::Round($Size / 1MB, 2)
        } else {
            return 0
        }
    }
    catch {
        # Log the error with better formatting
        $ErrorMessage = "$(Get-Date) - Error calculating size for: '$Path'. $_"
        Write-Host $ErrorMessage -ForegroundColor Red
        $ErrorMessage | Out-File -FilePath $ErrorLogFile -Append
        return 0  # Return 0 in case of error
    }
}

# Prepare output files (clear existing files)
if (Test-Path $CsvOutputFile) { Remove-Item $CsvOutputFile -Force }
if (Test-Path $ErrorLogFile) { Remove-Item $ErrorLogFile -Force }
"Directory Error Log" | Out-File -FilePath $ErrorLogFile
"===================" | Out-File -FilePath $ErrorLogFile -Append

# Initialize the total directory count
$TotalDirectoryCount = 0
$DirectoryData = @()  # Array to store directory information

# Iterate through directories
Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $Directory = $_.FullName
        $Name = $_.Name
        $TotalDirectoryCount++  # Increment the directory count

        # Get size and last write time
        $SizeMB = Get-DirectorySize -Path $Directory
        $LastWriteTime = $_.LastWriteTime

        # Display output in real-time (PowerShell ISE + Console)
        Write-Host "Processing: $Name | Size: $SizeMB MB | Last Write Time: $LastWriteTime" -ForegroundColor Cyan

        # Create an object for structured CSV output
        $DirectoryInfo = [PSCustomObject]@{
            "Directory Name" = $Name
            "Size (MB)" = $SizeMB
            "Last Write Time" = $LastWriteTime
        }

        # Store the object in the array
        $DirectoryData += $DirectoryInfo
    }
    catch {
        # Log the error to the error log file
        $ErrorMessage = "$(Get-Date) - Error processing directory: '$($_.FullName)'. $_"
        Write-Host $ErrorMessage -ForegroundColor Red
        $ErrorMessage | Out-File -FilePath $ErrorLogFile -Append
        continue  # Continue processing next directories
    }
}

# Export data to CSV file
$DirectoryData | Export-Csv -Path $CsvOutputFile -NoTypeInformation

# Stop transcript logging
Stop-Transcript

# Display final summary results in PowerShell ISE
Write-Host ""
Write-Host "Total Directories Processed: $TotalDirectoryCount" -ForegroundColor Yellow
Write-Host "CSV Report Saved: $CsvOutputFile" -ForegroundColor Green
Write-Host "Error Log Saved: $ErrorLogFile" -ForegroundColor Yellow
Write-Host "Transcript Log Saved: $TranscriptFile" -ForegroundColor Cyan
