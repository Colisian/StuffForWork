USE [pharos];
GO

/*
Purpose:
- Creates a SQL Server Agent job that:
  1. Saves the current day's print-group report output to dbo.printer_summary_rollup_history
  2. Saves the current day's device report output to dbo.printer_device_summary_history
  3. Exports both saved outputs to CSV
  4. Emails both CSV attachments with Database Mail

Before running:
- Confirm dbo.usp_rpt_printer_summary_rollup already exists in pharos.
- Confirm dbo.usp_rpt_printer_device_summary already exists in pharos.
- Confirm D:\Reports\Pharos exists on the SQL Server.
- Confirm the SQL Server Agent service account can write to that folder.
- Confirm sqlcmd is installed on the SQL Server.
- Confirm Database Mail is enabled and working on the SQL Server instance.
*/

IF OBJECT_ID('dbo.printer_summary_rollup_history', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.printer_summary_rollup_history (
        history_id int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        run_time datetime2 NOT NULL
            CONSTRAINT DF_printer_summary_rollup_history_run_time DEFAULT SYSDATETIME(),
        report_date date NOT NULL,
        summary_group nvarchar(255) NOT NULL,
        detail_group nvarchar(255) NOT NULL,
        jobs int NOT NULL,
        copies int NOT NULL,
        color_pages int NOT NULL,
        total_pages int NOT NULL,
        total_charged decimal(12,2) NOT NULL
    );
END;
GO

IF OBJECT_ID('dbo.printer_device_summary_history', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.printer_device_summary_history (
        history_id int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        run_time datetime2 NOT NULL
            CONSTRAINT DF_printer_device_summary_history_run_time DEFAULT SYSDATETIME(),
        report_date date NOT NULL,
        printer_id nvarchar(50) NULL,
        print_device nvarchar(255) NOT NULL,
        printer_type nvarchar(255) NULL,
        device_type nvarchar(255) NULL,
        jobs int NOT NULL,
        copies int NOT NULL,
        pages int NOT NULL,
        color_pages int NOT NULL,
        total_charged decimal(12,2) NOT NULL
    );
END;
GO

USE [msdb];
GO

IF EXISTS (
    SELECT 1
    FROM dbo.sysjobs
    WHERE name = N'Pharos Printer Summary Daily CSV Export and Email'
)
BEGIN
    EXEC dbo.sp_delete_job
        @job_name = N'Pharos Printer Summary Daily CSV Export and Email';
END;
GO

EXEC dbo.sp_add_job
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email',
    @enabled = 1,
    @description = N'Saves pharos printer summaries, exports CSV files, and emails the daily results.';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email',
    @step_name = N'Save daily print-group summary to history',
    @subsystem = N'TSQL',
    @database_name = N'pharos',
    @on_success_action = 3,
    @on_fail_action = 2,
    @command = N'
DECLARE @report_date date = CAST(GETDATE() AS date);
DECLARE @start_time datetime = CAST(@report_date AS datetime);
DECLARE @end_time datetime = DATEADD(second, -1, DATEADD(day, 1, @start_time));

DELETE FROM dbo.printer_summary_rollup_history
WHERE report_date = @report_date;

CREATE TABLE #rollup (
    summary_group nvarchar(255),
    detail_group nvarchar(255),
    jobs int,
    copies int,
    color_pages int,
    total_pages int,
    total_charged decimal(12,2)
);

INSERT INTO #rollup
EXEC [pharos].dbo.usp_rpt_printer_summary_rollup
    @start_time = @start_time,
    @end_time = @end_time;

INSERT INTO dbo.printer_summary_rollup_history (
    report_date,
    summary_group,
    detail_group,
    jobs,
    copies,
    color_pages,
    total_pages,
    total_charged
)
SELECT
    @report_date,
    summary_group,
    detail_group,
    jobs,
    copies,
    color_pages,
    total_pages,
    total_charged
FROM #rollup;
';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email',
    @step_name = N'Save daily device summary to history',
    @subsystem = N'TSQL',
    @database_name = N'pharos',
    @on_success_action = 3,
    @on_fail_action = 2,
    @command = N'
DECLARE @report_date date = CAST(GETDATE() AS date);
DECLARE @start_time datetime = CAST(@report_date AS datetime);
DECLARE @end_time datetime = DATEADD(second, -1, DATEADD(day, 1, @start_time));

DELETE FROM dbo.printer_device_summary_history
WHERE report_date = @report_date;

CREATE TABLE #device_summary (
    printer_id nvarchar(50),
    print_device nvarchar(255),
    printer_type nvarchar(255),
    device_type nvarchar(255),
    jobs int,
    copies int,
    pages int,
    color_pages int,
    total_charged decimal(12,2)
);

INSERT INTO #device_summary
EXEC [pharos].dbo.usp_rpt_printer_device_summary
    @start_time = @start_time,
    @end_time = @end_time;

INSERT INTO dbo.printer_device_summary_history (
    report_date,
    printer_id,
    print_device,
    printer_type,
    device_type,
    jobs,
    copies,
    pages,
    color_pages,
    total_charged
)
SELECT
    @report_date,
    printer_id,
    print_device,
    printer_type,
    device_type,
    jobs,
    copies,
    pages,
    color_pages,
    total_charged
FROM #device_summary;
';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email',
    @step_name = N'Export print-group summary to CSV',
    @subsystem = N'CmdExec',
    @on_success_action = 3,
    @on_fail_action = 2,
    @command = N'sqlcmd -E -S $(ESCAPE_NONE(SRVR)) -d pharos -W -s "," -Q "SET NOCOUNT ON; SELECT DISTINCT report_date, summary_group, detail_group, jobs, copies, color_pages, total_pages, total_charged FROM dbo.printer_summary_rollup_history WHERE report_date = (SELECT MAX(report_date) FROM dbo.printer_summary_rollup_history) ORDER BY report_date, summary_group, detail_group;" -o "D:\Reports\Pharos\PharosPrinterSummary.csv"';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email',
    @step_name = N'Export device summary to CSV',
    @subsystem = N'CmdExec',
    @on_success_action = 3,
    @on_fail_action = 2,
    @command = N'sqlcmd -E -S $(ESCAPE_NONE(SRVR)) -d pharos -W -s "," -Q "SET NOCOUNT ON; SELECT DISTINCT report_date, printer_id, print_device, printer_type, device_type, jobs, copies, pages, color_pages, total_charged FROM dbo.printer_device_summary_history WHERE report_date = (SELECT MAX(report_date) FROM dbo.printer_device_summary_history) ORDER BY report_date, print_device;" -o "D:\Reports\Pharos\PharosPrinterDeviceSummary.csv"';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email',
    @step_name = N'Email daily summaries',
    @subsystem = N'TSQL',
    @database_name = N'msdb',
    @on_success_action = 1,
    @on_fail_action = 2,
    @command = N'
DECLARE @report_date date = (
    SELECT MAX(report_date)
    FROM pharos.dbo.printer_summary_rollup_history
);
DECLARE @subject nvarchar(255) = N''Pharos Daily Printer Summary - '' + CONVERT(nvarchar(10), @report_date, 120);
DECLARE @body nvarchar(max) = N''Attached are the Pharos daily print-group and device summaries for '' + CONVERT(nvarchar(10), @report_date, 120) + N''.'';

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N''Pharos_Reports'',
    @recipients = N''cmcleod1@umd.edu'',
    @subject = @subject,
    @body = @body,
    @file_attachments = N''D:\Reports\Pharos\PharosPrinterSummary.csv;D:\Reports\Pharos\PharosPrinterDeviceSummary.csv'';
';
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'Pharos Daily 11_59PM Email',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 235900;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email',
    @schedule_name = N'Pharos Daily 11_59PM Email';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'Pharos Printer Summary Daily CSV Export and Email';
GO
