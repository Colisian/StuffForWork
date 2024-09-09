#Specify the start and end date/time for logon events

$startDate = [datetime]:: ParseExact("2024-09-06 11:00:00", "yyyy-MM-dd HH:mm:ss", $null)
$endDate = [datetime]:: ParseExact("2024-09-09 9:00:00", "yyyy-MM-dd HH:mm:ss", $null)

#Path to output text file
$logFile = "C:\Scripts\LoginTimes.txt"

#Get all logon events from the Security log
$logonEvents = Get-WinEvent -LogName Security -FilterHashtable @{Id=4624} -ErrorAction SilentlyContinue |
    Where-Object {
        $eventTime = $_.TimeCreated.ToLocalTime() #Convert event time to local time
        $eventTime -ge $startDate -and $eventTime -le $endDate #Check if event occured during the specified time range
    }

    # Prepare the header for the text file 
    "Username, Logon Time" | Out-File -FilePath $logFile -Encoding utf8

    # Process and outpit the list of users who logged in within the data/time range to the file
    $logonEvents | ForEach-Object {
        $eventData = $_.Properties[5].Value
        $logonTime = $_.TimeCreated.ToLocalTime()
        
        # Format th output
        $outputLine = "$eventData, $logonTime"

        #Append the output to the text file
        $outputLine | Out-File -FilePath $logFile -Append -Encoding utf8
    }

    Write-Host "Logon times have been saved to $logFile"
