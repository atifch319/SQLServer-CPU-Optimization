/*
    SQLServer-CPU-Optimization
    scenarios/01_NonSargablePredicates/After.sql

    Same June 2024 orders as Before.sql. OrderDate is bare, so the optimizer
    can seek IX_Orders_OrderDate.

    The range is half-open: >= 2024-06-01 and < 2024-07-01.
    datetime2(0) values in this database never fall on 2024-07-01 00:00:00
    for a June order, and a half-open range stays correct if the precision
    changes. BETWEEN would need an inclusive end that is easy to get wrong.

    '20240601' is unseparated and unambiguous regardless of DATEFORMAT.
    The literal is converted once. The column is not converted.

    Expected result: 12,000 rows, the same rows as Before.sql.
    Expected plan: Index Seek on IX_Orders_OrderDate.
    Logical reads should fall from a scan of Orders to the pages that hold
    those 12,000 rows.

    Measurement query: keep identical to benchmarks/RunAfter.sql scenario 01.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51022, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 01 AFTER. Record the execution CPU time, elapsed time, and logical reads.';

SELECT
    o.OrderId,
    o.OrderNumber,
    o.CustomerId,
    o.OrderDate,
    o.Status,
    o.TotalAmount
FROM dbo.Orders AS o
WHERE o.OrderDate >= '20240601'
  AND o.OrderDate < '20240701';

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
