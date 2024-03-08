$msiPath = ".\ibmspss.msi"
$licenseServer = "athos@umd.edu"
$msiArgs =  @(
    "/i", 
    "`"$msiPath`"", 
    "/qn", 
    "COMPANYNAME=`"University of Maryland`"", 
    "SPSSLICENSE=`"Network`"",
    "LSHOST=`"$licenseServer`""
)
Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru