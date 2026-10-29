/*
    SQLServer-CPU-Optimization
    scenarios/03_UnnecessarySorting/Before.sql

    Top 100 shipped orders by TotalAmount, then OrderId.
    No index provides (Status, TotalAmount, OrderId), so the optimizer
    reads the shipped rows and runs a Top N Sort.

    This script drops IX_Orders_Status_TotalAmount_OrderId if After.sql
    already created it. Otherwise a second run of Before.sql would quietly
    seek that index and the sort would be gone.

    Expected result: 100 rows.
    Expected plan: a scan or a partial scan, a Filter or residual predicate
    for Status = 'Shipped', and a Sort operator (Top N Sort in the properties).
    There are 320,000 shipped orders. The sort input is that set, not 100 rows.

    IX_Orders_OrderDate does not remove this sort. It orders by OrderDate,
    and the query orders by TotalAmount.

    Measurement query: keep identical to benchmarks/RunBefore.sql scenario 03.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51025, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

DROP INDEX IF EXISTS IX_Orders_Status_TotalAmount_OrderId ON dbo.Orders;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 03 BEFORE. Record execution CPU time, elapsed time, logical reads, and the Sort operator.';

SELECT TOP (100)
    o.OrderId,
    o.OrderNumber,
    o.OrderDate,
    o.Status,
    o.TotalAmount
FROM dbo.Orders AS o
WHERE o.Status = 'Shipped'
ORDER BY o.TotalAmount DESC, o.OrderId DESC;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
