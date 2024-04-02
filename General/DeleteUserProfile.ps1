# powershell.exe -executionpolicy bypass -file .\DeleteUserProfile.ps1 


# Get all user profiles, exluding system profiles
$userProfiles = Get-CimInstance -Class Win32_UserProfile | Where-Object {$_.LastUseTime -lt (Get-Date).Date}
$userprofiles.LocalPath

# Iterate through each user profile
foreach ($profile in $userProfiles) {
    try {
        #mae sure the profile is not the system account
        if($profile -ne $null -and !$profile.Special){
            Write-Host "Deleting user profile: $($profile.LocalPath.split('\')[-1])"
            $profile.Delete()
        }
    }
    catch {
        Write-Host "Failed to delete user profile: $($profile.LocalPath.split('\')[-1])"
    }
}