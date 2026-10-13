
-- CHANGE DATA CAPTURE (CDC)
-- 1. It is a built-in feature to track data changes made by DML operation.

-- 2. The progress run asynchronously as background job by SQL Server Agent that reads transaction log to capture changes.

-- 3. Provides a more effective and comprehensive solution compared to alternative manually implemented solutions.
--	+ Reduce development time, useful for ETL operations, real-time reporting, and compliance auditing.
--	+ Improve performance of DML operation (since no additional actions are performed like triggers, additional table insertion, additional query to get original data ...).
--	+ Run asynchronously, reading changes from transaction log and does not interfere with the core application workload.

-- 4. Offer many useful features:
--	+ Built-in cleanup mechanism with retention-based cleanup policy that is performed automatically in the background
--	+ The timeline of changes is based transaction commit time, ensure the reliable of changes order
--	+ Provide 2 query functions to obtain change information from historical view of changes, or metadata from change data capture metedata tables.

-- 5. To enable/disable the Change Data Capture feature:
--	+ Firstly, enable the feature for a database using function sys.sp_cdc_enable_db.
--	+ Secondly, enable the fearure at the table level using sys.sp_cdc_enable_table.
--	+ Using functions sys.sp_cdc_disable_db and sys.sp_cdc_disable_table to disable the feature.

-- 6. Each source table that is enabled with change data capture is constructed that.
--	+ Each table can have maximum of 2 associated capture instances, which named by format <schema name_table name> of the tracked table.
--	+ The capture instance consists of a change table, metadata tables and up to 2 query functions which are created in the cdc schema.

-- 7. Metadata describes configurations of the instance 
--	+ Defined in tables cdc.change_tables, cdc.index_columns, and cdc.captured_columns.
--	+ Metadata can be retrieved using the stored procedure sys.sp_cdc_help_change_data_capture.
--	+ The configured values of capture job (used to scan log) are stored in msdb.dbo.cdc_jobs (maxtrans, maxscans, continuous, pollinginterval)
--		+ maxtrans: specify the maximum number of transactions that can be processed in a single scan cycle.
--		+ maxscans: specify the maximum number of scan cycles to be executed before performing return or waitfor action
--		+ continuos: 

-- 8. Change table records change informations
--	+ The table is named by appending _CT to the instance name know as <instance name_CT>.
--	+ A change table contains first 5 metadata columns, and identified captured columns from the source table.
--	+ The metadata columns identify and interpret the change activity
--		+ Column __$start_lsn stores the commit log sequence number (LSN) of the change.
--		+ Column __$seqval used to order the changes in the same transaction.
--		+ Column __$operation determine the operation performed (1=delete, 2=insert, 3=before update, 4=after update)
--		+ Column __$update_mask works as bit mask to identify which columns has changed in the operation (1=value is changed, 0=no change)
--	+ Each insert/delete operation corresponding to a single row within the change table, captured the data after insertion and data before deletion.
--	+ Each update operation populates 2 rows, one for original data and the other for updated data
--	+ To query changes from change table, use the built-in function name <fn_cdc_get_all_changes_instance name>.
--	+ To query net changes of instance (if supported), use the function <fn_cdc_get_net_changes_instance name>.
--	+ The netchanges merges changes and return the final contents for each modified row within validity interval

-- 9. The change data capture cleanup process periodically removes expired data (data that out of validity interval, by the default the last 3 days)
--	+ The log sequence number (LSN) and transaction commit time identify the validity of a data, the value is stored at cdc.lsn_time_mapping (columns start_lsn and tran_end_time)
--	+ The cleanup process use high water mark of commit time to computes a new low water mark constructs the validity interval (time between high and low water mark) for cleanup process
--	+ To retrieve high and low water mark of an instance, use functions sys.fn_cdc_get_max_lsn and sys.fn_cdc_get_min_lsn respecively

-- 10. There are two agent jobs for the feature are capture jobs and cleanup job
--	+ The capture jobs runs continously, processing a maximum of 1000 transacrions per scan cycle with a wait of 5 seconds between cycles.
--	+ The cleanup job runs daily at 2 A.M. It retains log entries for 3 days
--	+ To create or drop change data capture agent, use the procedure sys.sp_cdc_add_job and sys.sp_cdc_drop_job
--	+ To modify the default configuration of agents, use sys.sp_cdc_change_job; To view use sys.sp_cdc_help_jobs
--	+ To start or stop the capture job, use sys.sp_cdc_start_job and sys.sp_cdc_stop_job.
--	+ It is best practice to stop the job during the periods of peak demand

-- 11. Some important requirements and notes when enabling CDC for a source table
--	+ To enable net changes queries, the source table must be able to uniquely identify rows, via a primary key or explicitly specified with unique index
--	+ If the change capture uses an existing primary key, during the capture process, subsequent changes to the primary key aren't allowed.




USE AdventureWorks2025
GO


-- ENABLE/DISABLE DATABASE FOR CDC
EXEC sys.sp_cdc_enable_db;
EXEC sys.sp_cdc_disable_db;


-- CHECK CDC STATUS OF DATABASE
SELECT 
	CASE is_cdc_enabled 
		WHEN 1 THEN N'True'
		ELSE 'False'
	END AS [CDC Enabled]
FROM sys.databases 
WHERE database_id = DB_ID()


-- ENABLE/DISABLE CDC FOR A TABLE
EXEC sys.sp_cdc_enable_table
	@source_schema = N'Person',
	@source_name = N'BusinessEntity',
	@role_name = NULL, -- No gating role is defined, allow all access to the change data
	@capture_instance = NULL, -- Use default capture instance name <schemaname>_<sourcename>
	@supports_net_changes = 1, -- enable net changes queries, the source table must have primary key, or explicitly defined with alternative unique key
	@index_name = 'AK_BusinessEntity_rowguid', -- explicitly use defined unique key
	@captured_column_list = NULL, -- use NULL to include all source table's columns in the change table
	@filegroup_name = NULL -- use default filegroup for the capture instance
EXEC sys.sp_cdc_disable_table
	@source_schema = N'Person',
	@source_name = N'BusinessEntity',
	@capture_instance = N'Person_BusinessEntity'


-- CHECK CDC STATUS OF A TABLE
SELECT 
	CASE is_tracked_by_cdc
		WHEN 1 THEN N'True'
		ELSE N'False'
	END AS [CDC Enabled]
FROM sys.tables 
WHERE [object_id] = OBJECT_ID('Person.BusinessEntity', 'U')


-- VIEW CHANGE TABLE INFORMATIONS
SELECT * FROM cdc.change_tables WHERE [source_object_id] = OBJECT_ID('Person.BusinessEntity', 'U')


-- MONITORING THE CHANGE DATA CAPTURE PROCESS
-- The column empty_scan_count counts the number of scan processes that return empty result
-- The value of column latency of session_id 0 is the average latency of the most recent sessions
-- The throughput of the most recent sessions is calculated by divide the command_count by the value of duration
SELECT * FROM sys.dm_cdc_log_scan_sessions
SELECT latency, ISNULL(command_count/NULLIF(duration, 0), 0) AS [throughput] FROM sys.dm_cdc_log_scan_sessions WHERE session_id = 0


-- ============================================================================================================================================================================
-- QUERY CHANGE DATA
-- 1. Create LSN-based range to be searched: interval1 (@min_lsn, @max_lsn), interval2 (@increment_lsn, @decrement_lsn), interval3 (@begin_lsn, @end_lsn), interval4 (@previousdate, @currentdate)
-- 2. Query change data in a range using TVFs
-- 3. Identify changed column on update operation
BEGIN TRY
	DECLARE @min_lsn Binary(10) = sys.fn_cdc_get_min_lsn('Person_BusinessEntity');
	DECLARE @max_lsn Binary(10) = sys.fn_cdc_get_max_lsn();
	DECLARE @increment_lsn Binary(10) = sys.fn_cdc_increment_lsn(@min_lsn);
	DECLARE @decrement_lsn Binary(10) = sys.fn_cdc_decrement_lsn(@max_lsn);
	DECLARE @begin_lsn Binary(10) = sys.fn_cdc_map_time_to_lsn(N'smallest greater than or equal', DATEADD(MINUTE, 30, sys.fn_cdc_map_lsn_to_time(@min_lsn)));
	DECLARE @end_lsn Binary(10) = sys.fn_cdc_map_time_to_lsn(N'largest less than or equal', DATEADD(MINUTE, -30, sys.fn_cdc_map_lsn_to_time(@max_lsn)));
	DECLARE @previousdate Binary(10) = sys.fn_cdc_map_time_to_lsn(N'smallest greater than or equal', DATEADD(DAY, -1, GETDATE()));
	DECLARE @currentdate Binary(10) = sys.fn_cdc_map_time_to_lsn(N'largest less than or equal', GETDATE());

	DECLARE @col_businessEntityID Int = sys.fn_cdc_get_column_ordinal('Person_BusinessEntity', 'BusinessEntityID');
	DECLARE @col_rowguid Int = sys.fn_cdc_get_column_ordinal('Person_BusinessEntity', 'rowguid');
	DECLARE @col_modifiedDate Int = sys.fn_cdc_get_column_ordinal('Person_BusinessEntity', 'ModifiedDate');
	DECLARE @col_text Int = sys.fn_cdc_get_column_ordinal('Person_BusinessEntity', 'text');
	
	SELECT 
		-- Get all changes for compliance auditing
		sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS [commit time],
		__$start_lsn AS [LSN],
		__$seqval,
		CASE __$operation
			WHEN 1 THEN N'Delete'
			WHEN 2 THEN N'Insert'
			WHEN 3 THEN N'Before Update'
			WHEN 4 THEN N'After Update'
			ELSE ''
		END AS [operation],
		ASCII(SUBSTRING(__$update_mask,1,1)) AS [bit masked],
		__$update_mask AS [bit masked2],
		BusinessEntityID,
		rowguid,
		ModifiedDate,
		text,
		CASE sys.fn_cdc_is_bit_set(@col_businessEntityID, __$update_mask) 
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is BusinessEntityID updated],
		CASE sys.fn_cdc_is_bit_set(@col_rowguid, __$update_mask) 
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is rowguid updated],
		CASE sys.fn_cdc_is_bit_set(@col_modifiedDate, __$update_mask) 
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is ModifiedDate updated],
		CASE sys.fn_cdc_is_bit_set(@col_text, __$update_mask)
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is text updated]
	FROM cdc.fn_cdc_get_all_changes_Person_BusinessEntity(@min_lsn, @max_lsn, 'all update old'); -- row filter options: all, all update old

	-- Get net changes to perform ETL operations 
	SELECT
		sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS [commit time],
		CASE __$operation
			WHEN 1 THEN N'Delete'
			WHEN 2 THEN N'Insert'
			WHEN 3 THEN N'Before Update'
			WHEN 4 THEN N'After Update'
			WHEN 5 THEN N'Insert or Update'
			ELSE ''
		END AS [operation],
		__$update_mask AS [bit masked],
		BusinessEntityID,
		rowguid,
		ModifiedDate,
		text,
		CASE sys.fn_cdc_is_bit_set(@col_businessEntityID, __$update_mask) 
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is BusinessEntityID updated],
		CASE sys.fn_cdc_is_bit_set(@col_rowguid, __$update_mask) 
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is rowguid updated],
		CASE sys.fn_cdc_is_bit_set(@col_modifiedDate, __$update_mask) 
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is ModifiedDate updated],
		CASE sys.fn_cdc_is_bit_set(@col_text, __$update_mask)
			WHEN 1 THEN N'True'
			ELSE N'False'
		END AS [is text updated]
	FROM cdc.fn_cdc_get_net_changes_Person_BusinessEntity(@max_lsn, @max_lsn, 'all with mask')
	WHERE BusinessEntityID = 21879; -- row filter options: all, all with mask, all with merge

	-- Example of relational operator 'smallest greater than' and 'smallest greater than or equal'
	-- '2026-03-19 10:48:34.170' - min_lsn
	--'2026-03-19 10:48:34.407' - 'smallest greater than' min_lsn
	--'2026-03-19 10:48:34.170' - 'smallest greater than or equal' min_lsn
	SELECT sys.fn_cdc_map_lsn_to_time(sys.fn_cdc_get_min_lsn('Person_BusinessEntity'))
	SELECT sys.fn_cdc_map_lsn_to_time(sys.fn_cdc_map_time_to_lsn('smallest greater than', sys.fn_cdc_map_lsn_to_time(sys.fn_cdc_get_min_lsn('Person_BusinessEntity'))))
	SELECT sys.fn_cdc_map_lsn_to_time(sys.fn_cdc_map_time_to_lsn('smallest greater than or equal', sys.fn_cdc_map_lsn_to_time(sys.fn_cdc_get_min_lsn('Person_BusinessEntity'))))
END TRY
BEGIN CATCH
	-- The cause of error could be validity interval is not valid
	PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS Varchar(10))
	PRINT 'Error Messages: ' + ERROR_MESSAGE();
	THROW;
END CATCH
-- ============================================================================================================================================================================



-- JOIN CHANGE DATA WITH OTHER DATA FROM THE SAME TRANSACTION
-- Use cdc.lsn_time_mapping to map Change capture LSN with Transaction commit LSN
-- Query change data that associated with the Transaction commit LSN
DECLARE @from_lsn binary(10),
	@to_lsn binary(10),
	@database_transaction_begin_lsn numeric(25,0)
;
SET @from_lsn = sys.fn_cdc_get_min_lsn('Person_BusinessEntity')
SET @to_lsn = sys.fn_cdc_get_max_lsn()
SET @database_transaction_begin_lsn = (SELECT TOP 1 database_transaction_begin_lsn FROM sys.dm_tran_database_transactions)
;
SELECT q.*
FROM cdc.fn_cdc_get_all_changes_Person_BusinessEntity(@from_lsn, @to_lsn, N'all') q
INNER JOIN cdc.lsn_time_mapping m ON q.__$start_lsn = m.start_lsn
WHERE m.tran_begin_lsn = dbo.fn_convertnumericlsntobinary(@database_transaction_begin_lsn)

select * from cdc.fn_cdc_get_all_changes_Person_BusinessEntity(sys.fn_cdc_get_min_lsn('Person_BusinessEntity'), sys.fn_cdc_get_max_lsn(), N'all')
select * from cdc.lsn_time_mapping
select * FROM sys.dm_tran_database_transactions
