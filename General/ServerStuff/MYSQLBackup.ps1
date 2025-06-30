$mysqlUser = "root"
$mysqlPassword = "password"
$mysqlDatabase = "SYSAID"
$backupPath = "C:\MySQLBackups"
$mysqldumpPath = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqldump.exe"

if (-not (Test-Path $backupPath)) {
    New-Item -Path $backupPath -ItemType Directory | Out-Null
}

# Get the current date and time for the backup filename
$date = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupPath "${mysqlDatabase}_$date.sql"

# Create the backup using mysqldump
try {
    $proc = Start-Process -FilePath $mysqldumpPath -ArgumentList "--user=$mysqlUser", "--password=$mysqlPassword", "--databases", "$mysqlDatabase", "--result-file=$backupFile" -PassThru -Wait
    Write-Host "MySQL backup created successfully: $backupFile" -ForegroundColor Green
} catch {
    Write-Host "Error creating MySQL backup: $_" -ForegroundColor Red
}

#Delete backups older than 3 days
Get-ChildItem -Path $backupPath -Filter "$mysqlDatabase-*.sql" | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-3)
} | Remove-Item -Force