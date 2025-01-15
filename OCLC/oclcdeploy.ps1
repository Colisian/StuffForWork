Start-Process -FilePath "msiexec.exe" -ArgumentList "/i Connexion.msi ALLUSERS=1 /qn /norestart" -Wait
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i OCLC.Connexion.ComServiceDeploy.msi ALLUSERS=1 /qn /norestart" -Wait
Start-Process -FilePath "accessdatabaseengine_X64.exe" -ArgumentList "/quiet /norestart" -Wait