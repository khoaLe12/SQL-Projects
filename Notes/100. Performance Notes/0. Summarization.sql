


-- TABLE DESIGN STRATEGIES
-- 1. Avoid over normalizing table since it make query to use JOIN operations.
-- 2. Normalize table only when it has many duplicate values, or consists of large object data/ row overflow data.
-- 3. Make clustered index as narrow as possible, and make it ever-increasing.




-- QUERY STRATEGIES
-- 1. Reduce the code paths (less wotk is performed and avoid contention points):
--	+ Parameterized queries: utilizing parameterized queries and stored procedure to reduce the cost of generating execution plans.
--	+ Fully Qualified Names: fully qualifying names of all objects helps remove the code paths required to resolve names



-- If a query is slow, go check
-- 1. Indexes
--	+ If the query is missing indexes
--	+ Check the state of indexes used by the query (fragmentation, page density) -> do reorganize/rebuild index
--		- Avoid over maintaining every index in the database since it highly costs resource
--	+ For columnstore index, reduce the number of INSERT/UPDATE/DELETE statement by doing bulk operations, columnstore index works at its best if almost 90% of operations performed are SELECT/AGGREGATE
--	+ Periodically reorganize/rebuild indexes
-- 2. Statistics
--	+ Check if statistic is up to date
-- 3. Check query plan
--	+ If Hash bailout (Grace hash join or Recursive hash join) occurs -> update statistics on the columns that are being joined.




-- If a SELECT statement invokes a scalar function
-- 1. Enable Scalar UDF inlining using option WITH INLINE = ON
--	+ This prevents the context switching between caller and invoked function



-- Use Table Partitions 
-- 1. To seperate old data and new data
--	+ Old data is rarely queried/modified
--	+ New data is queried all the time -> focus on improving query on new data



-- Apply Sharding and Replication
-- 1. Replication is a technique that replicates the primary database
--	+ The primary is responsible for handling all write/update requests
--	+ The replicated databases is used to process query requests which are distributed to all replications -> improved read performance
-- 2. Sharding is a technique that split database into smaller independent parts called shards
--	+ Each shard is stored in seperate database servers -> effectively reduce stress compared to a single centralized database
--	+ Require a good strategy to accurately identify shard key.



-- Recompiled stored procedures if the database undergoes significant changes to its data or structure
-- 1. This updates and optimized the procedure's query plan for those changes



-- Insert many values to a table
-- 1. Implement Bulk insert or use table-valued parameters on a procedure
--	+ Reduce roud trips to the server
-- 2. Table-value parameters are efficient for inserting less than 1,000 rows.
-- 3. Bulk insert is the best practice for inserting a very large amount of data rows (> 1,000 rows)
-- ============================================================================================================
-- TABLE-VALUED PARAMETER
-- Create table type
CREATE TYPE DepartmentTableType
	AS TABLE
	(
		Name Nvarchar(50),
		GroupName Nvarchar(50),
		ModifiedDate Datetime
	);
GO
-- Create an insert procedure to receive data for the table-valued parameter.
CREATE OR ALTER PROCEDURE dbo.asDepartmentIns 
	@TVP DepartmentTableType READONLY
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO HumanResources.Department (
		Name,
		GroupName,
		ModifiedDate
	)
	SELECT 
		Name,
		GroupName,
		ModifiedDate
	FROM @TVP

	SET NOCOUNT OFF;
END
GO
-- Demo
DECLARE @departmentTVP AS DepartmentTableType;
INSERT INTO @departmentTVP (Name, GroupName, ModifiedDate)
VALUES	('Name1', 'GroupName1', GETDATE()),
		('Name2', 'GroupName2', GETDATE()),
		('Name3', 'GroupName3', GETDATE())
EXEC dbo.asDepartmentIns @departmentTVP;
GO





-- Update many records to a table
-- Construct a dynamic query string to update in a single batch
UPDATE HumanResources.Department
SET Name = updateName,
	GroupName = updateGroupName
FROM (VALUES 
	('Name1', 'GroupName1', 1),
	('Name2', 'GroupName2', 2),
	('Name3', 'GroupName3', 3)
) AS vals (updateName, updateGroupName, id)
WHERE DepartmentID = id;
GO





-- Implement failover mechanism for a database to ensure its availability and reliability




-- Build a mechanism to coordinate connections between application and SQL Server, help to avoid creating and destroying too many connection





-- Troubleshoot the performance of full-text index population
-- 1. Review the full-text crawl logs; for default instance, logs are located at folder %ProgramFiles%\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\LOG
--	+ Crawl log naming scheme: SQLFT<DatabaseID\><FullTextCatalogID\>.LOG[<n\>]
--	+ Ex: SQLFT0000500008.2 -> DBID = 5, catalog ID = 8, 2 craw log files
-- 2. Check physical memory usage
--	+ Log shows fdhost.exe is being restarted often or that error code 8007008 is being returned -> one of these processes is running out of memory.
--	+ Get information about memory buffers used by a full-text crawl
SELECT 
	b.pool_id,
	b.row_count,
	b.bytes_used,
	b.percent_used,
	p.buffer_size,
	p.min_buffer_limit,
	p.max_buffer_limit,
	p.buffer_count
FROM sys.dm_fts_memory_buffers b
INNER JOIN sys.dm_fts_memory_pools p ON b.pool_id = p.pool_id





-- Performance counters
-- 1. SQL Server exposes performance counters through the DMV sys.dm_os_performance_counters, which can be directly queried with T-SQL.
-- 2. These counters provide real-time, cummulative statistics about SQL Server internals.
--	+ They're useful for monitoring and diagnosing specific aspects of performance (e.g., buffer cache, I/O, waits).
-- 3. Windows PerfMon can display these counters visually.
--	+ It can be configured to track SQL Server counters alongside OS counters for a holistic view.
-- 4. Sometimes counters don't appear in sys.dm_os_performance_counters, use the following PowerShell commands to reload them:
--	+ unlodctr MSSQL$SQLEXPRESS
--	+ lodctr "C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Binn\perf-SQLAgent$SQLEXPRESSsqlagtctr.ini"
-- Ex: Query the Page I/O latch waits counter:
SELECT
	object_name,
	counter_name,
	instance_name,
	cntr_value,
	cntr_type
FROM sys.dm_os_performance_counters
WHERE object_name = 'MSSQL$SQLEXPRESS:Wait Statistics' AND counter_name = 'Page IO latch waits'