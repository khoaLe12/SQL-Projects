

-- TEMPDB SYSTEM DATABASE
-- 1. Purpose:
--	Tempdb is a shared global resource used to store temporary data, including:
--		+ User objects: temporary tables and indexes, temporary stored procedures, large variables, table variables, results of table-valued functions, cursors.
--		+ Internal objects: work tables for spool operations, such as intermediate sort results for GROUP BY, ORDER BY, UNION queries; hash join/hash aggregation work files; and index build/maintenance operations (e.g., SORT_IN_TEMPDB).
--		+ Version stores: row versions generated during data modification when using row versioning-based isolation levels (e.g., READ COMMITTED SNAPSHOT or SNAPSHOT).
-- 2. File structure:
--	Tempdb consists of:
--		+ Primary data file: tempdev (tempdb.mdf).
--		+ Secondary data files: tempdb_mssql_#.ndf (temp1, temp2, etc.).
--		+ Log file: templog (templog.ldf).
--	By default, SQL Server creates tempdb with a single data file.
-- 3. File contents:
--	Each data file contains metadata pages and data pages.
--	Metadata tracks allocation and usage of space/pages.
-- 4. Concurrency:
--	Tempdb uses latch queues on allocation pages (PFS, GAM, SGAM) for each data file to serialize concurrent access.
--	Excessive contention on these latches leads to "tempdb allocation contention" or "page latch waits", observed as PAGELATCH_* waits.
--	These allocation pages are cached in memory, so the contention is in-memory synchronization, not disk I/O.
--	That's why the wait type is PAGELATCH_*, not PAGEIOLATCH_* (which indicates waiting for physical disk I/O).
-- 5. Detection:
--	Use DMVs such as sys.dm_os_waiting_tasks and sys.dm_os_wait_stats to identify waiting threads and reasons.
--	DBCC SQLPERF can reset wait statistics for monitoring.
-- 6. Mitigation strategies:
--		+ Add multiple files to increase the number of latch queues.
--			- Recommended: start with one file per logical processor up to 8, then add more only if necessary.
--			- Caution: too many files can add overhead.
--		+ Preallocate data files to their expected maximum size, or configure larger growth increments.
--			- Ensure all files have the same initial size and growth settings.
--		+ Enable "Instant File Initialization" to skip zeroing out new allocations.
--			- Caution: may expose residual data; use with care.
--		+ Enable "memory-optimized tempdb metadata" (SQL Server 2019+).
--			- Caution: increase memory usage.
--		+ Use table variables instead of temp table where appropriate (to avoid writing to metadata files), or optimze queries to reduce tempdb usage.
--		+ Place tempdb on seperate physical storage from other system databases to reduce I/O contention, preferably SSDs.





-- TEMPDB PRACTICE
-- 1. CHECK CURRENT SIZE AND GROWTH VALUE OF TEMPDB DATA FILES
SELECT 
	f.name AS [file name],
	f.type_desc AS [file type],
	ISNULL(RTRIM(CAST(f.size * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [size],
	CASE f.max_size
		WHEN -1 THEN 'Unlimited'
		ELSE ISNULL(RTRIM(CAST(f.max_size * 8.0 / 1024 AS CHAR)) + ' MB', '')
	END AS [max size],
	IIF(f.growth = 0, 'False', 'True') AS [is auto growth],
	CASE
		WHEN f.growth = 0 THEN '0 MB'
		WHEN f.growth > 0 AND f.is_percent_growth = 0 THEN ISNULL(RTRIM(CAST(f.growth * 8.0 / 1024 AS CHAR)) + ' MB', '')
		WHEN f.growth > 0 AND f.is_percent_growth = 1 THEN ISNULL(RTRIM(CAST(f.growth AS CHAR)) + '%', '')
	END AS [growth value],
	mf.physical_name AS [physical file path]
FROM tempdb.sys.database_files f
LEFT JOIN sys.master_files mf ON mf.file_id = f.file_id AND mf.database_id = DB_ID('tempdb');
GO


-- 2. MONIOR TEMPDB FILE SPACE USAGE
SELECT 
	ISNULL(RTRIM(CAST(SUM(total_page_count) * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [reserved space],
	ISNULL(RTRIM(CAST(SUM(allocated_extent_page_count) * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [allocated space],
	ISNULL(RTRIM(CAST(SUM(unallocated_extent_page_count) * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [unallocated space],
	ISNULL(RTRIM(CAST(SUM(version_store_reserved_page_count) * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [version store used],
	ISNULL(RTRIM(CAST(SUM(internal_object_reserved_page_count) * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [internal object used],
	ISNULL(RTRIM(CAST(SUM(user_object_reserved_page_count) * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [user object used],
	ISNULL(RTRIM(CAST(SUM(mixed_extent_page_count) * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [mixed extent used]
FROM tempdb.sys.dm_db_file_space_usage
GO;


-- 3. MONITOR TEMPDB FILE SPACE USAGE OF SESSIONS/REQUESTS (WITH SOME DETAILS OF REQUEST)
SELECT 
	u.session_id,
	ISNULL(RTRIM(CAST(u.user_objects_alloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [user objects allocation],
	ISNULL(RTRIM(CAST(u.user_objects_dealloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [user objects deallocation],
	ISNULL(RTRIM(CAST(u.internal_objects_alloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [internal objects allocation],
	ISNULL(RTRIM(CAST(u.internal_objects_dealloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [internal objects deallocation],
	ISNULL(RTRIM(CAST(u.user_objects_deferred_dealloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [user objects deferred deallocation],
	NULL AS [session infomration],
	s.host_name AS [host name],
	s.host_process_id AS [process id],
	CASE s.is_user_process 
		WHEN 0 THEN 'False'
		WHEN 1 THEN 'True'
		ELSE ''
	END AS [user process],
	s.login_time AS [login time],
	s.login_name AS [login name],
	s.original_login_name AS [origin name],
	s.status AS [status],
	ISNULL(FORMAT(s.last_request_start_time, 'dd-MM-yyyy HH:mm:ss'), 'Undefined') + ' - ' + ISNULL(FORMAT(s.last_request_end_time, 'dd-MM-yyyy HH:mm:ss'), 'Current') AS [last request],
	s.open_transaction_count AS [open transaction count]
FROM sys.dm_db_session_space_usage u
LEFT JOIN sys.dm_exec_sessions s ON s.session_id = u.session_id
GO
;
SELECT 
	u.session_id,
	u.request_id,
	ISNULL(RTRIM(CAST(u.user_objects_alloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [user objects allocation],
	ISNULL(RTRIM(CAST(u.user_objects_dealloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [user objects deallocation],
	ISNULL(RTRIM(CAST(u.internal_objects_alloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [internal objects allocation],
	ISNULL(RTRIM(CAST(u.internal_objects_dealloc_page_count * 8.0 / 1024 AS CHAR)) + ' MB', '') AS [internal objects deallocation],
	r.status AS [request status],
	(
		SELECT SUBSTRING(
			dest.text,
			(r.statement_start_offset / 2) + 1,  -- start index of sql text of current executing statement in a query
			((CASE r.statement_end_offset
				WHEN -1 THEN DATALENGTH(dest.text)
				ELSE r.statement_end_offset
			END - r.statement_start_offset) / 2) + 1
		)
		FOR XML PATH (''), TYPE
	) AS [sql text of a task in the request],
	(
		CASE 
			WHEN TRY_CAST(deqp.query_plan AS xml) IS NOT NULL 
				THEN TRY_CAST(deqp.query_plan AS xml)
			WHEN TRY_CAST(deqp.query_plan AS xml) IS NULL
				THEN (
					SELECT [processing-instruction(query_plan)] = 
						N'-- ' + NCHAR(13) + NCHAR(10) +
                        N'-- This is a huge query plan.' + NCHAR(13) + NCHAR(10) +
                        N'-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.' + NCHAR(13) + NCHAR(10) +
						NCHAR(13) + NCHAR(10) +
						REPLACE(deqp.query_plan, N'<RelOp', NCHAR(13) + NCHAR(10) + N'<RelOp') +
						NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
					FOR XML PATH(N''), TYPE
				)
		END
	) AS [query plan of a task in the request]
FROM sys.dm_db_task_space_usage u
LEFT JOIN sys.dm_exec_requests r ON r.session_id = u.session_id AND r.request_id = u.request_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS dest
OUTER APPLY sys.dm_exec_text_query_plan(r.plan_handle, r.statement_start_offset, r.statement_end_offset) AS deqp
GO


-- 4. DETECT TEMPDB ALLOCATION CONTENTIONS
SELECT
	ws.session_id AS [session id],
	ws.wait_type AS [wait type],
	ws.waiting_tasks_count AS [waiting tasks count],
	ISNULL(RTRIM(CAST(ws.wait_time_ms / 1000.0 AS CHAR)) + 's', '') AS [wait time],
	ISNULL(RTRIM(CAST(ws.max_wait_time_ms / 1000.0 AS CHAR)) + 's', '') AS [max wait time],
	ISNULL(RTRIM(CAST(ws.signal_wait_time_ms / 1000.0 AS CHAR)) + 's', '') AS [signal wait time]
FROM sys.dm_exec_session_wait_stats ws
WHERE wait_type LIKE 'PAGELATCH%'
GO
;
SELECT 
	-- Task info
	wt.session_id AS [session id],
	r.request_id AS [request id],
	r.status AS [request status],
	(
		SELECT SUBSTRING(
			dest.text,
			(r.statement_start_offset / 2) + 1,
			((CASE r.statement_end_offset
				WHEN -1 THEN DATALENGTH(dest.text)
				ELSE r.statement_end_offset
			END - r.statement_start_offset) / 2) + 1
		)
		FOR XML PATH (''), TYPE
	) AS [sql text], -- sql text of current current executed statement of a query
	ISNULL(r.parallel_worker_count, 0) AS [number of active parallel tasks],
	wt.waiting_task_address AS [task address],
	t.task_state AS [task status],
	wt.wait_type AS [wait type],
	ISNULL(RTRIM(CAST(wt.wait_duration_ms / 1000.0 AS CHAR)) + 's', '') AS [wait duration],
	wt.resource_description AS [resource description], -- tempdb file on which the request is waiting
	t.task_local_storage AS [task local storage],

	-- Blocking request infor
	br.session_id AS [blocking session],
	br.request_id AS [blocking request],
	br.status AS [blocking request status],
	(
		SELECT SUBSTRING(
			dest_br.text,
			(br.statement_start_offset / 2) + 1,  -- start index of sql text of current executing statement in a query
			((CASE br.statement_end_offset
				WHEN -1 THEN DATALENGTH(dest_br.text)
				ELSE br.statement_end_offset
			END - br.statement_start_offset) / 2) + 1
		)
		FOR XML PATH (''), TYPE
	) AS [blocking request - sql text],

	-- detail target resource page information of the current request
	dpi.database_id,
	dpi.pfs_status,
	dpi.gam_status,
	dpi.sgam_status,
	dpi.diff_status,
	dpi.ml_status,
	dpi.page_type_desc
FROM sys.dm_os_waiting_tasks wt
INNER JOIN sys.dm_exec_sessions S ON s.session_id = wt.session_id AND s.is_user_process = 1
LEFT JOIN sys.dm_os_tasks t ON t.task_address = wt.waiting_task_address
LEFT JOIN sys.dm_exec_requests r On r.request_id = t.request_id AND r.session_id = t.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS dest
CROSS APPLY sys.fn_PageResCracker(r.page_resource) AS prc
CROSS APPLY sys.dm_db_page_info(prc.db_id, prc.file_id, prc.page_id, 'DETAILED') AS dpi
LEFT JOIN sys.dm_exec_requests br ON br.session_id = r.blocking_session_id
OUTER APPLY sys.dm_exec_sql_text(br.sql_handle) AS dest_br
WHERE wt.wait_type LIKE 'PAGELATCH%'
ORDER BY wt.session_id, t.request_id
GO



-- 5. ADD MORE TEMPDB DATA FILES
ALTER DATABASE tempdb ADD FILE
(
	NAME = tempdev1, -- Logical name
	FILENAME = '/mnt/disks/sdb/tempdb/tempdb_mssql_1.mdf' -- Physical path for linux 
) TO FILEGROUP [PRIMARY]
GO
;
ALTER DATABASE tempdb ADD FILE
(
	NAME = tempdev1, -- Logical name
	FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQL2017\MSSQL\DATA\tempdb_mssql_1.ndf' -- Physical path for Windows
) TO FILEGROUP [PRIMARY]
GO
;
-- MODIFY PHYSICAL PATH
ALTER DATABASE tempdb
MODIFY FILE (NAME = tempdev, FILENAME = '/mnt/disks/mssql/tempdb/tempdb.mdf');
GO
ALTER DATABASE tempdb
MODIFY FILE (NAME = templog, FILENAME = '/mnt/disks/mssql/tempdb/templog.ldf');
GO
ALTER DATABASE tempdb
MODIFY FILE (NAME = tempdev2, FILENAME = '/mnt/disks/mssql/tempdb/tempdb2.ndf');
GO
;



-- 6. PREALLOCATE SPACE FOR ALL TEMPDB FILES WITH EXPECTED MAXIMUM SIZE
ALTER DATABASE tempdb
MODIFY FILE (NAME = tempdev, SIZE = 256 MB);
ALTER DATABASE tempdb
MODIFY FILE (NAME = temp1, SIZE = 256 MB);

-- DECREASE (SHRINK) THE FILE SIZE
USE tempdb;
GO
DBCC SHRINKFILE (tempdev, 64);
GO



-- CHECK CONFIGURATION
-- For SQL Server 2016 or later, keep the default behavior of tempdb
ALTER DATABASE tempdb SET MIXED_PAGE_ALLOCATION = OFF;
ALTER DATABASE YourDB SET AUTOGROW_ALL_FILES = ON;

-- For SQL Server 2014 or earlier, turn on TRACE FLAG 1117, 1118
DBCC TRACEON  (1117); DBCC TRACEON  (1118); -- This only turn on trace flags temporarily (search more for Enable permanently)



-- ENABLE "instant file initialization"
-- FOLLOW STEPS FROM THIS REFERENCE: https://learn.microsoft.com/en-us/sql/relational-databases/databases/database-instant-file-initialization?view=sql-server-ver17#enable-instant-file-initialization



-- ENABLE/DISABLE "Memory-optimized TempDB metadata" (only available on Enterprise, Developer, or Evaluation edition)
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = OFF;

-- VERIFY IF TEMPDB IS MEMORY-OPTIMIZED
SELECT SERVERPROPERTY('IsTempdbMetadataMemoryOptimized');

-- LIMIT MEMORY USAGE
CREATE RESOURCE POOL tempdb_resource_pool WITH (MAX_MEMORY_PERCENT = 20);
ALTER RESOURCE GOVERNOR RECONFIGURE;
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON (RESOURCE_POOL = 'tempdb_resource_pool')

-- REMOVE MEMORY USAGE LIMITATION
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;