/*
    SQLServer-CPU-Optimization
    diagnostics/02_ExecutionPlanInspection.sql

    Finds cached statements from this database and flags plan shapes used
    by the five scenarios. Run a scenario first. Plans for batches that have
    aged out of cache will not appear.

    SSMS operators to confirm by eye (Include Actual Execution Plan, Ctrl+M):

        Scenario 01 before   Index Scan or Clustered Index Scan
                              Residual predicate uses YEAR / MONTH
        Scenario 01 after    Index Seek on IX_Orders_OrderDate
        Scenario 02 before   CONVERT_IMPLICIT on CustomerCode, Index Scan
        Scenario 02 after    Index Seek on UQ_Customers_CustomerCode
        Scenario 03 before   Sort (Top N Sort) over the shipped orders
        Scenario 03 after    Ordered seek, no Sort
        Scenario 04 before   Serial plan, function fn_LineAmountWithTax
        Scenario 04 after    Compute Scalar, no UDF; often parallel
        Scenario 05 before   Aggregate of all orders, write to a temp table
        Scenario 05 after    Aggregate after a selective order predicate

    Estimated plans have no actual row counts and no QueryTimeStats.
    Actual plans do. Operator CPU and elapsed time (Actual Time Statistics)
    are present on actual plans in SQL Server 2016 and later. QueryTimeStats
    CpuTime and ElapsedTime in the plan XML are milliseconds.

    Permission: VIEW SERVER STATE, or VIEW SERVER PERFORMANCE STATE on
    SQL Server 2022 or later. db_owner alone is not sufficient for this DMV.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51041, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT TOP (30)
    qs.execution_count,
    CAST(qs.total_worker_time / 1000.0 AS decimal(18, 2)) AS total_cpu_ms,
    CAST(qs.total_elapsed_time / 1000.0 AS decimal(18, 2)) AS total_elapsed_ms,
    qs.total_logical_reads,
    CAST(qs.total_worker_time / 1000.0 / NULLIF(qs.execution_count, 0) AS decimal(18, 2)) AS avg_cpu_ms,
    SUBSTRING(
        st.text,
        (qs.statement_start_offset / 2) + 1,
        (
            (
                CASE qs.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset
                END - qs.statement_start_offset
            ) / 2
        ) + 1
    ) AS statement_text,
    CASE
        WHEN qp.query_plan.exist('//Convert[@Implicit="1"]') = 1 THEN 1
        ELSE 0
    END AS has_implicit_conversion,
    CASE
        WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Sort"]') = 1 THEN 1
        ELSE 0
    END AS has_sort,
    CASE
        WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Index Seek" or @PhysicalOp="Clustered Index Seek"]') = 1 THEN 1
        ELSE 0
    END AS has_seek,
    CASE
        WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Index Scan" or @PhysicalOp="Clustered Index Scan"]') = 1 THEN 1
        ELSE 0
    END AS has_scan,
    CASE
        WHEN qp.query_plan.exist('//Object[@FunctionName="[fn_LineAmountWithTax]"]') = 1 THEN 1
        ELSE 0
    END AS has_scalar_function
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
WHERE pa.attribute = N'dbid'
  AND pa.value = DB_ID()
  AND qp.query_plan IS NOT NULL
ORDER BY qs.total_worker_time DESC;
GO

PRINT 'total_cpu_ms is cumulative worker time for the cached statement, in milliseconds.';
PRINT 'has_implicit_conversion = 1 means some CONVERT_IMPLICIT exists. Date literals and decimal casts set it too. Scenario 02 is the case where the convert wraps CustomerCode and the operator is a scan.';
PRINT 'has_sort = 1 is the scenario 03 signature. has_scalar_function = 1 is scenario 04. An empty result means nothing from this database is in cache yet.';
GO
