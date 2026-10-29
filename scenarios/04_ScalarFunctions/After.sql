/*
    SQLServer-CPU-Optimization
    scenarios/04_ScalarFunctions/After.sql

    Replaces the scalar UDF with the same arithmetic as a relational expression.
    CROSS APPLY names the net line once so the tax math cannot drift from the
    function body. It is still a Compute Scalar, not a function call.

    The timed query is the SELECT below the first statistics block.
    Further down, dbo.InlineLineAmountWithTax is the reuse-friendly form
    (an inline table-valued function). It is not part of the benchmark.

    A parity check then compares the UDF with the expression for the same
    80,000 lines. Statistics are off for that check. MismatchedRows must be 0.
    The parity check is allowed to be slow: it calls the scalar function.

    Measurement query: keep identical to benchmarks/RunAfter.sql scenario 04.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51029, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 04 AFTER. Record execution CPU time, elapsed time, and logical reads.';

SELECT
    oi.OrderItemId,
    oi.OrderId,
    CAST(c.Net + CAST(ROUND(c.Net * 0.0800, 2) AS decimal(19, 4)) AS decimal(19, 4)) AS GrossAmount
FROM dbo.OrderItems AS oi
CROSS APPLY (
    SELECT CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4)) AS Net
) AS c
WHERE oi.OrderId <= 20000;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

CREATE OR ALTER FUNCTION dbo.InlineLineAmountWithTax
(
    @Quantity int,
    @UnitPrice decimal(19, 4)
)
RETURNS TABLE
AS
RETURN
    SELECT
        CAST(
            CAST(@Quantity * @UnitPrice AS decimal(19, 4))
            + CAST(ROUND(CAST(@Quantity * @UnitPrice AS decimal(19, 4)) * 0.0800, 2) AS decimal(19, 4))
            AS decimal(19, 4)
        ) AS GrossAmount;
GO

PRINT 'Parity check (not a timed run). MismatchedRows must be 0.';

SELECT
    SUM(CASE WHEN d.UdfAmount = d.ExprAmount THEN 1 ELSE 0 END) AS MatchingRows,
    SUM(CASE WHEN d.UdfAmount <> d.ExprAmount OR d.UdfAmount IS NULL OR d.ExprAmount IS NULL THEN 1 ELSE 0 END) AS MismatchedRows
FROM (
    SELECT
        dbo.fn_LineAmountWithTax(oi.Quantity, oi.UnitPrice) AS UdfAmount,
        CAST(c.Net + CAST(ROUND(c.Net * 0.0800, 2) AS decimal(19, 4)) AS decimal(19, 4)) AS ExprAmount
    FROM dbo.OrderItems AS oi
    CROSS APPLY (
        SELECT CAST(oi.Quantity * oi.UnitPrice AS decimal(19, 4)) AS Net
    ) AS c
    WHERE oi.OrderId <= 20000
) AS d;
GO
