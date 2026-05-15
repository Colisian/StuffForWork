USE [pharos];
GO

/*
Purpose:
- Returns a day-by-day view of individual printer/device activity for the two finals periods:
  - Spring 2025: May 15, 2025 through May 21, 2025
  - Fall 2025: December 15, 2025 through December 20, 2025
- Uses the existing device exclusion list.
*/

WITH report_dates AS (
    SELECT CAST('2025-05-15' AS date) AS report_date, 'Spring 2025 Finals' AS finals_period
    UNION ALL SELECT '2025-05-16', 'Spring 2025 Finals'
    UNION ALL SELECT '2025-05-17', 'Spring 2025 Finals'
    UNION ALL SELECT '2025-05-18', 'Spring 2025 Finals'
    UNION ALL SELECT '2025-05-19', 'Spring 2025 Finals'
    UNION ALL SELECT '2025-05-20', 'Spring 2025 Finals'
    UNION ALL SELECT '2025-05-21', 'Spring 2025 Finals'
    UNION ALL SELECT '2025-12-15', 'Fall 2025 Finals'
    UNION ALL SELECT '2025-12-16', 'Fall 2025 Finals'
    UNION ALL SELECT '2025-12-17', 'Fall 2025 Finals'
    UNION ALL SELECT '2025-12-18', 'Fall 2025 Finals'
    UNION ALL SELECT '2025-12-19', 'Fall 2025 Finals'
    UNION ALL SELECT '2025-12-20', 'Fall 2025 Finals'
),
printer_list AS (
    SELECT
        [Printer ID] AS printer_id,
        [Printer] AS print_device,
        [Printer Type] AS printer_type,
        [Device Type] AS device_type
    FROM dbo.rpt_printers
    WHERE [Printer] NOT IN (
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
device_activity AS (
    SELECT
        CAST([Date/Time] AS date) AS report_date,
        [Printer] AS print_device,
        COUNT(*) AS jobs,
        SUM(ISNULL([Copies], 0)) AS copies,
        SUM(ISNULL([Pages], 0)) AS pages,
        SUM(ISNULL([Color Pages], 0)) AS color_pages,
        CAST(SUM(ISNULL(-1.0 * [Amount Charged], 0)) AS decimal(12,2)) AS total_charged
    FROM dbo.rpt_print_transactions
    WHERE CAST([Date/Time] AS date) IN (
        '2025-05-15','2025-05-16','2025-05-17','2025-05-18','2025-05-19','2025-05-20','2025-05-21',
        '2025-12-15','2025-12-16','2025-12-17','2025-12-18','2025-12-19','2025-12-20'
    )
    GROUP BY
        CAST([Date/Time] AS date),
        [Printer]
)
SELECT
    rd.finals_period,
    rd.report_date,
    p.printer_id,
    p.print_device,
    p.printer_type,
    p.device_type,
    COALESCE(a.jobs, 0) AS jobs,
    COALESCE(a.copies, 0) AS copies,
    COALESCE(a.pages, 0) AS total_pages,
    COALESCE(a.color_pages, 0) AS color_pages,
    COALESCE(a.total_charged, 0.00) AS total_charged
FROM report_dates rd
CROSS JOIN printer_list p
LEFT JOIN device_activity a
    ON a.report_date = rd.report_date
   AND a.print_device = p.print_device
ORDER BY
    rd.report_date,
    p.print_device;
GO
