/*
    SQLServer-CPU-Optimization
    diagnostics/01_StatisticsIOAndTime.sql

    How to read SET STATISTICS IO and SET STATISTICS TIME.
    The batch at the bottom is a small worked example (one customer seek).
    Compare scenarios with the scenario scripts, not with this file.

    Permission: permission to query dbo.Customers.
*/

USE SqlServerCpuOptimization;
GO

/*
    SET STATISTICS IO ON prints one line per table the statement touched.

        Table 'Customers'. Scan count 1, logical reads 3, physical reads 0,
        page server reads 0, read-ahead reads 0, page server read-ahead reads 0,
        lob logical reads 0, lob physical reads 0, lob page server reads 0,
        lob read-ahead reads 0, lob page server read-ahead reads 0.

    logical reads
        Pages read from the buffer pool, including pages just brought in from
        disk. This is the IO number to compare. It does not depend on whether
        the page was cached.

    physical reads
        Pages read from disk because they were not cached. The first run after
        a restart or a cold cache shows these. Elapsed time moves with them.
        CPU time mostly does not. Run the statement again and compare the
        second execution when you care about elapsed time.

    read-ahead reads
        Pages the engine prefetched. They are a subset of the IO story, not
        an extra bill on top of logical reads.

    scan count
        Not "how many times the query author scanned the table." A parallel
        scan increments this per thread. A nested loop seek increments it per
        execution of the inner side. Read it together with the plan.

    lob logical reads
        Off-row data. These tables do not store LOB columns, so this stays 0.

    SET STATISTICS TIME ON prints two blocks.

        SQL Server parse and compile time:
           CPU time = 2 ms, elapsed time = 2 ms.

        SQL Server Execution Times:
           CPU time = 16 ms, elapsed time = 11 ms.

    Record the Execution Times block.

    CPU time is worker time. A parallel query can report CPU time greater
    than elapsed time because workers run together. That is not a regression
    by itself. A drop in elapsed time with CPU time still high means the
    same CPU was spread across threads.

    Elapsed time includes waits: disk, locks, tempdb spills, and
    ASYNC_NETWORK_IO while the client consumes a large grid. For timing,
    prefer benchmarks/RunBefore.sql and benchmarks/RunAfter.sql. They
    aggregate on the server so the SSMS grid is not part of the measurement.
    Turn Include Actual Execution Plan off while timing. Capturing the plan
    changes elapsed time.

    Do not run DBCC DROPCLEANBUFFERS on a shared instance. It empties the
    buffer pool for every database. This project compares warm-cache CPU
    and logical reads.
*/

SET NOCOUNT ON;

IF DB_NAME() <> N'SqlServerCpuOptimization'
BEGIN
    THROW 51040, 'Run this script in the SqlServerCpuOptimization database.', 1;
END;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT 'Worked example: one seek by primary key. Logical reads should be a handful, not a scan of Customers.';

DECLARE @CustomerId int;

SELECT @CustomerId = c.CustomerId
FROM dbo.Customers AS c
WHERE c.CustomerId = 10000;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

PRINT CONCAT('Example returned CustomerId ', COALESCE(CAST(@CustomerId AS varchar(11)), 'NULL'), '.');
GO
