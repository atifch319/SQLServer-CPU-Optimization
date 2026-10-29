/*
    SQLServer-CPU-Optimization
    database/01_CreateTables.sql

    Creates the order-management schema used by every scenario.

    Customers, products, orders, and order items are the whole model.
    dbo.fn_LineAmountWithTax is the scalar function exercised by scenario 04.
    It is created here because it is part of the deployed schema, not an index.

    Uniqueness of CustomerCode, OrderNumber, and ProductCode is enforced by
    unique indexes in 02_CreateIndexes.sql.

    Permission: db_owner on SqlServerCpuOptimization.
    Next script: database/02_CreateIndexes.sql
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51001, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

DROP FUNCTION IF EXISTS dbo.InlineLineAmountWithTax;
DROP FUNCTION IF EXISTS dbo.fn_LineAmountWithTax;
DROP TABLE IF EXISTS dbo.OrderItems;
DROP TABLE IF EXISTS dbo.Orders;
DROP TABLE IF EXISTS dbo.Products;
DROP TABLE IF EXISTS dbo.Customers;
GO

/*
    decimal(19, 4) is used for money values.
    The money type rounds with banker's rounding and is a poor fit for new work.
    float cannot represent most decimal fractions exactly.

    datetime2(0) stores order timestamps to one second (6 bytes).
    The sample never needs fractional seconds.

    CustomerId and ProductId fit in int at this scale.
    OrderId and OrderItemId are bigint so the keys are not the thing that
    runs out first if you raise the seed constants.
*/
CREATE TABLE dbo.Customers
(
    CustomerId   int            NOT NULL IDENTITY(1, 1),
    CustomerCode varchar(16)    NOT NULL,
    CustomerName nvarchar(100)  NOT NULL,
    Email        nvarchar(256)  NOT NULL,
    CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerId)
);
GO

CREATE TABLE dbo.Products
(
    ProductId   int            NOT NULL IDENTITY(1, 1),
    ProductCode varchar(16)    NOT NULL,
    ProductName nvarchar(100)  NOT NULL,
    UnitPrice   decimal(19, 4) NOT NULL,
    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductId),
    CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice >= 0)
);
GO

CREATE TABLE dbo.Orders
(
    OrderId     bigint         NOT NULL IDENTITY(1, 1),
    OrderNumber varchar(16)    NOT NULL,
    CustomerId  int            NOT NULL,
    OrderDate   datetime2(0)   NOT NULL,
    Status      varchar(20)    NOT NULL,
    TotalAmount decimal(19, 4) NOT NULL,
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderId),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (CustomerId),
    CONSTRAINT CK_Orders_Status CHECK (Status IN ('Open', 'Paid', 'Shipped', 'Cancelled', 'Returned')),
    CONSTRAINT CK_Orders_TotalAmount CHECK (TotalAmount >= 0)
);
GO

CREATE TABLE dbo.OrderItems
(
    OrderItemId bigint         NOT NULL IDENTITY(1, 1),
    OrderId     bigint         NOT NULL,
    ProductId   int            NOT NULL,
    Quantity    int            NOT NULL,
    UnitPrice   decimal(19, 4) NOT NULL,
    CONSTRAINT PK_OrderItems PRIMARY KEY CLUSTERED (OrderItemId),
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderId) REFERENCES dbo.Orders (OrderId),
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products (ProductId),
    CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OrderItems_UnitPrice CHECK (UnitPrice >= 0)
);
GO

/*
    Scenario 04 calls this function once per order line.

    WITH INLINE = OFF is deliberate. On SQL Server 2019+ (compatibility level
    150 or higher) a simple arithmetic scalar UDF is often inlined, and the
    CPU problem disappears. INLINE = OFF is the supported per-function switch
    that keeps the call in the plan. sys.sql_modules.inline_type is then 0.
    is_inlineable can still be 1: the body is eligible, and the option is what
    stops the inliner. Do not use EXECUTE AS OWNER for this. Impersonation
    adds a per-row security-context switch and swamps the comparison.

    The body is arithmetic only. It does not read a table.
    Keep the expression identical to scenarios/04_ScalarFunctions/After.sql
    and to dbo.InlineLineAmountWithTax created by that script.

    Gross amount = net line + tax, where tax is 8% of the net line rounded to
    the cent, then added back to the unrounded net. It is not ROUND(net * 1.08, 2).
*/
CREATE OR ALTER FUNCTION dbo.fn_LineAmountWithTax
(
    @Quantity int,
    @UnitPrice decimal(19, 4)
)
RETURNS decimal(19, 4)
WITH INLINE = OFF
AS
BEGIN
    DECLARE @Net decimal(19, 4) = CAST(@Quantity * @UnitPrice AS decimal(19, 4));
    DECLARE @Tax decimal(19, 4) = CAST(ROUND(@Net * 0.0800, 2) AS decimal(19, 4));
    RETURN CAST(@Net + @Tax AS decimal(19, 4));
END;
GO

SELECT
    OBJECT_SCHEMA_NAME(object_id) AS SchemaName,
    OBJECT_NAME(object_id) AS FunctionName,
    is_inlineable,
    inline_type
FROM sys.sql_modules
WHERE object_id = OBJECT_ID(N'dbo.fn_LineAmountWithTax');
GO

PRINT 'Tables and dbo.fn_LineAmountWithTax created. inline_type must be 0 (INLINE = OFF). is_inlineable may be 1. Next: database/02_CreateIndexes.sql.';
GO
