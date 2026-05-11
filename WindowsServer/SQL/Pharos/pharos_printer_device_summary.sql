USE [pharos];
GO

/*
Purpose:
- Creates a stored procedure that summarizes Pharos print activity by
  individual print device.
- Includes zero-usage printers except for an explicit exclusion list.
- Includes a grand total row.
*/

CREATE OR ALTER PROCEDURE dbo.usp_rpt_printer_device_summary
    @start_time datetime,
    @end_time   datetime
AS
BEGIN
    SET NOCOUNT ON;

    WITH printer_list AS (
        SELECT
            [Printer ID] AS printer_id,
            [Printer] AS print_device,
            [Printer Type] AS printer_type,
            [Device Type] AS device_type
        FROM dbo.rpt_printers
    ),
    device_activity AS (
        SELECT
            [Printer] AS print_device,
            COUNT(*) AS jobs,
            SUM(ISNULL([Copies], 0)) AS copies,
            SUM(ISNULL([Pages], 0)) AS pages,
            SUM(ISNULL([Color Pages], 0)) AS color_pages,
            SUM(ISNULL([Sheets], 0)) AS sheets,
            CAST(SUM(ISNULL(-1.0 * [Amount Charged], 0)) AS decimal(12, 2)) AS total_charged
        FROM dbo.rpt_print_transactions
        WHERE [Date/Time] >= @start_time
          AND [Date/Time] <= @end_time
        GROUP BY [Printer]
    ),
    detail_rows AS (
        SELECT
            p.printer_id,
            p.print_device,
            p.printer_type,
            p.device_type,
            COALESCE(a.jobs, 0) AS jobs,
            COALESCE(a.copies, 0) AS copies,
            COALESCE(a.pages, 0) AS pages,
            COALESCE(a.color_pages, 0) AS color_pages,
            COALESCE(a.sheets, 0) AS sheets,
            COALESCE(a.total_charged, 0.00) AS total_charged
        FROM printer_list p
        LEFT JOIN device_activity a
            ON a.print_device = p.print_device
        WHERE p.print_device NOT IN (
            'iSchool-CanonMFP1',
            'LIB-ATLABCanonMFP1',
            'LIB-ChemCanonMFP2',
            'LIB-LMSHPPrinterBW2',
            'LIB-Mck2FloorWideFormatPrinter1',
            'LIB-Mck2FloorWideFormatPrinter2',
            'LIB-Mck2FloorWideFormatPrinter3',
            'LIB-Mck6FCanonMFP1',
            'LIB-EPSLHPPrinterBW1',
            'LIB-EPSLHPPrinterBW2',
            'LIB-EPSLHPPrinterBW3'
        )
    ),
    final_rows AS (
        SELECT
            CAST(printer_id AS nvarchar(50)) AS printer_id,
            print_device,
            printer_type,
            device_type,
            jobs,
            copies,
            pages,
            color_pages,
            sheets,
            total_charged,
            0 AS sort_order
        FROM detail_rows

        UNION ALL

        SELECT
            NULL,
            'GRAND TOTAL',
            NULL,
            NULL,
            SUM(jobs),
            SUM(copies),
            SUM(pages),
            SUM(color_pages),
            SUM(sheets),
            CAST(SUM(total_charged) AS decimal(12, 2)),
            1 AS sort_order
        FROM detail_rows
    )
    SELECT
        printer_id,
        print_device,
        printer_type,
        device_type,
        jobs,
        copies,
        pages,
        color_pages,
        sheets,
        total_charged
    FROM final_rows
    ORDER BY
        sort_order,
        print_device;
END;
GO

/*
Example execution:
EXEC dbo.usp_rpt_printer_device_summary
    @start_time = '2026-05-10T00:00:00',
    @end_time   = '2026-05-10T23:59:59';
*/
