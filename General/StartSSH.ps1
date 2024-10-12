#Check if OpenSSH Client and Server is installed
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.*' | Select-Object State, Name

#Install OpenSSH Client/Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

#Start the SSH Server
Start-Service sshd

#Set the SSH Server to start automatically
Set-Service -Name sshd -StartupType 'Automatic'

#Create a firewall rule to allow inbound SSH traffic
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22