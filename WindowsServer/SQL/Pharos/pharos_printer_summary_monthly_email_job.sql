USE [msdb];
GO

/*
Purpose:
- Creates a SQL Server Agent job that emails dbo.usp_rpt_printer_summary_rollup once per month.
- Each run reports on the previous calendar month.

Examples:
- If the job runs on July 1, it emails June 1 through June 30.
- If the job runs on January 1, it emails December 1 through December 31.

Current mail settings:
- Database Mail profile: Pharos_Reports
- Recipient: cmcleod1@umd.edu

Schedule assumption:
- Runs on the 1st day of each month at 8:00 AM server local time.
- Adjust the schedule after creation if you want a different monthly day/time.

Prerequisites:
- dbo.usp_rpt_printer_summary_rollup must already exist in the pharos database.
- Database Mail must already be configured and working.
*/

IF EXISTS (
    SELECT 1
    FROM dbo.sysjobs
    WHERE name = N'Pharos Printer Summary Monthly Email'
)
BEGIN
    EXEC dbo.sp_delete_job
        @job_name = N'Pharos Printer Summary Monthly Email';
END;
GO

EXEC dbo.sp_add_job
    @job_name = N'Pharos Printer Summary Monthly Email',
    @enabled = 1,
    @description = N'Emails the previous calendar month print-group rollup once per month.';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Printer Summary Monthly Email',
    @step_name = N'Email previous month rollup',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @on_success_action = 1,
    @on_fail_action = 2,
    @command = N'
DECLARE @report_start date = DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 1, 0);
DECLARE @report_end date = DATEADD(day, -1, DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0));
DECLARE @start_time datetime = CAST(@report_start AS datetime);
DECLARE @end_time datetime = DATEADD(second, -1, DATEADD(day, 1, CAST(@report_end AS datetime)));
DECLARE @period_label nvarchar(32) = DATENAME(month, @report_start) + N'' '' + CONVERT(nvarchar(4), YEAR(@report_start));
DECLARE @subject nvarchar(255) = N''Pharos Printer Summary - '' + @period_label;
DECLARE @body nvarchar(max) = N''Attached is the Pharos print-group rollup for '' + @period_label + N''.'';
DECLARE @query nvarchar(max) =
    N''SET NOCOUNT ON;
EXEC pharos.dbo.usp_rpt_printer_summary_rollup
    @start_time = '''''' + CONVERT(nvarchar(19), @start_time, 126) + N'''''',
    @end_time   = '''''' + CONVERT(nvarchar(19), @end_time, 126) + N'''''';'';
DECLARE @attachment_name nvarchar(255) =
    N''PharosPrinterSummary_'' +
    CONVERT(nvarchar(4), YEAR(@report_start)) + N''-'' +
    RIGHT(N''0'' + CONVERT(nvarchar(2), MONTH(@report_start)), 2) +
    N''.csv'';

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N''Pharos_Reports'',
    @recipients = N''cmcleod1@umd.edu'',
    @subject = @subject,
    @body = @body,
    @query = @query,
    @attach_query_result_as_file = 1,
    @query_attachment_filename = @attachment_name,
    @query_result_separator = N'','',
    @query_result_no_padding = 1,
    @query_result_header = 1;
';
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'Pharos Monthly 1st Day 8AM',
    @freq_type = 16,
    @freq_interval = 1,
    @freq_recurrence_factor = 1,
    @active_start_time = 080000;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'Pharos Printer Summary Monthly Email',
    @schedule_name = N'Pharos Monthly 1st Day 8AM';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'Pharos Printer Summary Monthly Email';
GO
