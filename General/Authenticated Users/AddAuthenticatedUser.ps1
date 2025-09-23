# Add-AuthenticatedUsers-UserRights.ps1
# Adds "Authenticated Users" to interactive and RDP logon rights.
# WARNING: test on one device first. Use Domain Users or a scoped security group instead of Authenticated Users where possible.

$cfg = "C:\Windows\Temp\secpol.cfg"
$db = "C:\Windows\security\local.sdb"

# export current user rights to file (Unicode)
secedit /export /cfg $cfg | Out-Null

# read file in as single string (keep the file encoding)
$text = Get-Content -Path $cfg -Raw -Encoding Unicode

function Add-OrAppendRight {
    param($rightName, $accountName)
    if ($text -match "(?m)^$rightName\s*=\s*(.*)$") {
        $current = $Matches[1].Trim()
        if ($current -eq "") {
            $new = $accountName
        } elseif ($current -notmatch [regex]::Escape($accountName)) {
            $new = "$current,$accountName"
        } else {
            return  # already present
        }
        $text = $text -replace "(?m)^($rightName\s*=\s*).*","`$1$new"
    } else {
        # append new line at end
        $text += "`r`n$rightName = $accountName`r`n"
    }
}

# Use a less-broad account if possible (Domain Users / <your SG>).
$accountToAdd = "Authenticated Users"

Add-OrAppendRight -rightName "SeInteractiveLogonRight" -accountName $accountToAdd
Add-OrAppendRight -rightName "SeRemoteInteractiveLogonRight" -accountName $accountToAdd

# write back file as Unicode
Set-Content -Path $cfg -Value $text -Encoding Unicode

# apply only user rights area
secedit /configure /db $db /cfg $cfg /areas USER_RIGHTS

# cleanup and optional verification export
secedit /export /cfg $cfg | Out-Null
Write-Output "Completed. Please reboot or run gpupdate /force and test sign-in."