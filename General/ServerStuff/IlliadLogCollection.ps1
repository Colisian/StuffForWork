#Config
$sourceDir = "C:\illiad\dll"
$destDir = "C:\illiadlogs"

#Ensure Directory Exist

if(-not (Test-Path $destDire)){
    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
}

#Clean up old files
Get-ChildItem -Path $destDir -File | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-14) } | Remove-Item -Force 

#Copy files to destination
$todayPrefix = (Get-Date).ToString('M.d')
Get-ChildItem -Path $sourceDir -File | ForEach-Object {
    $newName = "$todayPrefix'_$($_.Name)"
    Copy-Item -Path $_.FullName -Destination (Join-Path -Path $destDir -ChildPath $newName) -Force

}

