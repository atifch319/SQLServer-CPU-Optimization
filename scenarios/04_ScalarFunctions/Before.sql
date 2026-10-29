/*
    SQLServer-CPU-Optimization
    scenarios/04_ScalarFunctions/Before.sql

    Calls dbo.fn_LineAmountWithTax once per order line for orders 1 through
    20000 (80,000 lines). The predicate on OrderId is sargable on purpose.
    IO should look similar to After.sql. CPU should not.

    The function is created in database/01_CreateTables.sql WITH INLINE = OFF.
    Confirm inline_type = 0 in the first result grid before reading timings.
    is_inlineable may be 1. That column means the body is eligible. The
    INLINE option is what keeps the per-row call.

    The literal 20000 is intentional. A local variable would hide the value
    from the optimizer and could turn the seek into a scan, which would mix
    a cardinality problem into this scenario.

    Expected plan: Index Seek on IX_OrderItems_OrderId, plus the UDF.
    The plan stays serial. QueryPlan/@NonParallelPlanReason is set; this
    project has observed CouldNotGenerateValidParallelPlan, and other builds
    report TSQLUserDefinedFunctionsNotParallelizable. Read the attribute.
    Do not require one exact string.

    Measurement query: keep identical to benchmarks/RunBefore.sql scenario 04.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51027, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

IF OBJECT_ID(N'dbo.fn_LineAmountWithTax', N'FN') IS NULL
BEGIN
    THROW 51028, 'dbo.fn_LineAmountWithTax is missing. Run database/01_CreateTables.sql.', 1;
END;

IF EXISTS (
    SELECT 1
    FROM sys.sql_modules
    WHERE object_id = OBJECT_ID(N'dbo.fn_LineAmountWithTax')
      AND (inline_type IS NULL OR inline_type <> 0)
)
BEGIN
    THROW 51032, 'dbo.fn_LineAmountWithTax must be created WITH INLINE = OFF (sys.sql_modules.inline_type = 0). Re-run database/01_CreateTables.sql.', 1;
END;

SELECT
    OBJECT_SCHEMA_NAME(object_id) AS SchemaName,
    OBJECT_NAME(object_id) AS FunctionName,
    is_inlineable,
    inline_type
FROM sys.sql_modules
WHERE object_id = OBJECT_ID(N'dbo.fn_LineAmountWithTax');
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 04 BEFORE. inline_type in the previous result must be 0.';

SELECT
    oi.OrderItemId,
    oi.OrderId,
    dbo.fn_LineAmountWithTax(oi.Quantity, oi.UnitPrice) AS GrossAmount
FROM dbo.OrderItems AS oi
WHERE oi.OrderId <= 20000;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
