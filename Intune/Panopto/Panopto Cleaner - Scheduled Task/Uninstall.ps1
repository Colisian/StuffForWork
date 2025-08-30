#Start Transcript
Start-Transcript -Path "C:\PanoptoRecorder\PanoptoCleaner-Uninstall-Log.txt" -Force

#Loop to Confirm Removal of Scheduled Task
DO{
    $Exists = Get-ScheduledTask -TaskName 'Panopto Cleaner'
    if($Exists){
        Write-Host "Removing Scheduled Task: 'Panopto Cleaner'"
        Unregister-ScheduledTask -TaskName "Panopto Cleaner" -Confirm:$false}
    else{
        Write-Host "No Panopto Cleaner Task Exists"}}
    Until ($Exists -ne $true)
    Stop-Transcript