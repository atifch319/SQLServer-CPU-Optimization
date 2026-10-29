/*
    SQLServer-CPU-Optimization
    diagnostics/04_StatisticsInspection.sql

    Shows statistic freshness for the demo tables and the histogram for
    IX_Orders_OrderDate.

    database/03_SeedData.sql rebuilds every index after the load. A rebuild
    writes a full-scan statistic, so rows_sampled should equal rows and
    last_updated should be the seed time. The scenario plans assume that.

    Auto update is left ON. This project does not modify data after the seed,
    so the full-scan histogram remains the one the optimizer uses. If you
    load more rows yourself, update statistics before comparing plans.
    A sampled update can keep the same seek or scan choice and still change
    the memory grant.

    DBCC SHOW_STATISTICS returns three result sets unless you pass a subject:
    header, density vector, and histogram. HISTOGRAM is the one that matters
    for the June range.

    Permission: VIEW DATABASE STATE for the DMV. DBCC SHOW_STATISTICS requires
    membership in a role that can read the table's statistics (db_owner).
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51043, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatisticName,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.steps,
    sp.modification_counter,
    sp.unfiltered_rows,
    CASE
        WHEN sp.rows IS NULL THEN NULL
        WHEN sp.rows = 0 THEN NULL
        ELSE CAST(100.0 * sp.rows_sampled / sp.rows AS decimal(5, 1))
    END AS sample_percent
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE s.object_id IN (
        OBJECT_ID(N'dbo.Customers'),
        OBJECT_ID(N'dbo.Products'),
        OBJECT_ID(N'dbo.Orders'),
        OBJECT_ID(N'dbo.OrderItems')
    )
ORDER BY TableName, StatisticName;

PRINT 'Histogram for IX_Orders_OrderDate. RANGE_HI_KEY is an OrderDate step. EQ_ROWS plus RANGE_ROWS describe how many orders sit at and between steps.';
GO

DBCC SHOW_STATISTICS (N'dbo.Orders', N'IX_Orders_OrderDate') WITH HISTOGRAM;
GO
