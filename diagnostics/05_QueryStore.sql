/*
    SQLServer-CPU-Optimization
    diagnostics/05_QueryStore.sql

    Turns Query Store on for SqlServerCpuOptimization only, flushes it, and
    returns the statements with the highest average and total CPU.

    This changes a database setting. Query Store capture has its own CPU cost.
    For the numbers in benchmarks/ResultsTemplate.md, leave Query Store off
    (the default from 00_CreateDatabase.sql) for both the before run and the
    after run. Use this script when you want to find the expensive statements,
    not while you are collecting the template timings. If you would rather
    capture both sides, enable it before RunBefore.sql and leave it on through
    RunAfter.sql. Do not enable it between the two runs.

    QUERY_CAPTURE_MODE = ALL is intentional and is for this demo database.
    AUTO is the right production setting. ALL stores short, cheap statements
    (the scenario 02 seek is one of them) and uses more CPU and storage.

    Runtime CPU in Query Store is in microseconds. The result columns convert
    to milliseconds.

    Stats are aggregated by interval. INTERVAL_LENGTH_MINUTES is 1.
    sys.sp_query_store_flush_db forces the in-memory stats to the store so
    you do not have to wait for the flush interval.

    Permission: ALTER on the database to enable, VIEW DATABASE STATE to read.
    db_owner covers both. Query Store exists in every edition since SQL Server
    2016 SP1, including the editions that can run this project.
*/

USE SqlServerCpuOptimization;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51044, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

ALTER DATABASE SqlServerCpuOptimization
SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL,
    INTERVAL_LENGTH_MINUTES = 1,
    MAX_STORAGE_SIZE_MB = 200,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 1),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_PLANS_PER_QUERY = 200
);
GO

EXEC sys.sp_query_store_flush_db;
GO

SELECT
    actual_state_desc,
    desired_state_desc,
    readonly_reason,
    query_capture_mode_desc,
    interval_length_minutes,
    current_storage_size_mb,
    max_storage_size_mb
FROM sys.database_query_store_options;
GO

SELECT TOP (15)
    q.query_id,
    SUM(rs.count_executions) AS executions,
    CAST(
        SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0
        AS decimal(18, 2)
    ) AS avg_cpu_ms,
    CAST(SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS decimal(18, 2)) AS total_cpu_ms,
    CAST(
        SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0
        AS decimal(18, 2)
    ) AS avg_duration_ms,
    CAST(
        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0)
        AS decimal(18, 1)
    ) AS avg_logical_reads,
    LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), ' '), CHAR(10), ' '), 240) AS query_text
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_query_text AS qt
    ON qt.query_text_id = q.query_text_id
INNER JOIN sys.query_store_plan AS p
    ON p.query_id = q.query_id
INNER JOIN sys.query_store_runtime_stats AS rs
    ON rs.plan_id = p.plan_id
GROUP BY
    q.query_id,
    qt.query_sql_text
ORDER BY total_cpu_ms DESC;
GO

PRINT 'An empty CPU result means no statement has been flushed yet. Run a scenario, then run this script again.';
PRINT 'avg_cpu_ms is a weighted average across Query Store intervals. It will not match a single STATISTICS TIME number exactly, and it should rank the same problems.';
GO
