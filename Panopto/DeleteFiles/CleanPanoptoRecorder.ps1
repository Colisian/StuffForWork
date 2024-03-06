# Delete old Panopto Recorder files every 30 days

Get-ChildItem -Path "C:\PanoptoRecorder" -Recurse | 
Where-Object {
     $_.LastWriteTime -lt (Get-Date).AddDays(-7) -and 
     $_.FullName -notmatch "C:\\PanoptoRecorder\\eventLogs" -and
     $_.FullName -notmatch "C:\\PanoptoRecorder\\UCSUploads"
    } | 
    Remove-Item -Force -Recurse -Confirm:$false

<#Get-ChildItem cmdlet specifies the path to the "PanoptoRecorder" folder in the 
C:\ drive. 

The Where-Object cmdlet filters the list of files and subfolders to only 
include files that were last modified more than 30 days ago. 

Finally, the Remove-Item cmdlet deletes all files that match the filter criteria specified by the Where-Object 
cmdlet, with the -Force flag to bypass any prompts for confirmation.

$_.LastWriteTime is a property of the current object that represents the date and time 
the file was last modified. The -lt operator stands for "less than" and is used to compare 
the last write time of the current file with the current date and time minus 30 days. 

The Get-Date cmdlet retrieves the current date and time, and the .AddDays(-30) method subtracts 30 days from it. 
This means that the script block will evaluate to $true for any file that was last modified more than 30 days ago.
The purpose of this command is to filter the list of files and subfolders retrieved by 
Get-ChildItem to only include files that haven't been modified in the last 30 days. 
The filtered list is then passed down the pipeline to the Remove-Item cmdlet, which deletes the files. #>