/*
    SQLServer-CPU-Optimization
    diagnostics/03_IndexUsage.sql

    Shows seek, scan, lookup, and update counters for the demo indexes,
    then runs the scenario 01 predicates and prints the delta.

    sys.dm_db_index_usage_stats is cumulative since the index was created
    or rebuilt, and since SQL Server started. It is empty for an index that
    has not been used. Counters are database-wide, so other sessions move them.

    A seek is not automatically better than a scan: a seek that is executed
    hundreds of thousands of times inside nested loops can be the problem.
    In this demo the comparison is one scan of Orders versus one range seek.

    Permission: VIEW DATABASE STATE. db_owner has CONTROL, which covers it.
    The delta section only reads and does not change schema.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51042, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc,
    ISNULL(us.user_seeks, 0) AS user_seeks,
    ISNULL(us.user_scans, 0) AS user_scans,
    ISNULL(us.user_lookups, 0) AS user_lookups,
    ISNULL(us.user_updates, 0) AS user_updates,
    us.last_user_seek,
    us.last_user_scan
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS us
    ON us.database_id = DB_ID()
   AND us.object_id = i.object_id
   AND us.index_id = i.index_id
WHERE i.object_id IN (
        OBJECT_ID(N'dbo.Customers'),
        OBJECT_ID(N'dbo.Products'),
        OBJECT_ID(N'dbo.Orders'),
        OBJECT_ID(N'dbo.OrderItems')
    )
  AND i.type_desc <> N'HEAP'
ORDER BY TableName, IndexName;
GO

DECLARE @Before TABLE
(
    IndexName sysname NOT NULL PRIMARY KEY,
    user_seeks bigint NOT NULL,
    user_scans bigint NOT NULL
);

INSERT INTO @Before (IndexName, user_seeks, user_scans)
SELECT
    i.name,
    ISNULL(us.user_seeks, 0),
    ISNULL(us.user_scans, 0)
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS us
    ON us.database_id = DB_ID()
   AND us.object_id = i.object_id
   AND us.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'dbo.Orders')
  AND i.name IN (N'IX_Orders_OrderDate', N'PK_Orders');

DECLARE @Rows int;

SELECT @Rows = COUNT(*)
FROM dbo.Orders AS o
WHERE YEAR(o.OrderDate) = 2024
  AND MONTH(o.OrderDate) = 6;

SELECT @Rows = COUNT(*)
FROM dbo.Orders AS o
WHERE o.OrderDate >= '20240601'
  AND o.OrderDate < '20240701';

SELECT
    b.IndexName,
    a.user_seeks - b.user_seeks AS seeks_during_demo,
    a.user_scans - b.user_scans AS scans_during_demo
FROM @Before AS b
INNER JOIN (
    SELECT
        i.name AS IndexName,
        ISNULL(us.user_seeks, 0) AS user_seeks,
        ISNULL(us.user_scans, 0) AS user_scans
    FROM sys.indexes AS i
    LEFT JOIN sys.dm_db_index_usage_stats AS us
        ON us.database_id = DB_ID()
       AND us.object_id = i.object_id
       AND us.index_id = i.index_id
    WHERE i.object_id = OBJECT_ID(N'dbo.Orders')
      AND i.name IN (N'IX_Orders_OrderDate', N'PK_Orders')
) AS a
    ON a.IndexName = b.IndexName
ORDER BY b.IndexName;

PRINT 'The delta covers two statements: YEAR/MONTH (scan) and the half-open range (seek).';
PRINT 'IX_Orders_OrderDate should show a scan increase and a seek increase. PK_Orders may stay flat when the nonclustered index covers both queries.';
PRINT CONCAT('Each statement counted ', @Rows, ' June 2024 orders.');
GO
