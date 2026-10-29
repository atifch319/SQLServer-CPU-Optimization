/*
    SQLServer-CPU-Optimization
    database/02_CreateIndexes.sql

    Unique indexes enforce the natural keys.
    The other indexes are the baseline a careful schema would already have:
    one nonclustered index per foreign key, a covering index on OrderDate,
    and a covering index on OrderItems.OrderId.

    Scenario 03's sort-eliminating index is not created here.
    scenarios/03_UnnecessarySorting/Before.sql drops it if a previous After.sql
    left it behind. After.sql creates it. That is the change under test.

    Permission: db_owner on SqlServerCpuOptimization.
    Next script: database/03_SeedData.sql
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51002, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;
GO

/*
    Covering unique index for scenario 02.
    CustomerId is present automatically because it is the clustered key.
    INCLUDE keeps the after plan on a single seek: the scan-versus-seek
    difference is the implicit conversion, not a key lookup.
*/
CREATE UNIQUE NONCLUSTERED INDEX UQ_Customers_CustomerCode
    ON dbo.Customers (CustomerCode)
    INCLUDE (CustomerName, Email);
GO

CREATE UNIQUE NONCLUSTERED INDEX UQ_Products_ProductCode
    ON dbo.Products (ProductCode)
    INCLUDE (ProductName, UnitPrice);
GO

CREATE UNIQUE NONCLUSTERED INDEX UQ_Orders_OrderNumber
    ON dbo.Orders (OrderNumber);
GO

CREATE NONCLUSTERED INDEX IX_Orders_CustomerId
    ON dbo.Orders (CustomerId);
GO

/*
    Scenario 01 seeks this index only after the predicate stops wrapping
    OrderDate. The before query scans it (or the clustered index).
    Scenario 05 uses it to find a month of orders before touching line items.

    OrderId, the clustered key, is already at the leaf.
*/
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate
    ON dbo.Orders (OrderDate)
    INCLUDE (OrderNumber, CustomerId, Status, TotalAmount);
GO

/*
    Covering foreign-key index. Scenario 04 and scenario 05 read Quantity and
    UnitPrice by OrderId. ProductId is included so a line lookup does not key
    lookup either. Those lookups are not the mistakes this project measures.
*/
CREATE NONCLUSTERED INDEX IX_OrderItems_OrderId
    ON dbo.OrderItems (OrderId)
    INCLUDE (ProductId, Quantity, UnitPrice);
GO

CREATE NONCLUSTERED INDEX IX_OrderItems_ProductId
    ON dbo.OrderItems (ProductId);
GO

PRINT 'Indexes created. The scenario 03 index is intentionally absent. Next: database/03_SeedData.sql.';
GO
