#Define source folder and destination folder

$sourceFolder = "Fonts_Rick" 
$destinationFolder = "C:\Windows\Fonts"

#Check if source folder exists
if (-not (Test-Path $destinationFolder)){
    Write-Output "The destination folder does not exist: $destinationFolder"
    exit 1
}

# Copy the fonts to the destination directory overwriting existing fonts
$fontExtensions = @("*.ttf", "*.otf", "*.ttc", "*.PFB", "*.pfm")
$fonts = Get-ChildItem -Path $sourceFolder -Include $fontExtensions -File
foreach ($font in $fonts){
    $destinationFontPath = Join-Path -Path $destinationFolder -ChildPath $font.Name
    try {
        Copy-Item -Path $font.FullName -Destination $destinationFontPath -Force -ErrorAction Stop
        Write-Output "Installed/Overwitten font: $($font.Name)"
    } catch {
        Write-Output "Error installing font: $($font.Name) - Errot: $($_.Exception.Message)"
    }
}
