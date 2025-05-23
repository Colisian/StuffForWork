# powershell.exe -executionpolicy bypass -file .\ibmspss.ps1 

$msiPath = ".\ibmspss.msi"
$licenseServer = "athos@umd.edu"
$msiArgs =  @(msiexec /i "ibmspss.msi" /qn SPSSLICENSE="Network"  LSHOST= $licenseServer 
SPSS_COMMUTE_MAX_LIFE="30")

Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru