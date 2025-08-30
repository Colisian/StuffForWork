#======================================================================================
#   Script
$TaskScript = @'
#Define the path
$path = "C:\PanoptoRecorder"
#Define the exclusion list
$exclusionList = @('eventlogs', 'UCSUploads')
# Get all files in the current directory and its subdirectories
$items = Get-ChildItem -Path $path -Recurse | Where-Object { !$_.PSIsContainer }
# Filter out the items from the exclusion list and those that are not older than 7 days
$itemsToDelete = $items | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) -and $_.Directory.Name -notin $exclusionList }
# Delete the filtered items
foreach ($item in $itemsToDelete) {
    Remove-Item $item.FullName -Force
}
# Output the deleted items
$itemsToDelete
'@
#======================================================================================
#   Encode the Script
$EncodedCommand = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($TaskScript))