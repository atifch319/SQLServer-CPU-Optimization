/*
    SQLServer-CPU-Optimization
    scenarios/01_NonSargablePredicates/Before.sql

    Non-sargable predicate: YEAR() and MONTH() wrap OrderDate.
    The index IX_Orders_OrderDate cannot be seeked. Every order date is
    extracted and compared.

    Expected result: 12,000 rows (June 2024).
    Expected plan: an index scan or clustered index scan, not an index seek.
    The scan may be parallel. CPU time can then exceed elapsed time.

    Record "SQL Server Execution Times", not "parse and compile time".
    Run the script a second time before comparing elapsed time.
    Turn Include Actual Execution Plan off while you are timing, then on
    when you want the operators. Actual plans add overhead.

    Measurement query: keep identical to benchmarks/RunBefore.sql scenario 01.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51021, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 01 BEFORE. Record the execution CPU time, elapsed time, and logical reads.';

SELECT
    o.OrderId,
    o.OrderNumber,
    o.CustomerId,
    o.OrderDate,
    o.Status,
    o.TotalAmount
FROM dbo.Orders AS o
WHERE YEAR(o.OrderDate) = 2024
  AND MONTH(o.OrderDate) = 6;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
