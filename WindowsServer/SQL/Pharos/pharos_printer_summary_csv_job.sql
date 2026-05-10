USE [pharos];
GO

/*
Purpose:
- Creates a table to store one saved result set per report_date.
- Creates a SQL Server Agent job that:
  1. Saves the current day's report output to dbo.printer_summary_rollup_history
  2. Exports that day's saved output to a CSV by using sqlcmd

Before running:
- Confirm D:\Reports\Pharos exists on the SQL Server.
- Confirm the SQL Server Agent service account can write to that folder.
- Confirm sqlcmd is installed on the SQL Server.
- Confirm the job step database context is pharos.
*/

IF OBJECT_ID('dbo.printer_summary_rollup_history', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.printer_summary_rollup_history (
        history_id int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        run_time datetime2 NOT NULL CONSTRAINT DF_printer_summary_rollup_history_run_time DEFAULT SYSDATETIME(),
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

USE [msdb];
GO

IF EXISTS (
    SELECT 1
    FROM dbo.sysjobs
    WHERE name = N'Pharos Printer Summary Daily CSV Export'
)
BEGIN
    EXEC dbo.sp_delete_job
        @job_name = N'Pharos Printer Summary Daily CSV Export';
END;
GO

EXEC dbo.sp_add_job
    @job_name = N'Pharos Printer Summary Daily CSV Export',
    @enabled = 1,
    @description = N'Saves pharos printer summary output and exports one CSV per daily run.';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Pharos Printer Summary Daily CSV Export',
    @step_name = N'Save daily rollup to history',
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
    @job_name = N'Pharos Printer Summary Daily CSV Export',
    @step_name = N'Export daily rollup to CSV',
    @subsystem = N'CmdExec',
    @command = N'sqlcmd -E -S $(ESCAPE_NONE(SRVR)) -d pharos -W -s "," -Q "SET NOCOUNT ON; SELECT report_date, summary_group, detail_group, jobs, copies, color_pages, total_pages, total_charged FROM dbo.printer_summary_rollup_history WHERE report_date = CAST(GETDATE() AS date) ORDER BY history_id;" -o "D:\Reports\Pharos\PharosPrinterSummary_$(ESCAPE_NONE(STRTDT))_$(ESCAPE_NONE(STRTTM)).csv"',
    @on_success_action = 1,
    @on_fail_action = 2;
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'Pharos Daily 11_59PM',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 235900;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'Pharos Printer Summary Daily CSV Export',
    @schedule_name = N'Pharos Daily 11_59PM';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'Pharos Printer Summary Daily CSV Export';
GO

/*
Manual verification query:
SELECT *
FROM [pharos].dbo.printer_summary_rollup_history
ORDER BY report_date DESC, history_id DESC;
*/
