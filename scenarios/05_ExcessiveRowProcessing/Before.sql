/*
    SQLServer-CPU-Optimization
    scenarios/05_ExcessiveRowProcessing/Before.sql

    Stages a total for every order (400,000 orders, 1,600,000 lines),
    then keeps the 600 open orders from June 2025.

    The second filter is too late. SQL Server cannot push it into the
    statement that already wrote #OrderTotals.

    An outer WHERE wrapped around this join, without the temp table, is a
    weaker demo: the optimizer will usually push that predicate down.
    The materializing step is what makes the extra work reproducible.

    Expected final result: 600 rows.
    Expected work: a full pass over Orders and OrderItems, a hash or stream
    aggregate of 400,000 groups, a write of #OrderTotals, then a small filter.

    Re-runnable: the temp table is dropped first.
    Measurement statements: keep identical to benchmarks/RunBefore.sql scenario 05.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51030, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

DROP TABLE IF EXISTS #OrderTotals;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 05 BEFORE, statement 1 of 2: aggregate every order. Record this execution.';

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

PRINT 'Scenario 05 BEFORE, statement 2 of 2: keep June 2025 open orders. Add this CPU to statement 1.';

SELECT
    t.OrderId,
    t.OrderNumber,
    t.CustomerId,
    t.OrderDate,
    t.Status,
    t.CalculatedTotal
FROM #OrderTotals AS t
WHERE t.Status = 'Open'
  AND t.OrderDate >= '20250601'
  AND t.OrderDate < '20250701';

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
