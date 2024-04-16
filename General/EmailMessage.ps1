$threshold = 64GB
$freeSpace = Get-PSDrive -Name "C"  | Select-Object Free

if ($freeSpace.Free -lt $threshold){

$EmailTo = "cmcleod1@umd.edu"
$EmailFrom = "cmcleod1@umd.edu"
$Subject = "Low Disk Space Warning"
$Body = "Your device is running low on disk space."
$SMTPServer = "smtp.gmail.com"
$SMTPPort = 587
$Username = "cmcleod1@umd.edu"
$Password = "your-app-password"  # This is the 16-character app password generated earlier

$SMTPInfo = @{
    To = $EmailTo
    From = $EmailFrom
    Subject = $Subject
    Body = $Body
    SmtpServer = $SMTPServer
    Port = $SMTPPort
    UseSsl = $true
    Credential = New-Object System.Management.Automation.PSCredential ($Username, ($Password | ConvertTo-SecureString -AsPlainText -Force))
}

Send-MailMessage @SMTPInfo
}