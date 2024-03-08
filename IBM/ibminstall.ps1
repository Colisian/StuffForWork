$msiPath = ".\ibmspss.msi"
$licenseServer = "athos@umd.edu"
$msiArgs = @("/i", 
            $msiPath, 
            "/qn", 
            SPSSLICENSE="Network",
            LSHOST=$licenseServer)

Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait