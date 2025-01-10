
#BasePath
$BasePath = "H:\userhome" #Change this to the path of the userhome folder on the server
$Domain = "AD" #Domain prefix for the users accounts
$LogFile = "C:\Logs\ZDriveSetUp.log"

#Start logging
Start-Transcript -Path $LogFile -Append

#Function to create Z Drive Folder and set Permissions
function Create-ZDrive {
    param(
        [string]$UserID
    )
    $UserFolder = Join-Path $BasePath $UserID

    #Create the user folder
    if (-not (Test-Path $UserFolder)) {
        New-Item -Path $UserFolder -ItemType Directory
        Write-Host "User folder created: $UserFolder"
    } else {
        Write-Host "User folder already exists: $UserFolder" 
    }

    #Set permissions on the user folder
    Try{
        $Acl = Get-Acl -Path $UserFolder
        $User = $Domain\$UserID

        #Grant Full Control to the user
        $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($User, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.AddAccessRule($AccessRule)

        #Disable inheritance and convert to explicit permissions
        $Acl.SetAccessRuleProtection($true, $true)

        #Apply the new ACL to the folder
        Set-Acl -Path $UserFolder -AclObject $Acl

        Write-Host "Permissions set for user: $UserID"

    } catch {
        Write-Host "Error setting permissions for user: $UserID"
        Write-Host $_.Exception.Message
    }
}
