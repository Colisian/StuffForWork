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
