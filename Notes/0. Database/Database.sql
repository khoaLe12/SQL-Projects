USE master;
GO




-- Create a database with specify data file location, log file location and some configurations
CREATE DATABASE Sales ON
(
	NAME = Sales_dat, -- this is primary file by default
	FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\saledat.mdf',
	SIZE = 10, -- MB type is used be default if MB or KB aren't specified
	MAXSIZE = 50,
	FILEGROWTH = 5
)
LOG ON
(
	NAME = Sales_log,
	FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\salelog.ldf',
	SIZE = 5 MB,
	MAXSIZE = 25 MB,
	FILEGROWTH = 5 MB
);
GO




-- Add file group to a database, data file, log file to the filegroup
ALTER DATABASE Sales
ADD FILEGROUP SalesFG1;
GO
;
ALTER DATABASE Sales
ADD FILE
(
	NAME = datafile1,
	FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\salesdat1.mdf',
	SIZE = 5MB,
	MAXSIZE = 100MB,
	FILEGROWTH = 5MB
),
(
	NAME = datafile2,
	FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\salesdat2.mdf',
	SIZE = 5MB,
	MAXSIZE = 100MB,
	FILEGROWTH = 5MB
)
TO FILEGROUP SalesFG1;
GO




-- View a list of databases
SELECT name, database_id, create_date
FROM sys.databases




-- View Database's properties / database-scoped configuration
SELECT DATABASEPROPERTYEX('Sales', 'IsAutoShrink'); -- get status of the AUTO_SHRINK database option
;
SELECT database_id, is_read_only, collation_name, compatibility_level
FROM sys.databases WHERE name = 'Sales'
;
SELECT configuration_id, name, value, value_for_secondary -- view several properties of the current database
FROM sys.database_scoped_configurations;




-- Change the properties of a database / database-scoped properties
SELECT name, snapshot_isolation_state,
	snapshot_isolation_state_desc AS description
FROM sys.databases
WHERE name = N'Sales'
;
ALTER DATABASE Sales
	SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
;
SELECT configuration_id, name, value, value_for_secondary
FROM sys.database_scoped_configurations
WHERE name = 'MAXDOP'
;
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 3
ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET MAXDOP = PRIMARY -- set value_for_secondary to null -> means inherit from primary





-- Display database size and index size
USE AdventureWorks2025
EXEC sp_spaceused




-- Display table size, allocation unit, number of rows, and the type of table
USE AdventureWorks2025
SELECT
	SCHEMA_NAME(t.schema_id) AS [schema_name],
	t.object_id,
	OBJECT_NAME(t.object_id) ObjectName,
	SUM(u.total_pages) * 8 Total_Reserved_kb,
	SUM(u.used_pages) * 8 Used_Space_kb,
	u.type_desc,
	MAX(p.rows) RowsCount
FROM 
	sys.allocation_units u
	JOIN sys.partitions p ON u.container_id = p.hobt_id
	JOIN sys.tables t ON p.object_id = t.object_id
GROUP BY 
	t.object_id,
	OBJECT_NAME(t.object_id),
	u.type_desc,
	t.schema_id
ORDER BY
	Used_Space_kb desc,
	ObjectName



-- Display data and log space information
USE AdventureWorks2025
SELECT file_id, name, type_desc, physical_name, size, max_size
FROM sys.database_files





-- Moving a database from one instance to another
USE Sales
GO
;
SELECT type_desc, name, physical_name
FROM sys.database_files
;
-- Detach a databse
EXEC sp_detach_db 'Sales', 'true'
;
-- Attach a database
USE [master]
GO
CREATE DATABASE New_Sales
ON (FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\saledat.mdf'),
	(FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\salelog.ldf'),
	(FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\salesdat1.mdf'),
	(FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\salesdat2.mdf'),
	(FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\salesdat3.mdf')
FOR ATTACH;
-- Review the files of attached database
USE [New_Sales] -- db Sales has been removed after detach
SELECT type_desc, name, physical_name
FROM sys.database_files





-- Verify the current state of a Database
SELECT name, state_desc FROM sys.databases
SELECT DATABASEPROPERTYEX('New_Sales', 'Status')





-- Resource database
-- Determine the version number of the Resource database
SELECT SERVERPROPERTY('ResourceVersion');

-- Determine the Resource database last updated
SELECT SERVERPROPERTY('ResourceLastUpdateDateTime');

-- Access SQL definitions of system objects
SELECT OBJECT_DEFINITION(OBJECT_ID('sys.objects'))
