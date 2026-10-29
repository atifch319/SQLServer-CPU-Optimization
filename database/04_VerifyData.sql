/*
    SQLServer-CPU-Optimization
    database/04_VerifyData.sql

    Fails the batch if the loaded data does not match the contract the
    scenario scripts depend on. All mismatches are returned in one result
    set, then the script throws.

    Keep the constants aligned with database/03_SeedData.sql.

    Permission: db_owner (the statistic check uses a database-scoped DMV;
    CONTROL on the database covers it).
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51006, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

DECLARE @CustomerCount int = 80000;
DECLARE @ProductCount int = 4000;
DECLARE @OrderCount int = 400000;
DECLARE @ItemsPerOrder int = 4;
DECLARE @OrderItemCount int = 1600000;
DECLARE @DateOrigin datetime2(0) = '20230101';
DECLARE @DateSpanDays int = 1000;
DECLARE @OrdersPerDay int = 400;
DECLARE @JuneOrderCount int = 12000; -- 400 orders/day * 30 days
DECLARE @JuneOpenCount int = 600;    -- 20 open orders/day * 30 days
DECLARE @ShippedCount int = 320000;  -- 16/20 of 400,000
DECLARE @ExpectedMaxDate date = DATEADD(day, @DateSpanDays - 1, CONVERT(date, @DateOrigin));

DECLARE @Failures TABLE
(
    CheckName varchar(80)  NOT NULL,
    Expected  varchar(40)  NOT NULL,
    Actual    varchar(40)  NOT NULL
);

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    v.CheckName,
    v.Expected,
    v.Actual
FROM (
    SELECT 'Customers' AS CheckName, CAST(@CustomerCount AS varchar(40)) AS Expected, CAST(COUNT(*) AS varchar(40)) AS Actual
    FROM dbo.Customers
    UNION ALL
    SELECT 'Products', CAST(@ProductCount AS varchar(40)), CAST(COUNT(*) AS varchar(40))
    FROM dbo.Products
    UNION ALL
    SELECT 'Orders', CAST(@OrderCount AS varchar(40)), CAST(COUNT(*) AS varchar(40))
    FROM dbo.Orders
    UNION ALL
    SELECT 'OrderItems', CAST(@OrderItemCount AS varchar(40)), CAST(COUNT(*) AS varchar(40))
    FROM dbo.OrderItems
) AS v
WHERE v.Expected <> v.Actual;

IF EXISTS (
    SELECT 1
    FROM dbo.Orders AS o
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Customers AS c
        WHERE c.CustomerId = o.CustomerId
    )
)
BEGIN
    INSERT INTO @Failures (CheckName, Expected, Actual)
    VALUES ('Orders without a customer', '0', '1 or more');
END;

IF EXISTS (
    SELECT 1
    FROM dbo.OrderItems AS oi
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Orders AS o WHERE o.OrderId = oi.OrderId
    )
    OR NOT EXISTS (
        SELECT 1 FROM dbo.Products AS p WHERE p.ProductId = oi.ProductId
    )
)
BEGIN
    INSERT INTO @Failures (CheckName, Expected, Actual)
    VALUES ('Order items with a broken foreign key', '0', '1 or more');
END;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Orders whose TotalAmount disagrees with SUM(Quantity * UnitPrice)',
    '0',
    CAST(COUNT(*) AS varchar(40))
FROM dbo.Orders AS o
INNER JOIN (
    SELECT
        oi.OrderId,
        CAST(SUM(CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4))) AS decimal(19, 4)) AS LineTotal
    FROM dbo.OrderItems AS oi
    GROUP BY oi.OrderId
) AS x
    ON x.OrderId = o.OrderId
WHERE o.TotalAmount <> x.LineTotal
HAVING COUNT(*) > 0;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Minimum order date',
    CONVERT(char(10), @DateOrigin, 23),
    CONVERT(char(10), MIN(OrderDate), 23)
FROM dbo.Orders
HAVING CONVERT(date, MIN(OrderDate)) <> CONVERT(date, @DateOrigin);

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Maximum order date',
    CONVERT(char(10), @ExpectedMaxDate, 23),
    CONVERT(char(10), MAX(OrderDate), 23)
FROM dbo.Orders
HAVING CONVERT(date, MAX(OrderDate)) <> @ExpectedMaxDate;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Orders on 2024-06-01 through 2024-06-30',
    CAST(@JuneOrderCount AS varchar(40)),
    CAST(COUNT(*) AS varchar(40))
FROM dbo.Orders
WHERE OrderDate >= '20240601'
  AND OrderDate < '20240701'
HAVING COUNT(*) <> @JuneOrderCount;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Open orders on 2025-06-01 through 2025-06-30',
    CAST(@JuneOpenCount AS varchar(40)),
    CAST(COUNT(*) AS varchar(40))
FROM dbo.Orders
WHERE Status = 'Open'
  AND OrderDate >= '20250601'
  AND OrderDate < '20250701'
HAVING COUNT(*) <> @JuneOpenCount;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Shipped orders',
    CAST(@ShippedCount AS varchar(40)),
    CAST(COUNT(*) AS varchar(40))
FROM dbo.Orders
WHERE Status = 'Shipped'
HAVING COUNT(*) <> @ShippedCount;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.Customers
    WHERE CustomerId = 10000
      AND CustomerCode = 'C00010000'
      AND Email = N'customer10000@example.test'
)
BEGIN
    INSERT INTO @Failures (CheckName, Expected, Actual)
    VALUES ('Customer 10000 code and email', 'C00010000 / customer10000@example.test', 'mismatch');
END;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.Orders
    WHERE OrderId = 1
      AND OrderNumber = 'ORD00000001'
      AND CustomerId = 1
      AND Status = 'Cancelled'
      AND CONVERT(date, OrderDate) = '20230101'
)
BEGIN
    INSERT INTO @Failures (CheckName, Expected, Actual)
    VALUES ('Order 1 natural values', 'ORD00000001 / Cancelled / 2023-01-01', 'mismatch');
END;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.Orders
    WHERE OrderId = 518
      AND CONVERT(date, OrderDate) = '20240601'
)
BEGIN
    INSERT INTO @Failures (CheckName, Expected, Actual)
    VALUES ('Order 518 calendar anchor', '2024-06-01', 'mismatch');
END;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Distinct order dates',
    CAST(@DateSpanDays AS varchar(40)),
    CAST(COUNT(*) AS varchar(40))
FROM (
    SELECT CONVERT(date, OrderDate) AS OrderDay
    FROM dbo.Orders
    GROUP BY CONVERT(date, OrderDate)
) AS days
HAVING COUNT(*) <> @DateSpanDays;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Days whose order count is not 400',
    '0',
    CAST(COUNT(*) AS varchar(40))
FROM (
    SELECT CONVERT(date, OrderDate) AS OrderDay
    FROM dbo.Orders
    GROUP BY CONVERT(date, OrderDate)
    HAVING COUNT(*) <> @OrdersPerDay
) AS uneven
HAVING COUNT(*) > 0;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Lines per order that are not ' + CAST(@ItemsPerOrder AS varchar(11)),
    '0',
    CAST(COUNT(*) AS varchar(40))
FROM (
    SELECT oi.OrderId
    FROM dbo.OrderItems AS oi
    GROUP BY oi.OrderId
    HAVING COUNT(*) <> @ItemsPerOrder
) AS uneven
HAVING COUNT(*) > 0;

IF OBJECT_ID(N'dbo.fn_LineAmountWithTax', N'FN') IS NULL
BEGIN
    INSERT INTO @Failures (CheckName, Expected, Actual)
    VALUES ('dbo.fn_LineAmountWithTax', 'present', 'missing');
END
ELSE IF EXISTS (
    SELECT 1
    FROM sys.sql_modules
    WHERE object_id = OBJECT_ID(N'dbo.fn_LineAmountWithTax')
      AND (inline_type IS NULL OR inline_type <> 0)
)
BEGIN
    INSERT INTO @Failures (CheckName, Expected, Actual)
    VALUES ('fn_LineAmountWithTax.inline_type', '0', 'not 0');
END;

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    'Full-scan statistic ' + s.name,
    'rows_sampled = rows',
    CONCAT(sp.rows_sampled, ' of ', sp.rows)
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE s.object_id = OBJECT_ID(N'dbo.Orders')
  AND s.name = N'IX_Orders_OrderDate'
  AND sp.rows_sampled <> sp.rows;

DECLARE @RequiredIndex TABLE (IndexName sysname NOT NULL, TableName sysname NOT NULL);
INSERT INTO @RequiredIndex (IndexName, TableName)
VALUES
    (N'UQ_Customers_CustomerCode', N'Customers'),
    (N'UQ_Products_ProductCode', N'Products'),
    (N'UQ_Orders_OrderNumber', N'Orders'),
    (N'IX_Orders_CustomerId', N'Orders'),
    (N'IX_Orders_OrderDate', N'Orders'),
    (N'IX_OrderItems_OrderId', N'OrderItems'),
    (N'IX_OrderItems_ProductId', N'OrderItems');

INSERT INTO @Failures (CheckName, Expected, Actual)
SELECT
    CONCAT('Index ', r.IndexName),
    'present',
    'missing'
FROM @RequiredIndex AS r
WHERE NOT EXISTS (
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.name = r.IndexName
      AND i.object_id = OBJECT_ID(N'dbo.' + r.TableName)
);

IF EXISTS (SELECT 1 FROM @Failures)
BEGIN
    SELECT CheckName, Expected, Actual
    FROM @Failures
    ORDER BY CheckName;

    THROW 51010, 'Data verification failed. The result grid lists every mismatch.', 1;
END;

PRINT 'Verification passed.';
PRINT CONCAT('Customers=', @CustomerCount, ', Products=', @ProductCount, ', Orders=', @OrderCount, ', OrderItems=', @OrderItemCount, '.');
PRINT 'June 2024 orders=12000. June 2025 open orders=600. Shipped orders=320000.';
PRINT 'fn_LineAmountWithTax is present and inline_type = 0 (INLINE = OFF).';
PRINT 'Next: scenarios/01_NonSargablePredicates/Before.sql, or benchmarks/RunBefore.sql.';
GO
