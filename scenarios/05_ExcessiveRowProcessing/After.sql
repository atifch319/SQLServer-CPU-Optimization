/*
    SQLServer-CPU-Optimization
    scenarios/05_ExcessiveRowProcessing/After.sql

    Filters orders to the 600 open June 2025 rows first, then joins the
    line items for those orders and aggregates.

    Same 600 rows and the same totals as Before.sql statement 2.
    IX_Orders_OrderDate supports the date range. Status is a residual
    predicate on that index unless a better Status index is present.
    The scenario 03 index is not required. If it exists, the optimizer may
    use it; the row reduction still comes from the predicate, not from that index.

    Expected plan: a seek (or a selective range read) of Orders, nested loops
    or a small hash into IX_OrderItems_OrderId, and an aggregate of about
    2,400 lines (600 orders * 4). Not an aggregate of 1,600,000 lines.

    Measurement query: keep identical to benchmarks/RunAfter.sql scenario 05.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51031, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 05 AFTER. Record execution CPU time, elapsed time, and logical reads.';

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
    o.Status;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
