#Define source folder and destination folder

$sourceFolder = "Fonts_Rick" 
$destinationFolder = "C:\Windows\Fonts"

#Check if source folder exists
if (-not (Test-Path $destinationFolder)){
    Write-Output "The destination folder does not exist: $destinationFolder"
    exit 1
}

# Copy the fonts to the destination directory overwriting existing fonts
$fonts = Get-ChildItem -Path $sourceFolder -Filter *.ttf, *.otf, *.ttc, *.PFB, *.pfm
foreach ($font in $fonts){
    $destinationFontPath = Join-Path -Path $destinationFolder -ChildPath $font.Name
    try {
        Copy-Item -Path $font.FullName -Destination $destinationFontPath -Force -ErrorAction Stop
        Wite-Output "Installed/Overwitten font: $($font.Name)"
    } catch {
        Write-Output "Error installing font: $($font.Name) - Errot: $($_.Exception.Message)"
    }
}

# Refresh the font cache
try{
    Write-Output "Refreshing font cache..."
    $null = Start-Proess -FilePath "C:\Wndows\System32\RunDll32.exe" -ArgumentList "shell32.dll,Control_RunDLL desk.cpl,,0" -NoNewWindow -Wait -ErrorAction Stop
    Write-Output "Font cache refreshed successfully"
} catch {
    Write-Output "Error refreshing font cache: $($_.Exception.Message)"
}