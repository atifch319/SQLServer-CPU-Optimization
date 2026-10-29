/*
    SQLServer-CPU-Optimization
    scenarios/03_UnnecessarySorting/After.sql

    Creates the index that matches the query, then runs the same SELECT.

    Key order is equality column first (Status), then the ORDER BY columns
    (TotalAmount DESC, OrderId DESC). The INCLUDE list covers the SELECT
    list. OrderId is part of the key, not only the clustered-key bookmark.

    Time the SELECT, not the CREATE INDEX. The first execution after the
    build also compiles and reads the new index. Run the SELECT a second
    time and record that execution. benchmarks/RunAfter.sql does the
    warm-up for you.

    Expected plan: Index Seek (or an ordered Index Scan of the Status range)
    on IX_Orders_Status_TotalAmount_OrderId, no Sort operator.
    The engine stops after 100 rows.

    Measurement query: keep identical to benchmarks/RunAfter.sql scenario 03.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51026, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_Orders_Status_TotalAmount_OrderId'
      AND object_id = OBJECT_ID(N'dbo.Orders')
)
BEGIN
    PRINT 'Creating IX_Orders_Status_TotalAmount_OrderId. Do not record this build as query CPU.';

    CREATE NONCLUSTERED INDEX IX_Orders_Status_TotalAmount_OrderId
        ON dbo.Orders (Status, TotalAmount DESC, OrderId DESC)
        INCLUDE (OrderNumber, OrderDate);
END
ELSE
BEGIN
    PRINT 'IX_Orders_Status_TotalAmount_OrderId already exists.';
END;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 03 AFTER. Record this execution only if you have run it once already, or use benchmarks/RunAfter.sql.';

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
