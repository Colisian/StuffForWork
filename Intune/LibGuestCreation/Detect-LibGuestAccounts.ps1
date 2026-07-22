<#
.SYNOPSIS
    Intune Win32 detection script. Detected = last account in the list exists
    locally AND its Kerberos UserList mapping is present.

.NOTES
    Intune reads: exit code 0 + non-empty STDOUT = installed.
    Upload this file as a "custom detection script" on the Win32 app.
    Do NOT include it in the .intunewin source folder requirement-wise; it is
    uploaded separately in the app's detection rules blade.
#>

$Realm       = 'UMD.EDU'
$UserListKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList'
$Sentinel    = 'libguest500'   # last account created; proves the loop finished

try {
    $user = Get-LocalUser -Name $Sentinel -ErrorAction Stop
    $map  = Get-ItemProperty -Path $UserListKey -Name "$Sentinel@$Realm" -ErrorAction Stop
    if ($user -and $map) {
        Write-Output 'Detected'
        exit 0
    }
}
catch { }
exit 1
