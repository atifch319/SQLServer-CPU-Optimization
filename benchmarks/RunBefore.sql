/*
    SQLServer-CPU-Optimization
    benchmarks/RunBefore.sql

    Warm-up and measured pass for all five before queries.
    Read benchmarks/BenchmarkInstructions.md before recording numbers.

    Include Actual Execution Plan must be off.
    The scenario 03 index is dropped so the sort is present.

    Each measured statement is the scenario query, aggregated on the server
    so the client does not fetch the full rowset. Row counts and checksums
    are printed for comparison with RunAfter.sql.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51050, 'Run this script in the SqlServerCpuOptimization database. Run database/00 through database/04 first.', 1;
END;

DROP INDEX IF EXISTS IX_Orders_Status_TotalAmount_OrderId ON dbo.Orders;

PRINT @@VERSION;
PRINT CONCAT('Compatibility level ', CAST(DATABASEPROPERTYEX(DB_NAME(), 'CompatibilityLevel') AS varchar(10)), '.');
PRINT 'Scenario 03 index dropped if it existed. Actual execution plan should be off. Record only blocks marked measured.';
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 01 BEFORE warm-up (do not record) ---';

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
    WHERE YEAR(o.OrderDate) = 2024
      AND MONTH(o.OrderDate) = 6
) AS q;

PRINT '--- Scenario 01 BEFORE measured ---';

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
    WHERE YEAR(o.OrderDate) = 2024
      AND MONTH(o.OrderDate) = 6
) AS q;

PRINT CONCAT('Scenario 01 BEFORE rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);
DECLARE @CustomerCode nvarchar(16) = N'C00010000';

PRINT '--- Scenario 02 BEFORE warm-up (do not record) ---';

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

PRINT '--- Scenario 02 BEFORE measured ---';

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

PRINT CONCAT('Scenario 02 BEFORE rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 03 BEFORE warm-up (do not record) ---';

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

PRINT '--- Scenario 03 BEFORE measured ---';

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

PRINT CONCAT('Scenario 03 BEFORE rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 04 BEFORE warm-up (do not record) ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.GrossAmount AS decimal(38, 4)))
FROM (
    SELECT
        oi.OrderItemId,
        oi.OrderId,
        dbo.fn_LineAmountWithTax(oi.Quantity, oi.UnitPrice) AS GrossAmount
    FROM dbo.OrderItems AS oi
    WHERE oi.OrderId <= 20000
) AS q;

PRINT '--- Scenario 04 BEFORE measured ---';

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(q.GrossAmount AS decimal(38, 4)))
FROM (
    SELECT
        oi.OrderItemId,
        oi.OrderId,
        dbo.fn_LineAmountWithTax(oi.Quantity, oi.UnitPrice) AS GrossAmount
    FROM dbo.OrderItems AS oi
    WHERE oi.OrderId <= 20000
) AS q;

PRINT CONCAT('Scenario 04 BEFORE rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @Rows bigint;
DECLARE @Check decimal(38, 4);

PRINT '--- Scenario 05 BEFORE warm-up (do not record) ---';

DROP TABLE IF EXISTS #OrderTotals;

SELECT
    o.OrderId,
    o.OrderNumber,
    o.CustomerId,
    o.OrderDate,
    o.Status,
    CAST(SUM(CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4))) AS decimal(19, 4)) AS CalculatedTotal
INTO #OrderTotals
FROM dbo.Orders AS o
INNER JOIN dbo.OrderItems AS oi
    ON oi.OrderId = o.OrderId
GROUP BY
    o.OrderId,
    o.OrderNumber,
    o.CustomerId,
    o.OrderDate,
    o.Status;

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(t.CalculatedTotal AS decimal(38, 4)))
FROM #OrderTotals AS t
WHERE t.Status = 'Open'
  AND t.OrderDate >= '20250601'
  AND t.OrderDate < '20250701';

PRINT '--- Scenario 05 BEFORE measured (add the two execution blocks) ---';

DROP TABLE IF EXISTS #OrderTotals;

SELECT
    o.OrderId,
    o.OrderNumber,
    o.CustomerId,
    o.OrderDate,
    o.Status,
    CAST(SUM(CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4))) AS decimal(19, 4)) AS CalculatedTotal
INTO #OrderTotals
FROM dbo.Orders AS o
INNER JOIN dbo.OrderItems AS oi
    ON oi.OrderId = o.OrderId
GROUP BY
    o.OrderId,
    o.OrderNumber,
    o.CustomerId,
    o.OrderDate,
    o.Status;

SELECT
    @Rows = COUNT_BIG(*),
    @Check = SUM(CAST(t.CalculatedTotal AS decimal(38, 4)))
FROM #OrderTotals AS t
WHERE t.Status = 'Open'
  AND t.OrderDate >= '20250601'
  AND t.OrderDate < '20250701';

PRINT CONCAT('Scenario 05 BEFORE rows=', @Rows, ' checksum=', CONVERT(varchar(40), @Check));

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

PRINT 'Before pass complete. Next: benchmarks/RunAfter.sql.';
GO
