$BasePath = "H:\userhome"
$OutPutFile = "C:\Scripts\DiscoveryUsage.txt"
$ErrorLogFile = "C:\Scripts\DiscoveryUsageError.txt"
$TranscriptFile = "C:\Scripts\DiscoveryUsageTranscript.txt"

Start-Transcript -Path $TranscriptFile -Append

function Get-DirectorySize {
    param (
        [string]$Path
    )
    try {
        #Get total sie of all the files in the directory
        $size =(Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        #Convert the size to MB
        if ($size -is [double]) {
            return [math]::round($size / 1MB, 2)
        } else {
            return = 0
        }
    }
    catch {
        Write-Host "Error calculating size for: $Path. $_"
        #log Error to error log file
        $_ | Out-File -FilePath $ErrorLogFile -Append
        return 0
    }
    
}

#Prepare output file

if (Test-Path $OutPutFile) {
    Remove-Item $OutPutFile -Force
}
"Directory USage Report" | Out-File -FilePath $OutPutFile 
"======================" | Out-File -FilePath $OutPutFile -Append

if (Test-Path $ErrorLogFile) {
    Remove-Item $ErrorLogFile -Force
}

"Directory Error Log" | Out-File -FilePath $ErrorLogFile
"====================" | Out-File -FilePath $ErrorLogFile -Append

#Initialize the total directory count
$TotalDirectoryCount = 0

#Iterate through directories
Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {

    try{ 
    $Directory = $_.Fullname
    $Name = $_.Name

    #Increment the total directory count
    $TotalDirectoryCount++

    #Get the size of the directory
    $SizeMB = Get-DirectorySize -Path $Directory

    #Get last write time
    $LastWriteTime = $_.LastWriteTime

    #Output the directory details
    $Output = "Directory: $Name, Size: $SizeMB MB, Last Write Time: $LastWriteTime"
    
    Write-Host $Output
    "" | Out-File -FilePath $OutputFile -Append
    $Output | Out-File -FilePath $OutPutFile -Append
    "" | Out-File -FilePath $OutputFile -Append
} catch {
    # Log the error to the error log file
    $ErrorMessage = "Error processing directory: $($_.FullName). $_"
    Write-Host $ErrorMessage -ForegroundColor Red
    $ErrorMessage | Out-File -FilePath $ErrorLogFile -Append
    "" | Out-File -FilePath $ErrorLogFile -Append  # Add a blank line in error file
    # Continue processing other directories
    continue
}
}


#Add total directory count to the output file
"========================" | Out-File -FilePath $OutPutFile -Append
"Total Directories: $TotalDirectoryCount" | Out-File -FilePath $OutPutFile -Append

#Stop transcript
Stop-Transcript

# Display final results
Write-Host "Total Directories: $TotalDirectoryCount" -ForegroundColor Yellow
Write-Host ""  # Add space
Write-Host "Directory Usage Report saved to: $OutputFile" -ForegroundColor Green
Write-Host "Error log saved to: $ErrorLogFile" -ForegroundColor Yellow
Write-Host "Transcript log saved to: $TranscriptFile" -ForegroundColor Cyan
Write-Host ""  # Add space