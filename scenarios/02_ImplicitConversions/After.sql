/*
    SQLServer-CPU-Optimization
    scenarios/02_ImplicitConversions/After.sql

    The parameter type now matches CustomerCode: varchar(16).
    The unique index can be seeked. The INCLUDE list covers CustomerName
    and Email, so the seek is not followed by a key lookup.

    Expected result: the same one row as Before.sql.
    Expected plan: Index Seek on UQ_Customers_CustomerCode, no CONVERT_IMPLICIT
    on CustomerCode.

    If the application always sends nvarchar and you cannot change it, the
    matching fix is to alter CustomerCode to nvarchar. Do that only when the
    column should actually store Unicode. This script does not alter the column,
    so Before.sql stays reproducible.

    Measurement query: keep identical to benchmarks/RunAfter.sql scenario 02.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51024, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 02 AFTER. Record execution CPU time, elapsed time, and logical reads.';

DECLARE @CustomerCode varchar(16) = 'C00010000';

SELECT
    c.CustomerId,
    c.CustomerCode,
    c.CustomerName,
    c.Email
FROM dbo.Customers AS c
WHERE c.CustomerCode = @CustomerCode;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
