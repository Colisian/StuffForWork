# Define the path for the output CSV report.
$reportPath = "C:\DirectorySizeReport.csv"

Write-Output "Scanning directories on C: drive. This may take a while..."

# Get all directories on the C: drive recursively.
$directorySizes = Get-ChildItem -Path "C:\" -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $folder = $_.FullName
    # Calculate the size of each directory by summing the sizes of all files within it.
    try {
        $size = (Get-ChildItem -Path $folder -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    }
    catch {
        $size = 0
    }
    # Create a custom object with the folder path and sizes in bytes, MB, and GB.
    [PSCustomObject]@{
        Directory = $folder
        SizeMB    = if ($size) { [math]::Round($size / 1MB, 2) } else { 0 }
        SizeGB    = if ($size) { [math]::Round($size / 1GB, 2) } else { 0 }
    }
} | Where-Object { $_.SizeGB -gt 1 }  # Only include directories with more than 1 GB of space used.

# Sort the results so that the directories with the most space used appear first.
$sortedDirectorySizes = $directorySizes | Sort-Object -Property SizeGB -Descending

# Output the results to the console in a table format.
$sortedDirectorySizes | Format-Table -AutoSize

# Export the report to a CSV file for further review.
$sortedDirectorySizes | Export-Csv -Path $reportPath -NoTypeInformation

Write-Output "Report has been saved to $reportPath"
