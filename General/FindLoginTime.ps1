#Specify the start and end date/time for logon events

$startDate = Get-Date "2024-09-06 11:00:00"  # 11 AM, 9/6/2024
$endDate = Get-Date "2024-09-09 09:00:00"    # 9 AM, 9/9/2024

#Path to output text file
$logFile = "C:\Scripts\LoginTimes.txt"


#Get all logon events from the Security log
$logonEvents = Get-WinEvent -LogName Security -FilterHashtable @{
    Id=4624
} | Where-Object {

    if($_.TimeCreated){

    
    $eventTime = $_.TimeCreated.ToLocalTime()
    $eventTime -ge $startDate -and $eventTime -le $endDate
    }
}
    # Prepare the header for the text file 
    "Username, Logon Time" | Out-File -FilePath $logFile -Encoding utf8

    # Process and output the list of users who logged in within the data/time range to the file
    $logonEvents | ForEach-Object {
        $userName = if ($_.Properties.Count -ge 6) {
        ($_.Properties[5].Value -as [string]) -or "UnknownUser"
       
        } else {
            "UnknownUser"
        }

        
        $logonTime = if($_.TimeCreated){

         $_.TimeCreated.ToLocalTime()  # Safely retrieve the logon time
        } else{
            "UnknownTime"
        }
        # Format th output
        $outputLine = "$userName, $logonTime"

        #Append the output to the text file
        $outputLine | Out-File -FilePath $logFile -Append -Encoding utf8
    }

    Write-Host "Logon times have been saved to $logFile"
