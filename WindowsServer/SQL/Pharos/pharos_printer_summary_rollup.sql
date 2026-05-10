USE [pharos];
GO

/*
Purpose:
- Creates a stored procedure that summarizes Pharos print activity by
  library group (Mckeldin, EPSL, PAL, etc.) and print group.
- Includes subtotal rows and a grand total row.
*/

CREATE OR ALTER PROCEDURE dbo.usp_rpt_printer_summary_rollup
    @start_time datetime,
    @end_time   datetime
AS
BEGIN
    SET NOCOUNT ON;

    WITH tpa_agg AS (
        SELECT
            transaction_id,
            SUM(ISNULL(num_pages, 0)) AS total_pages
        FROM dbo.transaction_print_attributes
        GROUP BY transaction_id
    ),
    base AS (
        SELECT
            t.transaction_id,
            t.[time],
            t.amount,
            ISNULL(pt.copies, 1) AS copies,
            ISNULL(pt.num_color_pages, 0) AS color_pages,
            ISNULL(tpa.total_pages, 0) AS total_pages,
            pt.print_group,
            CASE
                WHEN pt.print_group LIKE 'LIB-Mckeldin%' THEN 'LIB-Mckeldin'
                WHEN pt.print_group LIKE 'LIB-EPSL%'     THEN 'LIB-EPSL'
                WHEN pt.print_group LIKE 'LIB-PAL%'      THEN 'LIB-PAL'
                WHEN pt.print_group LIKE 'LIB-Arch%'     THEN 'LIB-Arch'
                WHEN pt.print_group LIKE 'LIB-Art%'      THEN 'LIB-Art'
                WHEN pt.print_group LIKE 'LIB-HBK%'      THEN 'LIB-HBK'
                WHEN pt.print_group LIKE 'LIB-Mdroom%'   THEN 'LIB-Mdroom'
                ELSE pt.print_group
            END AS printgroup_summary
        FROM dbo.transactions t
        JOIN dbo.print_transactions pt
            ON pt.transaction_id = t.transaction_id
        LEFT JOIN tpa_agg tpa
            ON tpa.transaction_id = t.transaction_id
        WHERE t.[time] >= @start_time
          AND t.[time] <= @end_time
    )
    SELECT
        CASE
            WHEN GROUPING(printgroup_summary) = 1 THEN 'GRAND TOTAL'
            ELSE printgroup_summary
        END AS summary_group,
        CASE
            WHEN GROUPING(print_group) = 1 AND GROUPING(printgroup_summary) = 0 THEN 'SUBTOTAL'
            WHEN GROUPING(print_group) = 1 AND GROUPING(printgroup_summary) = 1 THEN 'GRAND TOTAL'
            ELSE print_group
        END AS detail_group,
        COUNT(*) AS jobs,
        SUM(copies) AS copies,
        SUM(color_pages) AS color_pages,
        SUM(total_pages) AS total_pages,
        CAST(SUM(-1.0 * amount) AS decimal(12, 2)) AS total_charged
    FROM base
    GROUP BY ROLLUP (printgroup_summary, print_group)
    ORDER BY
        CASE WHEN GROUPING(printgroup_summary) = 1 THEN 1 ELSE 0 END,
        printgroup_summary,
        CASE WHEN GROUPING(print_group) = 1 THEN 1 ELSE 0 END,
        print_group;
END;
GO

/*
Example execution:
EXEC dbo.usp_rpt_printer_summary_rollup
    @start_time = '2025-08-25T00:00:00',
    @end_time   = '2025-12-20T23:59:59';
*/
