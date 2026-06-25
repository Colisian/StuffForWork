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
- `pharos_printer_summary_csv_job.sql`
  - Creates `dbo.printer_summary_rollup_history` if needed
  - Creates a SQL Server Agent job that saves the current day's report output
  - Exports that saved output to a CSV with `sqlcmd`
- `pharos_printer_summary_email_job.sql`
  - Creates `dbo.printer_summary_rollup_history` if needed
  - Creates `dbo.printer_device_summary_history` if needed
  - Creates a SQL Server Agent job that saves the current day's report output
  - Exports both the print-group report and the device report to CSV with `sqlcmd`
  - Emails both CSV files as Database Mail attachments
- `pharos_printer_device_summary.sql`
  - Creates/updates `dbo.usp_rpt_printer_device_summary`
  - Summarizes print activity by individual print device
  - Includes a grand total row
  - Excludes a fixed list of devices you chose not to report on
- `pharos_finals_2025_daily_print_groups.sql`
  - Returns a day-by-day print-group view for:
    - Spring 2025 finals: May 15, 2025 through May 21, 2025
    - Fall 2025 finals: December 15, 2025 through December 20, 2025
- `pharos_finals_2025_daily_devices.sql`
  - Returns a day-by-day device view for the same two finals periods
  - Uses the current excluded-device list from the device summary report
- `pharos_finals_2024_daily_print_groups.sql`
  - Returns a day-by-day print-group view for:
    - Spring 2024 finals: May 11, 2024 through May 17, 2024
    - Fall 2024 finals: December 11, 2024 through December 17, 2024
  - Includes a grand total row at the end of each day
- `pharos_finals_2024_daily_devices.sql`
  - Returns a day-by-day device view for the same two 2024 finals periods
  - Uses the current excluded-device list from the device summary report
  - Includes a grand total row at the end of each day
- `pharos_printer_summary_monthly_email_job.sql`
  - Creates a SQL Server Agent job that emails the previous calendar month's print-group rollup once per month
  - Uses `dbo.usp_rpt_printer_summary_rollup`
  - Uses Database Mail profile `Pharos_Reports`
  - Sends to `cmcleod1@umd.edu`
  - Defaults to running on the 1st day of each month at 8:00 AM
- `pharos_report_cleanup_monthly_job.sql`
  - Creates a SQL Server Agent job that deletes old CSV files from `D:\Reports\Pharos`
  - Keeps the current month and the immediately previous month
  - Deletes files older than the first day of the previous month
  - Defaults to running on the 1st day of each month at 7:00 AM

## How the query works

1. Pre-aggregates `transaction_print_attributes` so each transaction has one `total_pages` value.
2. Joins:
   - `transactions`
   - `print_transactions`
   - aggregated `transaction_print_attributes`
3. Maps raw `print_group` names into combined groups (`LIB-Mckeldin`, `LIB-EPSL`, etc.).
4. Left joins actual activity to a fixed list of expected print groups so zero-usage groups still appear.
5. Maps `LIB-HBK...` print groups into `LIB-HBK`.
6. Produces detail + subtotal + grand total rows.

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

## Notes

- SQL Server Agent service must be running.
- The SQL login/credential used by the job needs permission to execute the procedure and read source tables.

## Export to CSV

Use [pharos_printer_summary_csv_job.sql](/Users/cmcleod1/Library/CloudStorage/OneDrive-UniversityofMaryland/Documents/Work/StuffForWork/WindowsServer/SQL/Pharos/pharos_printer_summary_csv_job.sql) when you want each daily run saved and exported to disk.

What it does:

1. Saves one result set per day into `dbo.printer_summary_rollup_history`.
2. Exports the saved rows for the latest saved `report_date` to a CSV file.
3. Names the file with SQL Server Agent start-date and start-time tokens.

Important prerequisites:

- Confirm this export path exists on the SQL Server:
  - `D:\Reports\Pharos\`
- Confirm the SQL Server Agent service account can write to that folder.
- Confirm `sqlcmd` is installed on the SQL Server.
- If you already created the earlier report job, delete or disable it before enabling the CSV export job to avoid duplicate runs.

CSV behavior:

- The T-SQL step stores the current calendar day's report.
- The `CmdExec` step then exports the latest saved `report_date` from `dbo.printer_summary_rollup_history`.
- The export query uses `DISTINCT` so duplicate saved rows do not repeat in the CSV.
- The CSV file includes the grand total row, subtotal rows, and detail rows exactly as the stored procedure returns them.
- Step 1 must be configured to `Go to the next step` on success so the CSV export step actually runs.

## Email the report

Use [pharos_printer_summary_email_job.sql](/Users/cmcleod1/Library/CloudStorage/OneDrive-UniversityofMaryland/Documents/Work/StuffForWork/WindowsServer/SQL/Pharos/pharos_printer_summary_email_job.sql) when you want the daily run exported to CSV and emailed.

What it does:

1. Saves the daily print-group report rows into `dbo.printer_summary_rollup_history`.
2. Saves the daily device report rows into `dbo.printer_device_summary_history`.
3. Exports both reports to `D:\Reports\Pharos`.
4. Sends one email through Database Mail with both CSV files attached.

Important prerequisites:

- Database Mail must already be configured on the SQL Server instance.
- The current script is configured to use Database Mail profile `Pharos_Reports`.
- The current script sends to `cmcleod1@umd.edu`.
- `dbo.usp_rpt_printer_summary_rollup` and `dbo.usp_rpt_printer_device_summary` must both exist before you run the mail job script.
- If you already have the CSV-only job enabled, disable or delete it before enabling the mail-enabled job so you do not run both every night.

Recommended test order:

1. Send a plain Database Mail test message first.
2. Run the mail-enabled job manually once.
3. Verify:
   - rows were inserted into both history tables
   - both CSV files were written to `D:\Reports\Pharos`
   - the email was delivered with both attached reports

Email job behavior:

- Step 1 saves the current calendar day's print-group report rows.
- Step 2 saves the current calendar day's device report rows.
- Step 3 exports the latest saved print-group `report_date` to `D:\Reports\Pharos\PharosPrinterSummary.csv`.
- Step 4 exports the latest saved device `report_date` to `D:\Reports\Pharos\PharosPrinterDeviceSummary.csv`.
- Step 5 emails both CSV files as attachments.
- The export queries de-duplicate identical saved rows before sending output.
- Using the latest saved `report_date` in the export steps avoids midnight crossover issues where a job starts before midnight and finishes after midnight.

## Monthly Summary Email

Use [pharos_printer_summary_monthly_email_job.sql](/Users/cmcleod1/Library/CloudStorage/OneDrive-UniversityofMaryland/Documents/Work/StuffForWork/WindowsServer/SQL/Pharos/pharos_printer_summary_monthly_email_job.sql) when you want a separate monthly email for the print-group rollup using the previous calendar month as the reporting window.

Behavior:

- Sends one email with the procedure output attached as `PharosPrinterSummary_YYYY-MM.csv`
- Uses Database Mail profile `Pharos_Reports`
- Sends to `cmcleod1@umd.edu`
- Defaults to the 1st day of each month at `8:00 AM` server local time
- Reports on the previous calendar month each time it runs

Notes:

- The script recreates the job if it already exists.
- If you want a different monthly day or time, change the SQL Server Agent schedule after creating the job.

## Monthly Report Cleanup

Use [pharos_report_cleanup_monthly_job.sql](/Users/cmcleod1/Library/CloudStorage/OneDrive-UniversityofMaryland/Documents/Work/StuffForWork/WindowsServer/SQL/Pharos/pharos_report_cleanup_monthly_job.sql) when you want SQL Server Agent to remove older CSV files from `D:\Reports\Pharos`.

Behavior:

- Deletes `*.csv` files whose `LastWriteTime` is older than the first day of the previous month
- Keeps files from the current month and the immediately previous month
- Defaults to running on the 1st day of each month at `7:00 AM` server local time

Example:

- On `July 1`, files from `May` and earlier are deleted
- Files from `June` and `July` are kept

Notes:

- This job is intentionally separate from the monthly email job.
- The SQL Server Agent service account must have delete permission on `D:\Reports\Pharos`.

## Finals Queries

Use these scripts when you need historical day-by-day finals-period reporting rather than the scheduled daily summaries.

Print groups:

- [pharos_finals_2025_daily_print_groups.sql](/Users/cmcleod1/Library/CloudStorage/OneDrive-UniversityofMaryland/Documents/Work/StuffForWork/WindowsServer/SQL/Pharos/pharos_finals_2025_daily_print_groups.sql)
- Output columns:
  - `finals_period`
  - `report_date`
  - `summary_group`
  - `detail_group`
  - `jobs`
  - `copies`
  - `color_pages`
  - `total_pages`
  - `total_charged`

Devices:

- [pharos_finals_2025_daily_devices.sql](/Users/cmcleod1/Library/CloudStorage/OneDrive-UniversityofMaryland/Documents/Work/StuffForWork/WindowsServer/SQL/Pharos/pharos_finals_2025_daily_devices.sql)
- Output columns:
  - `finals_period`
  - `report_date`
  - `printer_id`
  - `print_device`
  - `printer_type`
  - `device_type`
  - `jobs`
  - `copies`
  - `total_pages`
  - `color_pages`
  - `total_charged`

Notes:

- The print-group finals query only returns rows where activity exists for that day/group.
- The device finals query cross joins the finals dates to the printer list, so it can show zero-usage devices for a given day.
- The device finals query uses the same exclusion list as `dbo.usp_rpt_printer_device_summary`.
- The 2024 finals scripts follow the same pattern as the 2025 finals scripts and include daily grand total rows.
