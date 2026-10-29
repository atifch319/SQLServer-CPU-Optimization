/*
    SQLServer-CPU-Optimization
    scenarios/02_ImplicitConversions/Before.sql

    CustomerCode is varchar(16). The variable is nvarchar(16).
    nvarchar outranks varchar, so SQL Server converts every CustomerCode
    to nvarchar and the unique index cannot be seeked.

    This is the usual ORM shape: SqlClient, EF, and most .NET string
    parameters are sent as nvarchar unless the type is specified.

    A local variable also hides the histogram (density is used). That is
    not what forces the scan. The scan remains if you replace the variable
    with the literal N'C00010000'. Do not "fix" the estimate with
    OPTION (RECOMPILE) and leave the nvarchar type in place.

    Expected result: one row, customer 10000.
    Expected plan: Index Scan on UQ_Customers_CustomerCode (or a clustered
    scan) with a CONVERT_IMPLICIT warning. Not an Index Seek.

    Measurement query: keep identical to benchmarks/RunBefore.sql scenario 02.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51023, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Scenario 02 BEFORE. One row comes back. The scan is the CPU and IO problem.';

DECLARE @CustomerCode nvarchar(16) = N'C00010000';

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
