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
    ),
    expected_groups AS (
        SELECT 'LIB-Arch' AS summary_group, 'LIB-ArchMobileGroup' AS detail_group
        UNION ALL SELECT 'LIB-Art', 'LIB-ArtMobileGroup'
        UNION ALL SELECT 'LIB-Art', 'LIB-ArtPrintGroup'
        UNION ALL SELECT 'LIB-EPSL', 'LIB-EPSLCanonMobileGroup'
        UNION ALL SELECT 'LIB-EPSL', 'LIB-EPSLCanonPrintGroup'
        UNION ALL SELECT 'LIB-HBK', 'LIB-HBKCanonPrintGroup'
        UNION ALL SELECT 'LIB-Mckeldin', 'LIB-MckeldinCanonPrintGroup'
        UNION ALL SELECT 'LIB-Mckeldin', 'LIB-MckeldinMobilePrintGroup'
        UNION ALL SELECT 'LIB-Mdroom', 'LIB-MdroomPrintGroup'
        UNION ALL SELECT 'LIB-PAL', 'LIB-PALCanonMobileGroupBW'
        UNION ALL SELECT 'LIB-PAL', 'LIB-PALCanonMobileGroupColor'
        UNION ALL SELECT 'LIB-PAL', 'LIB-PALCanonPrintGroupBW'
        UNION ALL SELECT 'LIB-PAL', 'LIB-PALCanonPrintGroupColor'
    ),
    detail_rows AS (
        SELECT
            eg.summary_group,
            eg.detail_group,
            COUNT(b.transaction_id) AS jobs,
            COALESCE(SUM(b.copies), 0) AS copies,
            COALESCE(SUM(b.color_pages), 0) AS color_pages,
            COALESCE(SUM(b.total_pages), 0) AS total_pages,
            CAST(COALESCE(SUM(-1.0 * b.amount), 0) AS decimal(12, 2)) AS total_charged
        FROM expected_groups eg
        LEFT JOIN base b
            ON b.printgroup_summary = eg.summary_group
           AND b.print_group = eg.detail_group
        GROUP BY
            eg.summary_group,
            eg.detail_group
    ),
    final_rows AS (
        SELECT
            summary_group,
            detail_group,
            jobs,
            copies,
            color_pages,
            total_pages,
            total_charged,
            0 AS sort_group,
            CASE WHEN detail_group = 'SUBTOTAL' THEN 1 WHEN detail_group = 'GRAND TOTAL' THEN 2 ELSE 0 END AS sort_detail
        FROM detail_rows

        UNION ALL

        SELECT
            summary_group,
            'SUBTOTAL' AS detail_group,
            SUM(jobs),
            SUM(copies),
            SUM(color_pages),
            SUM(total_pages),
            CAST(SUM(total_charged) AS decimal(12, 2)) AS total_charged,
            0 AS sort_group,
            1 AS sort_detail
        FROM detail_rows
        GROUP BY summary_group

        UNION ALL

        SELECT
            'GRAND TOTAL' AS summary_group,
            'GRAND TOTAL' AS detail_group,
            SUM(jobs),
            SUM(copies),
            SUM(color_pages),
            SUM(total_pages),
            CAST(SUM(total_charged) AS decimal(12, 2)) AS total_charged,
            1 AS sort_group,
            2 AS sort_detail
        FROM detail_rows
    )
    SELECT
        summary_group,
        detail_group,
        jobs,
        copies,
        color_pages,
        total_pages,
        total_charged
    FROM final_rows
    ORDER BY
        sort_group,
        summary_group,
        sort_detail,
        detail_group;
END;
GO

/*
Example execution:
EXEC dbo.usp_rpt_printer_summary_rollup
    @start_time = '2025-08-25T00:00:00',
    @end_time   = '2025-12-20T23:59:59';
*/
