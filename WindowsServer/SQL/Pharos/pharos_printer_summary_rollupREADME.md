# Pharos Printer Summary Rollup

This folder contains a SQL Server report script for the `pharos` database.

## File

- `pharos_printer_summary_rollup.sql`
  - Creates/updates `dbo.usp_rpt_printer_summary_rollup`
  - Summarizes print activity by:
    - `summary_group` (combined library group such as `LIB-Mckeldin`)
    - `detail_group` (actual `print_group`)
  - Includes `SUBTOTAL` rows and one `GRAND TOTAL` row
  - Outputs:
    - `jobs`
    - `copies`
    - `color_pages`
    - `total_pages`
    - `total_charged` (positive dollars from negative transaction amounts)

## How the query works

1. Pre-aggregates `transaction_print_attributes` so each transaction has one `total_pages` value.
2. Joins:
   - `transactions`
   - `print_transactions`
   - aggregated `transaction_print_attributes`
3. Maps raw `print_group` names into combined groups (`LIB-Mckeldin`, `LIB-EPSL`, etc.).
4. Uses `ROLLUP` to produce detail + subtotal + grand total rows.

## Run manually

1. Open SQL Server Management Studio (SSMS).
2. Connect to your SQL Server instance.
3. Open `pharos_printer_summary_rollup.sql` and execute it once to create/update the procedure.
4. Run:

```sql
USE [pharos];
GO
EXEC dbo.usp_rpt_printer_summary_rollup
    @start_time = '2025-08-25T00:00:00',
    @end_time   = '2025-12-20T23:59:59';
GO
```

## Schedule with SQL Server Agent

### Create a job (example: weekly Monday 6:00 AM)

Run in SSMS:

```sql
USE [msdb];
GO

EXEC sp_add_job
    @job_name = N'Pharos Printer Summary Rollup',
    @enabled = 1,
    @description = N'Runs dbo.usp_rpt_printer_summary_rollup on schedule';
GO

EXEC sp_add_jobstep
    @job_name = N'Pharos Printer Summary Rollup',
    @step_name = N'Run stored procedure',
    @subsystem = N'TSQL',
    @database_name = N'pharos',
    @command = N'
DECLARE @start_time datetime = DATEADD(day, -7, GETDATE());
DECLARE @end_time   datetime = GETDATE();

EXEC dbo.usp_rpt_printer_summary_rollup
    @start_time = @start_time,
    @end_time   = @end_time;
';
GO

EXEC sp_add_schedule
    @schedule_name = N'Weekly Monday 6AM',
    @freq_type = 8,              -- weekly
    @freq_interval = 2,          -- Monday
    @freq_recurrence_factor = 1, -- every week
    @active_start_time = 060000; -- 06:00:00
GO

EXEC sp_attach_schedule
    @job_name = N'Pharos Printer Summary Rollup',
    @schedule_name = N'Weekly Monday 6AM';
GO

EXEC sp_add_jobserver
    @job_name = N'Pharos Printer Summary Rollup';
GO
```

### Adjust the schedule window

- Last 1 day:
  - `@start_time = DATEADD(day, -1, GETDATE())`
- Last 7 days:
  - `@start_time = DATEADD(day, -7, GETDATE())`
- Semester/custom:
  - Replace both variables with fixed date/time literals.

## Notes

- SQL Server Agent service must be running.
- The SQL login/credential used by the job needs permission to execute the procedure and read source tables.
