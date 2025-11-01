# MySQL Configuration
$mysqlDatabase = "SYSAID"
$backupPath = "C:\MySQLBackups"
$mysqldumpPath = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqldump.exe"
$mysqlConfigFile = "C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf"

# Verify config file exists
if (-not (Test-Path $mysqlConfigFile)) {
    Write-Host "Error: MySQL config file not found at $mysqlConfigFile" -ForegroundColor Red
    Write-Host "Please create the file with the following content:" -ForegroundColor Yellow
    Write-Host "[client]" -ForegroundColor Yellow
    Write-Host "user=root" -ForegroundColor Yellow
    Write-Host "password=your_password" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Then secure it with:" -ForegroundColor Yellow
    Write-Host "icacls `"$mysqlConfigFile`" /inheritance:r /grant:r `"SYSTEM:(F)`" `"Administrators:(F)`"" -ForegroundColor Yellow
    exit
}

if (-not (Test-Path $backupPath)) {
    New-Item -Path $backupPath -ItemType Directory | Out-Null
}

# Get the current date and time for the backup filename
$date = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupPath "${mysqlDatabase}_$date.sql"

# Create the backup using mysqldump with config file
try {
    $proc = Start-Process -FilePath $mysqldumpPath -ArgumentList "--defaults-extra-file=$mysqlConfigFile", "--databases", "$mysqlDatabase", "--result-file=$backupFile" -PassThru -Wait -NoNewWindow

    if ($proc.ExitCode -eq 0) {
        Write-Host "MySQL backup created successfully: $backupFile" -ForegroundColor Green
    } else {
        Write-Host "MySQL backup failed with exit code: $($proc.ExitCode)" -ForegroundColor Red
    }
} catch {
    Write-Host "Error creating MySQL backup: $_" -ForegroundColor Red
}

#Delete backups older than 3 days
Get-ChildItem -Path $backupPath -Filter "$mysqlDatabase-*.sql" | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-3)
} | Remove-Item -Force