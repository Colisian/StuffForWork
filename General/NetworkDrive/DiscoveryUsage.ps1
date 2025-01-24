$BasePath = "H:\userhome"
$OutPutFile = "C:\Scripts\DiscoveryUsage.txt"

Start-Transcript -Path $OutPutFile -Append

function Get-DirectorySize {
    param (
        [string]$Path
    )
    try {
        #Get total sie of all the files in the directory
        $size =(Get-ChildItem -Path $Path -Recurse | Measure-Object -Property Length -Sum).Sum
        #Convert the size to MB
        return [math]::Round($size / 1MB, 2)
    }
    catch {
        Write-Host "Error calculating size for: $Path. $_"
        return 0
    }
    
}

#Prepare output file

if (Test-Path $OutPutFile) {
    Remove-Item $OutPutFile -Force
}
"Directory USage Report" | Out-File -FilePath $OutPutFile 
"======================" | Out-File -FilePath $OutPutFile -Append

#Initialize the total directory count
$TotalDirectoryCount = 0

#Iterate through directories
Get-ChildItem -Path $BasePath -Directory | ForEach-Object {
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
    $Output | Out-File -FilePath $OutPutFile -Append
}

#Add total directory count to the output file
"========================" | Out-File -FilePath $OutPutFile -Append
"Total Directories: $TotalDirectoryCount" | Out-File -FilePath $OutPutFile -Append

#Stop transcript
Stop-Transcript

Write-Host "Total Directories: $TotalDirectoryCount"