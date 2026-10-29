/*
    SQLServer-CPU-Optimization
    database/03_SeedData.sql

    Deterministic, set-based load. No RAND(), no NEWID(), no real people.

    Scale, also asserted by database/04_VerifyData.sql:
        Customers          80,000
        Products            4,000
        Orders            400,000
        Items per order         4
        Order items     1,600,000
        Order-date window   1,000 days starting 2023-01-01
                            (2023-01-01 through 2025-09-26)
        Orders per day        400

    Status is taken from (OrderId / 1000) % 20, not from OrderId % 20.
    OrderId steps by 1,000 inside a single calendar day, so OrderId % 20
    would stamp an entire day with one status. Dividing by 1,000 first
    gives every day the same mix:
        20 Cancelled, 20 Returned, 20 Open, 20 Paid, 320 Shipped.

    Emails use the reserved example.test domain. Names are "Customer {id}".

    Indexes already exist (02). After the load, every index is rebuilt so
    later logical reads measure the query shape rather than page splits from
    the insert. Rebuild writes a full-scan statistic.

    Permission: db_owner. Recovery is SIMPLE (set in 00) so the log can reuse
    space. Expect roughly one to five minutes, depending on the drive.

    Requires GENERATE_SERIES? No. The tally is built from a cross join of
    VALUES so the load runs on SQL Server 2019 and SQL Server 2022.
    SQL Server 2022's GENERATE_SERIES(1, @OrderCount) is equivalent.

    Next script: database/04_VerifyData.sql
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51003, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

IF EXISTS (SELECT 1 FROM dbo.Customers)
    OR EXISTS (SELECT 1 FROM dbo.Products)
    OR EXISTS (SELECT 1 FROM dbo.Orders)
    OR EXISTS (SELECT 1 FROM dbo.OrderItems)
BEGIN
    THROW 51004, 'Tables are not empty. Re-run database/00_CreateDatabase.sql, then 01 and 02, before seeding.', 1;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UQ_Customers_CustomerCode'
      AND object_id = OBJECT_ID(N'dbo.Customers')
)
BEGIN
    THROW 51005, 'Unique indexes are missing. Run database/02_CreateIndexes.sql before seeding.', 1;
END;

DECLARE @CustomerCount int = 80000;
DECLARE @ProductCount int = 4000;
DECLARE @OrderCount int = 400000;
DECLARE @ItemsPerOrder int = 4;
DECLARE @DateOrigin datetime2(0) = '20230101';
DECLARE @DateSpanDays int = 1000;

PRINT CONCAT('Seeding ', @CustomerCount, ' customers.');

SET IDENTITY_INSERT dbo.Customers ON;

;WITH
Digits AS (
    SELECT digit
    FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) AS d(digit)
),
Numbers AS (
    SELECT TOP (@CustomerCount)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM Digits AS a
    CROSS JOIN Digits AS b
    CROSS JOIN Digits AS c
    CROSS JOIN Digits AS d
    CROSS JOIN Digits AS e
    CROSS JOIN Digits AS f
)
INSERT INTO dbo.Customers WITH (TABLOCK) (CustomerId, CustomerCode, CustomerName, Email)
SELECT
    n.n,
    CONCAT('C', RIGHT(CONCAT('00000000', n.n), 8)),
    CONCAT(N'Customer ', n.n),
    CONCAT(N'customer', n.n, N'@example.test')
FROM Numbers AS n
ORDER BY n.n;

SET IDENTITY_INSERT dbo.Customers OFF;

PRINT CONCAT('Seeding ', @ProductCount, ' products.');

SET IDENTITY_INSERT dbo.Products ON;

;WITH
Digits AS (
    SELECT digit
    FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) AS d(digit)
),
Numbers AS (
    SELECT TOP (@ProductCount)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM Digits AS a
    CROSS JOIN Digits AS b
    CROSS JOIN Digits AS c
    CROSS JOIN Digits AS d
    CROSS JOIN Digits AS e
)
INSERT INTO dbo.Products WITH (TABLOCK) (ProductId, ProductCode, ProductName, UnitPrice)
SELECT
    n.n,
    CONCAT('P', RIGHT(CONCAT('000000', n.n), 6)),
    CONCAT(N'Product ', n.n),
    CAST(5.0000 + ((n.n % 400) * 0.2500) AS decimal(19, 4))
FROM Numbers AS n
ORDER BY n.n;

SET IDENTITY_INSERT dbo.Products OFF;

PRINT CONCAT('Seeding ', @OrderCount, ' orders.');

SET IDENTITY_INSERT dbo.Orders ON;

;WITH
Digits AS (
    SELECT digit
    FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) AS d(digit)
),
Numbers AS (
    SELECT TOP (@OrderCount)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM Digits AS a
    CROSS JOIN Digits AS b
    CROSS JOIN Digits AS c
    CROSS JOIN Digits AS d
    CROSS JOIN Digits AS e
    CROSS JOIN Digits AS f
)
INSERT INTO dbo.Orders WITH (TABLOCK)
(
    OrderId,
    OrderNumber,
    CustomerId,
    OrderDate,
    Status,
    TotalAmount
)
SELECT
    n.n,
    CONCAT('ORD', RIGHT(CONCAT('00000000', n.n), 8)),
    ((n.n - 1) % @CustomerCount) + 1,
    DATEADD(
        hour,
        (n.n % 14) + 8,
        DATEADD(day, (n.n - 1) % @DateSpanDays, @DateOrigin)
    ),
    CASE (n.n / 1000) % 20
        WHEN 0 THEN 'Cancelled'
        WHEN 1 THEN 'Returned'
        WHEN 2 THEN 'Open'
        WHEN 3 THEN 'Paid'
        ELSE 'Shipped'
    END,
    CAST(0 AS decimal(19, 4))
FROM Numbers AS n
ORDER BY n.n;

SET IDENTITY_INSERT dbo.Orders OFF;

PRINT CONCAT('Seeding ', @OrderCount * @ItemsPerOrder, ' order items.');

SET IDENTITY_INSERT dbo.OrderItems ON;

;WITH Slots AS (
    SELECT slot
    FROM (VALUES (1), (2), (3), (4)) AS s(slot)
)
INSERT INTO dbo.OrderItems WITH (TABLOCK)
(
    OrderItemId,
    OrderId,
    ProductId,
    Quantity,
    UnitPrice
)
SELECT
    ((o.OrderId - 1) * @ItemsPerOrder) + s.slot,
    o.OrderId,
    p.ProductId,
    ((o.OrderId + s.slot) % 5) + 1,
    p.UnitPrice
FROM dbo.Orders AS o
CROSS JOIN Slots AS s
INNER JOIN dbo.Products AS p
    ON p.ProductId = ((o.OrderId + s.slot) % @ProductCount) + 1
ORDER BY o.OrderId, s.slot;

SET IDENTITY_INSERT dbo.OrderItems OFF;

PRINT 'Setting Orders.TotalAmount from order lines (pre-tax merchandise total).';

UPDATE o
SET o.TotalAmount = x.LineTotal
FROM dbo.Orders AS o
INNER JOIN (
    SELECT
        oi.OrderId,
        CAST(SUM(CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4))) AS decimal(19, 4)) AS LineTotal
    FROM dbo.OrderItems AS oi
    GROUP BY oi.OrderId
) AS x
    ON x.OrderId = o.OrderId
WHERE o.TotalAmount <> x.LineTotal;

PRINT 'Rebuilding indexes to clear load fragmentation and refresh full-scan statistics.';

ALTER INDEX ALL ON dbo.Customers REBUILD;
ALTER INDEX ALL ON dbo.Products REBUILD;
ALTER INDEX ALL ON dbo.Orders REBUILD;
ALTER INDEX ALL ON dbo.OrderItems REBUILD;

DBCC CHECKIDENT (N'dbo.Customers', RESEED, 80000) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.Products', RESEED, 4000) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.Orders', RESEED, 400000) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.OrderItems', RESEED, 1600000) WITH NO_INFOMSGS;

PRINT 'Seed complete. Next: database/04_VerifyData.sql.';
GO
