/*
    SQLServer-CPU-Optimization
    benchmarks/RunAfter.sql

    Warm-up and measured pass for all five after queries.
    Read benchmarks/BenchmarkInstructions.md. Run RunBefore.sql first if you
    want a paired comparison. This script creates the scenario 03 index
    before that scenario's warm-up.

    Include Actual Execution Plan must be off.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51051, 'Run this script in the SqlServerCpuOptimization database. Run database/00 through database/04 first.', 1;
END;

PRINT @@VERSION;
PRINT CONCAT('Compatibility level ', CAST(DATABASEPROPERTYEX(DB_NAME(), 'CompatibilityLevel') AS varchar(10)), '.');
PRINT 'Record only blocks marked measured. Do not record the index build.';

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_Orders_Status_TotalAmount_OrderId'
      AND object_id = OBJECT_ID(N'dbo.Orders')
)
BEGIN
    PRINT 'Creating IX_Orders_Status_TotalAmount_OrderId for scenario 03.';

    CREATE NONCLUSTERED INDEX IX_Orders_Status_TotalAmount_OrderId
        ON dbo.Orders (Status, TotalAmount DESC, OrderId DESC)
        INCLUDE (OrderNumber, OrderDate);
END
ELSE
BEGIN
    PRINT 'IX_Orders_Status_TotalAmount_OrderId already exists.';
END;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 01 AFTER warm-up (do not record) ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.TotalAmount AS decimal(38, 4)))
FROM (
    SELECT
        o.OrderId,
        o.OrderNumber,
        o.CustomerId,
        o.OrderDate,
        o.Status,
        o.TotalAmount
    FROM dbo.Orders AS o
    WHERE o.OrderDate >= '20240601'
      AND o.OrderDate < '20240701'
) AS q;

PRINT '--- Scenario 01 AFTER measured ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.TotalAmount AS decimal(38, 4)))
FROM (
    SELECT
        o.OrderId,
        o.OrderNumber,
        o.CustomerId,
        o.OrderDate,
        o.Status,
        o.TotalAmount
    FROM dbo.Orders AS o
    WHERE o.OrderDate >= '20240601'
      AND o.OrderDate < '20240701'
) AS q;

PRINT CONCAT('Scenario 01 AFTER rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);
DECLARE @CustomerCode varchar(16) = 'C00010000';

PRINT '--- Scenario 02 AFTER warm-up (do not record) ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.CustomerId AS decimal(38, 4)))
FROM (
    SELECT
        c.CustomerId,
        c.CustomerCode,
        c.CustomerName,
        c.Email
    FROM dbo.Customers AS c
    WHERE c.CustomerCode = @CustomerCode
) AS q;

PRINT '--- Scenario 02 AFTER measured ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.CustomerId AS decimal(38, 4)))
FROM (
    SELECT
        c.CustomerId,
        c.CustomerCode,
        c.CustomerName,
        c.Email
    FROM dbo.Customers AS c
    WHERE c.CustomerCode = @CustomerCode
) AS q;

PRINT CONCAT('Scenario 02 AFTER rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 03 AFTER warm-up (do not record) ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.TotalAmount AS decimal(38, 4)))
FROM (
    SELECT TOP (100)
        o.OrderId,
        o.OrderNumber,
        o.OrderDate,
        o.Status,
        o.TotalAmount
    FROM dbo.Orders AS o
    WHERE o.Status = 'Shipped'
    ORDER BY o.TotalAmount DESC, o.OrderId DESC
) AS q;

PRINT '--- Scenario 03 AFTER measured ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.TotalAmount AS decimal(38, 4)))
FROM (
    SELECT TOP (100)
        o.OrderId,
        o.OrderNumber,
        o.OrderDate,
        o.Status,
        o.TotalAmount
    FROM dbo.Orders AS o
    WHERE o.Status = 'Shipped'
    ORDER BY o.TotalAmount DESC, o.OrderId DESC
) AS q;

PRINT CONCAT('Scenario 03 AFTER rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 04 AFTER warm-up (do not record) ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.GrossAmount AS decimal(38, 4)))
FROM (
    SELECT
        oi.OrderItemId,
        oi.OrderId,
        CAST(c.Net + CAST(ROUND(c.Net * 0.0800, 2) AS decimal(19, 4)) AS decimal(19, 4)) AS GrossAmount
    FROM dbo.OrderItems AS oi
    CROSS APPLY (
        SELECT CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4)) AS Net
    ) AS c
    WHERE oi.OrderId <= 20000
) AS q;

PRINT '--- Scenario 04 AFTER measured ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.GrossAmount AS decimal(38, 4)))
FROM (
    SELECT
        oi.OrderItemId,
        oi.OrderId,
        CAST(c.Net + CAST(ROUND(c.Net * 0.0800, 2) AS decimal(19, 4)) AS decimal(19, 4)) AS GrossAmount
    FROM dbo.OrderItems AS oi
    CROSS APPLY (
        SELECT CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4)) AS Net
    ) AS c
    WHERE oi.OrderId <= 20000
) AS q;

PRINT CONCAT('Scenario 04 AFTER rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 05 AFTER warm-up (do not record) ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.CalculatedTotal AS decimal(38, 4)))
FROM (
    SELECT
        o.OrderId,
        o.OrderNumber,
        o.CustomerId,
        o.OrderDate,
        o.Status,
        CAST(SUM(CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4))) AS decimal(19, 4)) AS CalculatedTotal
    FROM dbo.Orders AS o
    INNER JOIN dbo.OrderItems AS oi
        ON oi.OrderId = o.OrderId
    WHERE o.Status = 'Open'
      AND o.OrderDate >= '20250601'
      AND o.OrderDate < '20250701'
    GROUP BY
        o.OrderId,
        o.OrderNumber,
        o.CustomerId,
        o.OrderDate,
        o.Status
) AS q;

PRINT '--- Scenario 05 AFTER measured ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.CalculatedTotal AS decimal(38, 4)))
FROM (
    SELECT
        o.OrderId,
        o.OrderNumber,
        o.CustomerId,
        o.OrderDate,
        o.Status,
        CAST(SUM(CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4))) AS decimal(19, 4)) AS CalculatedTotal
    FROM dbo.Orders AS o
    INNER JOIN dbo.OrderItems AS oi
        ON oi.OrderId = o.OrderId
    WHERE o.Status = 'Open'
      AND o.OrderDate >= '20250601'
      AND o.OrderDate < '20250701'
    GROUP BY
        o.OrderId,
        o.OrderNumber,
        o.CustomerId,
        o.OrderDate,
        o.Status
) AS q;

PRINT CONCAT('Scenario 05 AFTER rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

PRINT 'After pass complete. Compare checksums with RunBefore.sql, then fill benchmarks/ResultsTemplate.md.';
GO
