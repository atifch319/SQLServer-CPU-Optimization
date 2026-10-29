/*
    SQLServer-CPU-Optimization
    database/00_CreateDatabase.sql

    Drops and recreates the demo database SqlServerCpuOptimization.

    Intended platform: SQL Server 2022 or later, compatibility level 160.
    SQL Server 2019 (compatibility level 150) can run every script in this
    repository. Nothing here depends on 2022-only syntax. On SQL Server 2022
    or later the database is created at compatibility level 160. On SQL Server
    2019 it is created at 150, which is the highest level that instance supports.

    This script is destructive. It drops an existing database of this name,
    including any data you loaded into it. Do not point it at a shared instance
    where that database name might already be in use for something else.

    Permission: CREATE DATABASE (sysadmin or dbcreator).
    Next script: database/01_CreateTables.sql
*/

USE master;
GO

SET NOCOUNT ON;

IF CAST(SERVERPROPERTY(N'ProductMajorVersion') AS int) < 15
BEGIN
    THROW 51000, 'SQL Server 2019 or later is required. The project target is SQL Server 2022 (compatibility level 160).', 1;
END;
GO

IF DB_ID(N'SqlServerCpuOptimization') IS NOT NULL
BEGIN
    PRINT 'Dropping existing database SqlServerCpuOptimization.';
    ALTER DATABASE SqlServerCpuOptimization SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SqlServerCpuOptimization;
END;
GO

PRINT 'Creating database SqlServerCpuOptimization.';
CREATE DATABASE SqlServerCpuOptimization;
GO

USE SqlServerCpuOptimization;
GO

DECLARE @Major int = CAST(SERVERPROPERTY(N'ProductMajorVersion') AS int);
DECLARE @Compat int = CASE WHEN @Major >= 16 THEN 160 ELSE 150 END;
DECLARE @Sql nvarchar(max);

SET @Sql = N'ALTER DATABASE SqlServerCpuOptimization SET COMPATIBILITY_LEVEL = '
    + CAST(@Compat AS nvarchar(10)) + N';';
EXEC sys.sp_executesql @Sql;

ALTER DATABASE SqlServerCpuOptimization SET RECOVERY SIMPLE;
ALTER DATABASE SqlServerCpuOptimization SET AUTO_CLOSE OFF;
ALTER DATABASE SqlServerCpuOptimization SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE SqlServerCpuOptimization SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE SqlServerCpuOptimization SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE SqlServerCpuOptimization SET QUERY_STORE = OFF;

/*
    Pre-size the files so the load does not spend its time growing 8 MB data
    and log files. SIZE fails closed if the volume is short on space; the
    database is still usable, later inserts just autogrow.
*/
DECLARE @DataName sysname;
DECLARE @LogName sysname;
DECLARE @Resize nvarchar(max);

SELECT @DataName = name
FROM sys.database_files
WHERE type_desc = N'ROWS';

SELECT @LogName = name
FROM sys.database_files
WHERE type_desc = N'LOG';

SET @Resize = N'
ALTER DATABASE SqlServerCpuOptimization
    MODIFY FILE (NAME = ' + QUOTENAME(@DataName) + N', SIZE = 1024MB, FILEGROWTH = 256MB);
ALTER DATABASE SqlServerCpuOptimization
    MODIFY FILE (NAME = ' + QUOTENAME(@LogName) + N', SIZE = 1024MB, FILEGROWTH = 256MB);';

BEGIN TRY
    EXEC sys.sp_executesql @Resize;
    PRINT 'Data and log files set to 1024 MB with 256 MB growth.';
END TRY
BEGIN CATCH
    PRINT 'File pre-size was skipped: ' + ERROR_MESSAGE();
END CATCH;

PRINT @@VERSION;
PRINT CONCAT(
    'Ready. Compatibility level ',
    CAST(DATABASEPROPERTYEX(N'SqlServerCpuOptimization', N'CompatibilityLevel') AS nvarchar(10)),
    '. Query Store is off so timed runs are not paying for capture. ',
    'Next: database/01_CreateTables.sql.'
);
GO
