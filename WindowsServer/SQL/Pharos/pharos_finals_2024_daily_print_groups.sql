USE [pharos];
GO

/*
Purpose:
- Returns a day-by-day view of print-group activity for the two finals periods:
  - Spring 2024: May 11, 2024 through May 17, 2024
  - Fall 2024: December 11, 2024 through December 17, 2024
- Includes a grand total row at the end of each day.
*/

WITH report_dates AS (
    SELECT CAST('2024-05-11' AS date) AS report_date, 'Spring 2024 Finals' AS finals_period
    UNION ALL SELECT '2024-05-12', 'Spring 2024 Finals'
    UNION ALL SELECT '2024-05-13', 'Spring 2024 Finals'
    UNION ALL SELECT '2024-05-14', 'Spring 2024 Finals'
    UNION ALL SELECT '2024-05-15', 'Spring 2024 Finals'
    UNION ALL SELECT '2024-05-16', 'Spring 2024 Finals'
    UNION ALL SELECT '2024-05-17', 'Spring 2024 Finals'
    UNION ALL SELECT '2024-12-11', 'Fall 2024 Finals'
    UNION ALL SELECT '2024-12-12', 'Fall 2024 Finals'
    UNION ALL SELECT '2024-12-13', 'Fall 2024 Finals'
    UNION ALL SELECT '2024-12-14', 'Fall 2024 Finals'
    UNION ALL SELECT '2024-12-15', 'Fall 2024 Finals'
    UNION ALL SELECT '2024-12-16', 'Fall 2024 Finals'
    UNION ALL SELECT '2024-12-17', 'Fall 2024 Finals'
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
        '2024-05-11','2024-05-12','2024-05-13','2024-05-14','2024-05-15','2024-05-16','2024-05-17',
        '2024-12-11','2024-12-12','2024-12-13','2024-12-14','2024-12-15','2024-12-16','2024-12-17'
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
