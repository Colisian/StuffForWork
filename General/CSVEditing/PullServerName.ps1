<#
.SYNOPSIS
    Prompts for an input CSV path and an output CSV path, then filters for rows containing "Windows Server".

#>
# Load the VB helper for simple input boxes
Add-Type -AssemblyName Microsoft.VisualBasic

# Prompt for the source CSV
$InputFile = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Paste the full path to your input CSV file:",
    "Input CSV Path"
)

# If the user hit Cancel or left it blank, exit
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    Write-Warning "No input file specified. Exiting."
    exit
}

# Prompt for where to save the filtered CSV
$OutputFile = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Paste the full path where you'd like to save the filtered CSV:",
    "Output CSV Path",
    # Suggest a default filename next to the input file
    ([System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($InputFile),
        [System.IO.Path]::GetFileNameWithoutExtension($InputFile) + "_WindowsServer.csv"
    ))
)

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    Write-Warning "No output file specified. Exiting."
    exit
}

# Define the term to search for
$SearchTerm = "Windows Server"

# Import, filter, and export
try {
    $data = Import-Csv -Path $InputFile
} catch {
    Write-Error "Failed to read '$InputFile'. $_"
    exit
}

$filtered = $data | Where-Object {
    ($_.PSObject.Properties.Value -join ' ') -match [regex]::Escape($SearchTerm)
}

if ($filtered.Count -gt 0) {
    $filtered | Export-Csv -Path $OutputFile -NoTypeInformation
    Write-Host "✅ Filtered $($filtered.Count) rows containing '$SearchTerm' to '$OutputFile'."
} else {
    Write-Host "⚠️ No rows containing '$SearchTerm' were found in '$InputFile'. No file written."
}
