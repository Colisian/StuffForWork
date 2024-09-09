#Specify the start and end date/time for logon events

$startDate = [datetime]::ParseExact("2024-09-06 11:00:00", "yyyy-MM-dd HH:mm:ss", $null)
$endDate = [datetime]::ParseExact("2024-09-09 9:00:00", "yyyy-MM-dd HH:mm:ss", $null)

#Path to output text file
$logFile = "C:\Scripts\LoginTimes.txt"

#Get all logon events from the Security log
$logonEvents = Get-WinEvent -LogName Security -FilterHashtable @{
    Id=4624
    StartTime=$startDate
    EndTime=$endDate

} 

    # Prepare the header for the text file 
    "Username, Logon Time" | Out-File -FilePath $logFile -Encoding utf8

    # Process and outpit the list of users who logged in within the data/time range to the file
    $logonEvents | ForEach-Object {
        $userName = ($_.Properties[5].Value -as [string]) -or "UnknownUser"
        $logonTime = $_.TimeCreated.ToLocalTime()
        
        # Format th output
        $outputLine = "$userName, $logonTime"

        #Append the output to the text file
        $outputLine | Out-File -FilePath $logFile -Append -Encoding utf8
    }

    Write-Host "Logon times have been saved to $logFile"
