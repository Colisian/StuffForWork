#Define Paths
$BasePath = "E:\Department"
$CsvOutputFile = "C:\Scripts\SharedDriveUsage.csv"  # CSV file for structured data
$ErrorLogFile = "C:\Scripts\SharedDriveUsageError.txt"
$TranscriptFile = "C:\Scripts\SharedDriveUsageTranscript.txt"

#Strart transcript logging in a separate file
Start-Transcript -Path $TranscriptFile -Append

# Function to calculate directory size safely
function Get-FolderSize {
    param (
        [string]$Path
    )
    try {
        #Ensure the path is formatted correctly
        $CleanPath = $Path -replace '\s+$', ''  # Trim any trailing spaces
        
        #Get all files in the directory and its subdirect
        $Files = Get-ChildItem -Path $CleanPath -Recurse -File -ErrorAction SilentlyContinue

        #Handle empty directories
        if ($Files.Count -eq 0) {
            return 0
        }
        #Measure total size
        $Size = ($Files | Measure-Object -Property Length -Sum).Sum

        # Return size in MB
        if ($Size -is [double] -or $Size -is [int]) {
            return [math]::Round($Size / 1MB, 2)
        } else {
            return 0
        }
    } catch {
        #log the error
        $ErrorMessage = "$(Get-Date) - Error calculating size for: '$Path'. $_"
        Write-Host $ErrorMessage -ForegroundColor Red
        $ErrorMessage | Out-File -FilePath $ErrorLogFile -Append
        return 0
    }
}

#Prepare output files
if (Test-Path $CsvOutputFile) { Remove-Item $CsvOutputFile -Force }
if (Test-Path $ErrorLogFile) { Remove-Item $ErrorLogFile -Force }
"Department M Drive Error Log" | Out-File -FilePath $ErrorLogFile-Append
"=========================" | Out-File -FilePath $ErrorLogFile -Append

#Initialize the total directory count
$TotalDepartments = 0
$MDriveData = @()  # Array to store directory information

#Get the Departments M Drive
$Departments=Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue

foreach($Departments in $Departments){
    $DepartmentName = $Departments.Name
    $DepartmentPath = $Departments.FullName
    Write-Host "Processing Department: $DepartmentName" -ForegroundColor Green

    #Get the size of the directory
    $subDirectories = Get-ChildItem -Path $DepartmentPath -Directory -ErrorAction SilentlyContinue
foreach ($subDir in $subDirectories) {
    $subDirName = $subDir.Name
    $subDirPath = $subDir.FullName

    #Folder size
    $SizeMB = Get-FolderSize -Path $subDirPath
    #Display output in real-time
    Write-Host "Processing: $subDirName | Size: $SizeMB MB" -ForegroundColor Cyan


    #Create a custom object to store the data
    $subDirInfo = [PSCustomObject]@{
        "Department" = $DepartmentName
        "SubDirectory" = $subDirName
        "Size (MB)" = $SizeMB
    }

    #Add the object to the array
    $MDriveData += $subDirInfo

}

#Increment the total directory count
$TotalDepartments++

}# Export data to CSV file

# Display final results
Write-Host ""
Write-Host "Total Departments Processed: $TotalDepartments" -ForegroundColor Yellow
Write-Host "M Drive Usage Report saved to: $CsvOutputFile" -ForegroundColor Green
Write-Host "Error Log saved to: $ErrorLogFile" -ForegroundColor Yellow
Write-Host "Transcript Log saved to: $TranscriptFile" -ForegroundColor Cyan