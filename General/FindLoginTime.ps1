#Specify the start and end date/time for logon events

$startDate = Get-Date "2024-09-06 11:00:00"  # 11 AM, 9/6/2024 adjust as needed
$endDate = Get-Date "2024-09-09 09:00:00"    # 9 AM, 9/9/2024 adjust as needed

#Path to output text file
$logFile = "C:\Scripts\LoginTimes.txt"


#Get all logon events from the Security log
$logonEvents = Get-WinEvent -LogName Security  | Where-Object{
    #filter for logoff events which is 4634. Logon events are 4624
    $_.Id -eq 4634 -and $_.TimeCreated -ne $null -and
    $_.TimeCreated.ToLocalTime() -ge $startDate -and
    $_.TimeCreated.ToLocalTime() -le $endDate
    
}
    # Prepare the header for the text file 
    "User SID, Username, Logon Time" | Out-File -FilePath $logFile -Encoding utf8

    # Process and output the list of users who logged in within the data/time range to the file
    $logonEvents | ForEach-Object {
        #Extract event details
        $eventData = $_.Properties

        # Extract EventData fields by how they show up name
    $userSid = $_.Properties[0].Value        # TargetUserSid
    $userName = $_.Properties[1].Value       # TargetUserName
        
        $logonTime = if($_.TimeCreated){

         $_.TimeCreated.ToLocalTime()  # Safely retrieve the logon time
        } else{
            "UnknownTime"
        }
        # Format th output
        $outputLine = "$userSID ,$userName, $logonTime"

        #Append the output to the text file
        $outputLine | Out-File -FilePath $logFile -Append -Encoding utf8
    }

    Write-Host "Logon times have been saved to $logFile"
