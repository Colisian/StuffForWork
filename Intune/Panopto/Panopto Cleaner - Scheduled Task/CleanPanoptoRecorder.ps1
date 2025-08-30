#Define the path
$path = "C:\PanoptoRecorder"
#Define the exclusion list
$exclusionList = @('eventlogs', 'UCSUploads')
# Get all files in the current directory and its subdirectories
$items = Get-ChildItem -Path $path -Recurse | Where-Object { !$_.PSIsContainer }
# Filter out the items from the exclusion list and those that are not older than 1 day
$itemsToDelete = $items | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) -and $_.Directory.Name -notin $exclusionList }
# Delete the filtered items
foreach ($item in $itemsToDelete) {
    Remove-Item $item.FullName -Force
}
# Output the deleted items
$itemsToDelete
