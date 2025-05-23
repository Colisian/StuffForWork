#Define source folder and destination folder

$sourceFolder = "Fonts_Rick" 
$destinationFolder = "C:\Windows\Fonts"

#Check if source folder exists
if (-not (Test-Path $destinationFolder)){
    Write-Output "The destination folder does not exist: $destinationFolder"
    exit 1
}

# Copy the fonts to the destination directory overwriting existing fonts
$fontExtensions = "*.ttf", "*.otf", "*.ttc", "*.PFB", "*.pfm"
$fonts = @()
foreach ($extension in $fontExtensions){
    $fonts += Get-ChildItem -Path $sourceFolder -Filter $extension -File
}
# Check if there are fonts to install
if ($fonts.Count -eq 0) {
    Write-Output "No fonts found in the source folder."
    exit 1
}

# Copy the fonts to the destination directory and register them

foreach ($font in $fonts){
    $destinationFontPath = Join-Path -Path $destinationFolder -ChildPath $font.Name
    try {
        Copy-Item -Path $font.FullName -Destination $destinationFontPath -Force -ErrorAction Stop
        Write-Output "Installed/Overwitten font: $($font.Name)"

        #Register the font
        $fontName = [System.IO.Path]::GetFileNameWithoutExtension($font.Name)
        $fontRegistryPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        Set-ItemProperty -Path $fontRegistryPath -Name $fontName -Value $font.Name -Force -ErrorAction Stop
        Write-Output "Registered font: $($font.Name)"
    } catch {
        Write-Output "Error installing font: $($font.Name) - Errot: $($_.Exception.Message)"
    }
}

# Refresh the font cache
# Refresh the font cache to ensure the new fonts are available immediately
try {
    Write-Output "Refreshing font cache..."
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class Gdi32 {
        [DllImport("gdi32.dll")]
        public static extern int AddFontResource(string lpFileName);
        [DllImport("gdi32.dll")]
        public static extern int RemoveFontResource(string lpFileName);
    }
"@
    foreach ($font in $fonts) {
        [Gdi32]::AddFontResource($font.FullName)
    }
    Write-Output "Font cache refreshed."
} catch {
    Write-Output "Failed to refresh font cache: $($_.Exception.Message)"
}