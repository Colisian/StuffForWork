USE [pharos];
GO

/*
Purpose:
- Returns a day-by-day view of print-group activity for the two finals periods:
  - Spring 2025: May 15, 2025 through May 21, 2025
  - Fall 2025: December 15, 2025 through December 20, 2025
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
tpa_agg AS (
    SELECT
        transaction_id,
        SUM(ISNULL(num_pages, 0)) AS total_pages
    FROM dbo.transaction_print_attributes
    GROUP BY transaction_id
),
base AS (
    SELECT
        CAST(t.[time] AS date) AS report_date,
        t.transaction_id,
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
        END AS summary_group
    FROM dbo.transactions t
    JOIN dbo.print_transactions pt
        ON pt.transaction_id = t.transaction_id
    LEFT JOIN tpa_agg tpa
        ON tpa.transaction_id = t.transaction_id
    WHERE CAST(t.[time] AS date) IN (
        '2025-05-15','2025-05-16','2025-05-17','2025-05-18','2025-05-19','2025-05-20','2025-05-21',
        '2025-12-15','2025-12-16','2025-12-17','2025-12-18','2025-12-19','2025-12-20'
    )
),
detail_rows AS (
    SELECT
        rd.finals_period,
        rd.report_date,
        b.summary_group,
        b.print_group AS detail_group,
        COUNT(b.transaction_id) AS jobs,
        SUM(b.copies) AS copies,
        SUM(b.color_pages) AS color_pages,
        SUM(b.total_pages) AS total_pages,
        CAST(SUM(-1.0 * b.amount) AS decimal(12,2)) AS total_charged,
        0 AS sort_order
    FROM report_dates rd
    LEFT JOIN base b
        ON b.report_date = rd.report_date
    GROUP BY
        rd.finals_period,
        rd.report_date,
        b.summary_group,
        b.print_group
    HAVING COUNT(b.transaction_id) > 0
),
final_rows AS (
    SELECT
        finals_period,
        report_date,
        summary_group,
        detail_group,
        jobs,
        copies,
        color_pages,
        total_pages,
        total_charged,
        sort_order
    FROM detail_rows

    UNION ALL

    SELECT
        finals_period,
        report_date,
        'GRAND TOTAL' AS summary_group,
        'GRAND TOTAL' AS detail_group,
        SUM(jobs),
        SUM(copies),
        SUM(color_pages),
        SUM(total_pages),
        CAST(SUM(total_charged) AS decimal(12,2)) AS total_charged,
        1 AS sort_order
    FROM detail_rows
    GROUP BY
        finals_period,
        report_date
)
SELECT
    finals_period,
    report_date,
    summary_group,
    detail_group,
    jobs,
    copies,
    color_pages,
    total_pages,
    total_charged
FROM final_rows
ORDER BY
    report_date,
    sort_order,
    summary_group,
    detail_group;
GO
