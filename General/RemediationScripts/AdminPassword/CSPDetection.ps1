<#
.DESCRIPTION
    This script will check if the specified account is flagged for reset or not.
#>

#Define the Username of the Account to Check
$user = "CSPAdmin"

#Check the Password status of the Defined Username
$usr = [ADSI]"WinNT://$env:ComputerName/$($user),user"
$PasswordStatus = $usr.PasswordExpired

#Output Result
if ($PasswordStatus){
  Write-Output "$($user) is flagged for reset" 
  Exit 1} 
Else {
  Write-Output "$($user) is not flagged for reset"
  Exit 0}