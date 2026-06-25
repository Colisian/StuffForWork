USE [msdb];
GO

/*
Purpose:
- Creates a SQL Server Agent job that deletes old CSV summary files from:
  D:\Reports\Pharos

Retention rule:
- Keep files from the current month and the immediately previous month.
- Delete CSV files older than the first day of the previous month.

Example:
- On July 1, delete files with LastWriteTime earlier than June 1.
- That removes May and older files, while keeping June and July files.

Prerequisites:
- D:\Reports\Pharos must exist on the SQL Server.
- The SQL Server Agent service account must have permission to delete files there.
- PowerShell must be available on the SQL Server.

Schedule assumption:
- Runs on the 1st day of each month at 7:00 AM server local time.
- Adjust the schedule after creation if you want a different monthly day/time.
*/

IF EXISTS (
    SELECT 1
    FROM dbo.sysjobs
    WHERE name = N'Pharos Report Cleanup Monthly'
)
BEGIN
    EXEC dbo.sp_delete_job
        @job_name = N'Pharos Report Cleanup Monthly';
END;
GO

EXEC dbo.sp_add_job
    @job_name = N'Pharos Report Cleanup Monthly',
    @enabled = 1,
    @description = N'Deletes old CSV summary files from D:\Reports\Pharos on a monthly retention schedule.';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Report Cleanup Monthly',
    @step_name = N'Delete old CSV files',
    @subsystem = N'CmdExec',
    @on_success_action = 1,
    @on_fail_action = 2,
    @command = N'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$cutoff = (Get-Date -Day 1).AddMonths(-1); Get-ChildItem ''D:\Reports\Pharos'' -Filter ''*.csv'' | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force"';
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'Pharos Monthly Cleanup 1st Day 7AM',
    @freq_type = 16,
    @freq_interval = 1,
    @freq_recurrence_factor = 1,
    @active_start_time = 070000;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'Pharos Report Cleanup Monthly',
    @schedule_name = N'Pharos Monthly Cleanup 1st Day 7AM';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'Pharos Report Cleanup Monthly';
GO
