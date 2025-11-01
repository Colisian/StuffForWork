# MySQL SYSAID Database Backup Documentation

## Overview
This documentation covers the automated MySQL backup system for the SYSAID database. The backup script runs daily via Windows Task Scheduler and maintains a rolling 3-day backup history.

## System Components

### Files and Locations
- **Backup Script**: `MYSQLBackup.ps1` (location: same directory as this documentation)
- **MySQL Credentials File**: `C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf`
- **Backup Storage**: `C:\MySQLBackups`
- **MySQL Installation**: `C:\Program Files\MySQL\MySQL Server 5.7\`
- **Database Name**: `SYSAID`

### Backup Retention
- Backups are created daily with timestamp format: `SYSAID_YYYYMMDD_HHMMSS.sql`
- Backups older than **3 days** are automatically deleted
- All backups are stored in: `C:\MySQLBackups`

---

## Initial Setup

### 1. Create MySQL Credentials File

The backup uses a secure configuration file instead of hardcoding passwords in the script.

**Create the credentials file at**: `C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf`

**File contents**:
```ini
[client]
user=root
password=your_actual_mysql_password
```

### 2. Secure the Credentials File

**CRITICAL**: This file contains the MySQL root password and must be secured.

Run this command in PowerShell (as Administrator):
```powershell
icacls "C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf" /inheritance:r /grant:r "SYSTEM:(F)" "cmcleod1.admin:(F)"
```

This ensures only SYSTEM and the admin account can read the file.

### 3. Create Scheduled Task

The backup should run automatically via Windows Task Scheduler.

**Option A: PowerShell Setup (Recommended)**

Run this in PowerShell as Administrator:

```powershell
# Update the path to match your script location
$scriptPath = "C:\Path\To\MYSQLBackup.ps1"

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "MySQL SYSAID Backup" -Action $action -Trigger $trigger -Principal $principal -Description "Daily backup of SYSAID MySQL database"
```

**Option B: Task Scheduler GUI**

1. Open **Task Scheduler** (`taskschd.msc`)
2. Click **Create Task** (not Create Basic Task)
3. **General Tab**:
   - Name: `MySQL SYSAID Backup`
   - Description: `Daily backup of SYSAID MySQL database`
   - Select: "Run whether user is logged on or not"
   - Check: "Run with highest privileges"
   - Configure for: Windows Server 2016 (or your OS version)
4. **Triggers Tab**:
   - Click **New**
   - Begin the task: On a schedule
   - Settings: Daily at 2:00 AM
   - Click **OK**
5. **Actions Tab**:
   - Click **New**
   - Action: Start a program
   - Program/script: `PowerShell.exe`
   - Add arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\MYSQLBackup.ps1"`
   - Click **OK**
6. **Settings Tab**:
   - Allow task to be run on demand: Checked
   - If the task fails, restart every: 10 minutes
   - Attempt to restart up to: 3 times
7. Click **OK** and enter credentials when prompted

---

## How the Backup Works

1. **Credential Verification**: Script checks if the credentials file exists
2. **Directory Creation**: Creates `C:\MySQLBackups` if it doesn't exist
3. **Timestamp Generation**: Creates unique filename with current date/time
4. **Database Dump**: Uses `mysqldump` to export the SYSAID database
5. **Cleanup**: Removes backups older than 3 days

### Security Features
- Credentials stored in separate, secured configuration file
- Password never appears in command line or process list
- File permissions restrict access to SYSTEM and Administrators only

---

## Maintenance & Troubleshooting

### Testing the Backup Manually

Run the script manually in PowerShell:
```powershell
cd "C:\Path\To\Script\Directory"
.\MYSQLBackup.ps1
```

You should see:
```
MySQL backup created successfully: C:\MySQLBackups\SYSAID_20250101_020000.sql
```

### Common Issues

**Issue: "MySQL config file not found"**
- **Solution**: Create the `backup_credentials.cnf` file at the specified location (see Setup Step 1)

**Issue: "Access denied for user 'root'"**
- **Solution**: Verify the password in `backup_credentials.cnf` is correct
- Test MySQL connection: `mysql -u root -p`

**Issue: "mysqldump: command not found"**
- **Solution**: Verify MySQL installation path in the script matches your system
- Update `$mysqldumpPath` variable if needed

**Issue: Scheduled task not running**
- **Solution**: Check Task Scheduler History
  - Open Task Scheduler
  - Enable History (Actions > Enable All Tasks History)
  - Right-click task > View History
- Verify the task is set to "Run whether user is logged on or not"
- Ensure SYSTEM account has permissions to the script and credentials file

**Issue: Backups not being deleted after 3 days**
- **Solution**: The filter pattern in line 42 is `"$mysqlDatabase-*.sql"` but backups are created as `${mysqlDatabase}_*.sql`
- This is a known issue - the cleanup filter doesn't match the backup naming convention

### Checking Backup Integrity

Verify a backup file is valid:
```powershell
# Check file size (should be several MB, not 0 bytes)
Get-ChildItem "C:\MySQLBackups\SYSAID_*.sql" | Select-Object Name, Length, LastWriteTime

# Test restore (to a test database)
mysql -u root -p test_database < "C:\MySQLBackups\SYSAID_20250101_020000.sql"
```

---

## Modifying the Configuration

### Change Backup Schedule
Edit the scheduled task trigger in Task Scheduler or update the PowerShell setup command.

### Change Retention Period
Edit line 42-44 in `MYSQLBackup.ps1`:
```powershell
# Change -3 to desired number of days
$_.LastWriteTime -lt (Get-Date).AddDays(-3)
```

### Change Backup Location
Update the `$backupPath` variable at the top of the script:
```powershell
$backupPath = "C:\MySQLBackups"  # Change this path
```

### Add Email Notifications
Add email notification on failure by installing and using `Send-MailMessage` in the catch block.

---

## SysAid System Restore Procedure

### IMPORTANT: Before You Begin

**WARNING**: Restoring a database will **permanently overwrite** all current data with the backup data. This action cannot be undone.

**Pre-Restore Checklist**:
- [ ] Identify the correct backup file to restore (verify timestamp and file size)
- [ ] Notify all users that SysAid will be unavailable during restoration
- [ ] Document the reason for the restore (data corruption, user error, system failure, etc.)
- [ ] Create a current backup before restoring (if system is still functional)
- [ ] Verify you have MySQL root credentials available
- [ ] Ensure sufficient disk space (backup file size + 2x for temporary operations)
- [ ] Plan for potential data loss (any changes made after the backup timestamp will be lost)

---

### Restore Scenarios

#### Scenario 1: Complete Database Restore (System Failure)
Use this when the entire SysAid database is corrupted or lost.

#### Scenario 2: Partial Data Recovery
Use this when specific data needs to be recovered but the system is still running.

#### Scenario 3: System Migration
Use this to move SysAid to a new server.

---

### Full Database Restore Procedure

#### Step 1: Identify the Backup File

List available backups:
```powershell
Get-ChildItem "C:\MySQLBackups\SYSAID_*.sql" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
```

Example output:
```
Name                        Length      LastWriteTime
----                        ------      -------------
SYSAID_20250101_020000.sql  52428800    1/1/2025 2:00:00 AM
SYSAID_20250102_020000.sql  52534016    1/2/2025 2:00:00 AM
SYSAID_20250103_020000.sql  52641232    1/3/2025 2:00:00 AM
```

**Choose the appropriate backup** based on:
- **Timestamp**: Select a backup from before the issue occurred
- **File Size**: Verify file size is reasonable (typical size should be consistent unless major changes occurred)

#### Step 2: Stop SysAid Services

Stop all SysAid-related services to prevent database access during restoration:

```powershell
# Stop the SysAid Server service
Stop-Service -Name "SysAidServer" -Force

# Verify service is stopped
Get-Service -Name "SysAidServer" | Select-Object Name, Status

# If SysAid has additional services, stop them too:
# Stop-Service -Name "SysAidAgent" -Force
```

**Wait 30 seconds** to ensure all database connections are closed.

#### Step 3: Verify MySQL Service is Running

```powershell
# Check MySQL service status
Get-Service -Name "MySQL*" | Select-Object Name, Status

# Start MySQL if it's not running
Start-Service -Name "MySQL57"  # Adjust name based on your version
```

#### Step 4: Create Emergency Backup (If Possible)

If the current database is still accessible, create an emergency backup:

```powershell
$emergencyBackup = "C:\MySQLBackups\SYSAID_EMERGENCY_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"

& "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqldump.exe" --defaults-extra-file="C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf" --databases SYSAID --result-file="$emergencyBackup"

Write-Host "Emergency backup created: $emergencyBackup" -ForegroundColor Green
```

#### Step 5: Drop Existing Database (Critical Step)

**WARNING**: This deletes all current data in the SYSAID database.

```powershell
# Connect to MySQL and drop the database
$mysqlPath = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe"
$configFile = "C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf"

& $mysqlPath --defaults-extra-file=$configFile -e "DROP DATABASE IF EXISTS SYSAID;"

Write-Host "Existing SYSAID database dropped" -ForegroundColor Yellow
```

#### Step 6: Restore from Backup

Restore the selected backup file:

```powershell
# Set the backup file to restore
$backupFile = "C:\MySQLBackups\SYSAID_20250103_020000.sql"

# Verify file exists
if (-not (Test-Path $backupFile)) {
    Write-Host "ERROR: Backup file not found: $backupFile" -ForegroundColor Red
    exit
}

# Restore the database
Write-Host "Starting database restore from: $backupFile" -ForegroundColor Cyan
Write-Host "This may take several minutes depending on database size..." -ForegroundColor Cyan

$mysqlPath = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe"
$configFile = "C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf"

& $mysqlPath --defaults-extra-file=$configFile < $backupFile

if ($LASTEXITCODE -eq 0) {
    Write-Host "Database restore completed successfully!" -ForegroundColor Green
} else {
    Write-Host "ERROR: Database restore failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Check MySQL error logs for details" -ForegroundColor Red
    exit
}
```

#### Step 7: Verify Database Restoration

Verify the database was restored correctly:

```powershell
# Check that SYSAID database exists
& $mysqlPath --defaults-extra-file=$configFile -e "SHOW DATABASES LIKE 'SYSAID';"

# Check table count
& $mysqlPath --defaults-extra-file=$configFile -e "USE SYSAID; SHOW TABLES;" | Measure-Object -Line

# Check a sample table for data
& $mysqlPath --defaults-extra-file=$configFile -e "USE SYSAID; SELECT COUNT(*) as 'Total Records' FROM users;" 2>$null
```

Expected results:
- SYSAID database should be listed
- Table count should match expected number of tables
- Sample queries should return data

#### Step 8: Start SysAid Services

Restart the SysAid services:

```powershell
# Start the SysAid Server service
Start-Service -Name "SysAidServer"

# Wait for service to fully start
Start-Sleep -Seconds 10

# Verify service is running
Get-Service -Name "SysAidServer" | Select-Object Name, Status

# Check if service is running properly
if ((Get-Service -Name "SysAidServer").Status -eq "Running") {
    Write-Host "SysAid Server service started successfully!" -ForegroundColor Green
} else {
    Write-Host "WARNING: SysAid Server service failed to start!" -ForegroundColor Red
    Write-Host "Check SysAid logs for errors" -ForegroundColor Red
}
```

#### Step 9: Verify SysAid Functionality

1. **Access SysAid Web Interface**:
   - Navigate to SysAid web portal (typically `http://servername:8080`)
   - Verify login page loads

2. **Test Login**:
   - Log in with an administrator account
   - Verify successful authentication

3. **Verify Data**:
   - Check recent tickets to confirm data from backup timeframe
   - Verify user accounts are present
   - Check asset inventory
   - Test creating a test ticket

4. **Check for Errors**:
   - Review SysAid logs: `C:\Program Files (x86)\SysAidServer\logs\`
   - Look for database connection errors or missing table errors

---

### Alternative: Restore Specific Tables Only

If you only need to recover specific data (not a full restore):

```powershell
# Extract a single table from the backup
$backupFile = "C:\MySQLBackups\SYSAID_20250103_020000.sql"
$mysqlPath = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe"
$configFile = "C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf"

# Create temporary database
& $mysqlPath --defaults-extra-file=$configFile -e "CREATE DATABASE SYSAID_TEMP;"

# Restore backup to temporary database
& $mysqlPath --defaults-extra-file=$configFile SYSAID_TEMP < $backupFile

# Export specific table
& $mysqlPath --defaults-extra-file=$configFile -e "USE SYSAID_TEMP; SELECT * FROM specific_table;" > "C:\Temp\recovered_data.csv"

# Drop temporary database
& $mysqlPath --defaults-extra-file=$configFile -e "DROP DATABASE SYSAID_TEMP;"
```

---

### Migration to New Server

To move SysAid to a new server using the backup:

#### On the New Server:

1. **Install MySQL Server 5.7** (same version as source)
2. **Create SYSAID database**:
   ```powershell
   mysql -u root -p -e "CREATE DATABASE SYSAID CHARACTER SET utf8 COLLATE utf8_general_ci;"
   ```
3. **Copy backup file** from old server to new server
4. **Restore database** using Step 6 above
5. **Install SysAid Server** (same version as source)
6. **Configure SysAid** to connect to the restored database
7. **Test functionality** using Step 9 above

---

### Troubleshooting Restore Issues

**Issue: "ERROR 1045 (28000): Access denied"**
- **Cause**: Incorrect MySQL credentials
- **Solution**: Verify `backup_credentials.cnf` has correct password
- **Test**: Run `mysql -u root -p` and manually enter password

**Issue: "ERROR 1007 (HY000): Can't create database 'SYSAID'; database exists"**
- **Cause**: Database wasn't dropped before restore
- **Solution**: Run `DROP DATABASE SYSAID;` before restoring

**Issue: Restore completes but SysAid won't start**
- **Cause**: Database version mismatch or corrupted backup
- **Solution**:
  1. Check MySQL error log: `C:\ProgramData\MySQL\MySQL Server 5.7\Data\*.err`
  2. Verify MySQL and SysAid versions are compatible
  3. Try an older backup file

**Issue: Restore is taking too long (>30 minutes)**
- **Cause**: Large database or slow disk I/O
- **Solution**: This is normal for large databases (>5GB). Monitor progress:
  ```powershell
  # Check if mysql.exe process is active
  Get-Process mysql -ErrorAction SilentlyContinue

  # Monitor database file size growth
  Get-Item "C:\ProgramData\MySQL\MySQL Server 5.7\Data\sysaid\*.ibd" | Select-Object Name, Length
  ```

**Issue: "ERROR 2006 (HY000): MySQL server has gone away"**
- **Cause**: Backup file too large for default MySQL settings
- **Solution**: Increase `max_allowed_packet` in MySQL configuration:
  1. Edit `my.ini`: `C:\ProgramData\MySQL\MySQL Server 5.7\my.ini`
  2. Add under `[mysqld]`:
     ```ini
     max_allowed_packet=512M
     ```
  3. Restart MySQL service
  4. Retry restore

**Issue: Data is missing after restore**
- **Cause**: Wrong backup file selected or backup was incomplete
- **Solution**:
  1. Verify backup file timestamp matches expected date
  2. Check backup file size against other backups
  3. Try next most recent backup

---

### Rollback Plan

If the restore fails or causes issues:

1. **Stop SysAid services**:
   ```powershell
   Stop-Service -Name "SysAidServer" -Force
   ```

2. **Restore the emergency backup** (if created in Step 4):
   ```powershell
   $mysqlPath = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe"
   $configFile = "C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf"

   & $mysqlPath --defaults-extra-file=$configFile -e "DROP DATABASE IF EXISTS SYSAID;"
   & $mysqlPath --defaults-extra-file=$configFile < "C:\MySQLBackups\SYSAID_EMERGENCY_*.sql"
   ```

3. **Restart SysAid services**:
   ```powershell
   Start-Service -Name "SysAidServer"
   ```

---

### Post-Restore Documentation

After completing a restore, document the following:

- **Date and time of restoration**: _______________
- **Backup file used**: _______________
- **Reason for restore**: _______________
- **Data loss window**: From _______________ to _______________
- **Performed by**: _______________
- **Verification results**: Pass / Fail
- **Issues encountered**: _______________
- **Users notified**: Yes / No

---

### Point-in-Time Recovery Limitations

Since backups are only retained for 3 days:
- **Recovery Window**: Limited to last 3 days of backups
- **Data Loss**: Any changes after backup timestamp will be lost
- **Granularity**: Daily backups only (no hourly recovery)

**Recommendations for Better Recovery Options**:
- Archive older backups to network storage or cloud for longer retention
- Implement transaction log backups for point-in-time recovery
- Consider MySQL replication for high availability
- Increase backup frequency for critical periods (hourly during business hours)

---

## Security Considerations

### Access Control
- Credentials file is restricted to SYSTEM and Administrator accounts
- Backup files contain sensitive data - ensure `C:\MySQLBackups` has appropriate permissions
- Consider encrypting backup files for long-term storage

### Password Rotation
If MySQL root password changes:
1. Update `C:\Users\cmcleod1.admin\Documents\backup_credentials.cnf`
2. Test backup manually: `.\MYSQLBackup.ps1`
3. No changes needed to scheduled task

---

## Contact Information

**Current Administrator**: cmcleod1.admin
**Implementation Date**: 2025
**Last Updated**: 2025-01-01

For questions or issues, refer to MySQL documentation or contact IT support.

---

## Additional Resources

- [MySQL mysqldump Documentation](https://dev.mysql.com/doc/refman/5.7/en/mysqldump.html)
- [Windows Task Scheduler Documentation](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
- MySQL Server 5.7 Documentation
