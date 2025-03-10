<#

    This script will reset the password for the specified  user.
#>

#Define the Username and Password for the Account to be Reset
$user = "LibCirc"
$password = ""

try{
    Write-Output "Attempting to reset the password for $($user)"
    #Reset the Password using CMD
    cmd.exe /c "net user $user $password"
    #Confirm Password has been reset
    $usr = [ADSI]"WinNT://$env:ComputerName/$($user),user"
    $ResetStatus = $usr.PasswordExpired
    #Output Result
    if ($ResetStatus){
        Write-Error "Password is still flagged for reset"
        Exit 1}
    else {
        Write-Output "Password has been successfully reset"
        Exit 0}
    }
Catch {
    Write-error $_
    Exit 1}
