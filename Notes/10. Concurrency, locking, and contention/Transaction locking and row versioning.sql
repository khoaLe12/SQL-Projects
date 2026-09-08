
-- TRANSACTION LOCKING AND ROW VERSIONING

-- 1. Transactions:
--	+ A transaction is a logical unit of work consisting of one or more operations.
--	+ Transactions must satisfy ACID properties:
--		- Atomicity: all operations succeed or none are applied.
--		- Consistency: ensures data integrity and adherence to constraints.
--		- Isolation: concurrent transactions execute independently without interference.
--		- Durability: once committed, changes persist even after system failures.
--	+ Transaction types:
--		- Explicit: defined with BEGIN TRANSACTION / COMMIT / ROLLBACK.
--		- Implicit: engine automatically starts a new transaction after one finishes.
--		- Batch-scoped: applies to all statements in a batch.
--		- Distributed: span multiple databases/instances, coordinated by a transaction manager.
--	+ Transactions end with COMMIT or ROLLBACK. Errors trigger automatic rollback unless handled with TRY...CATCH.

-- 2. Concurrency Control:
--	+ SQL Server uses locking and isolation levels to manage concurrent transactions.
--	+ Without control, anomalies occur:
--		- Lost updates: one update overwrites another.
--		- Dirty reads: reading uncommitted changes.
--		- Nonrepeatable reads: same row returns different values in one transaction.
--		- Phantom reads: repeated queries return new rows inserted by other transactions.
--	+ Concurrency models:
--		- Pessimistic: locks resource to prevent conflicts; best for high contention.
--		- Optimistic: reads without locks, checks for conflicts at update; best for low contention.

-- 3. Transaction Isolation levels:
--	+ Define how transactions interact with each other's changes.
--	+ Control lock acquisition, duration, and behavior when encountering modified rows.
--	+ Lower levels → more concurrency, more anomalies. Higher levels → fewer anomalies, more blocking.
--	+ Levels:
--		- READ UNCOMMITTED: allow dirty reads.
--		- READ COMMITTED (default): prevents dirty reads; nonrepeatable and phantom reads possible.
--		- REPEATABLE READ: prevents nonrepeatable reads; phantom reads possible.
--		- SERIALIZABLE: highest isolation; prevents all anomalies.
--		- RSCI (Read Committed Snapshot): statement-level consistency via row versioning.
--		- SNAPSHOT: transaction-level consistency via row versioning.
--	+ Side effects by level:
--		- READ UNCOMMITTED: Dirty, Nonrepeatable, Phantom.
--		- READ COMMITTED: nonrepeatable, Phantom.
--		- REPEATABLE READ: Phantom.
--		- SNAPSHOT / SERIALIZABLE: none.
--	+ Set isolation level with: SET TRANSACTION ISOLATION LEVEL { READ UNCOMMITTED | READ COMMITTED | REPEATABLE READ | SNAPSHOT | SERIALIZABLE }

-- 4. Locking:
--	+ Locks synchronize concurrent access to resources.
--	+ If a requested lock conflicts, the transaction waits until it is released.
--	+ Lock duration depends on isolation level and optimized locking settings.
--	+ All locks are released at transaction end.
--	+ Trade-off: fine-grained locks increase concurrency but add overhead; coarse locks reduce overhead but block more.
--	+ Best practices: minimize lock count, use snapshot isolation cautiously, batch updates/deletes to avoid escalation, ...
--	  Example: to delete 5000 rows - DELETE TOP (500) in a loop until @@ROWCOUNT = 0.

-- 5. Lock Granularity & Hierarchy:
--	+ Used to identify the type of resource to be locked.
--	+ Lock levels:
--		- RID: single row in heap.
--		- KEY: single row in B-tree.
--		- PAGE: 8 KB page.
--		- EXTENT: 8 contiguous pages.
--		- HoBT: heap or B-tree.
--		- TABLE: entire table.
--		- FILE: database file.
--		- APPLICATION: user-defined resource.
--		- METADATA: schema metadata
--		- ALLOCATION_UNIT: allocation unit.
--		- DATABASE: entire database.
--		- XACT: transaction ID (optimized locking).
--	+ Trade-off:
--		- Small granularity → more locks, higher overhead, better concurrency.
--		- Large granularity → fewer locks, lower overhead, reduced concurrency.

-- 6. Lock Modes:
--	+ Define how resources can be accessed:
--		- Shared (S): read-only; compatible with other S locks.
--		- Update (U): specify the UPLOCK hint in SELECT statement; prevents deadlocks in SELECT→UPDATE scenarios; only 1 Update lock to be granted on the resource.
--		- Exclusive (X): for modifications; blocks all except READ operations with NOLOCK/READ UNCOMMITTED.
--		- Intent (IS, IX, SIX, IU, SIU, UIX): indicate intention to lock at finer granularity; helps effectively detect conflicts at higher granular level.
--		- Schema (Sch-M, Sch-S): protect schema changes or stability.
--		- Bulk Update (BU): used with TABLOCK during bulk insert.
--		- Key-range: protects ranges of rows being read in SERIALIZABLE isolation.

-- 7. Lock Compatibility:
--	+ Determines if multiple locks can coexist on the same resource.
--	+ If a requested new lock is not compatible with existing locks, the request must wait until all incompatible locks are released or a timeout occurs.
--	+ Example compatibility matrix (Y=yes, N=no):
--		 S   U   X   IS  IX  SIX
--	 S	 Y   Y   N   Y   N   N
--	 U   Y   N   N   Y   N   N
--	 X   N   N   N   N   N   N
--	IS   Y   Y   N   Y   Y   Y
--  IX   N   N   N   Y   Y   N
-- SIX   N   N   N   Y   N   N

-- 8. Lock Escalation:
--	+ Converts many fine-grained locks into fewer coarse locks.
--	+ Reduces overhead but lowers concurrency.
--	+ Escalation examples: change intent lock to correspond full lock (IX → X at table level), escalate lower granularity to higer one (page locks → table lock).
--	+ Each escalation event operates on all locks acquired at the current statement and all previous statements within the transaction.
--	+ Triggered only if when a statement acquires ≥ 5,000 locks on a single reference of a table.
--	+ Engine checks for escalation every 1,250 new locks.
--	+ If escalation fails due to conflicts, retries after each 1,250 locks.
--	+ Optimized locking reduces the number of locks and so escalation frequency.
--	+ Monitor escalation with lock_escalation extended event.




-- Query all existing locks
SELECT 
    tl.resource_type AS [Resource Type],
    tl.request_mode AS [Lock Mode],
    tl.request_status AS [Request Status],
    DB_NAME(tl.resource_database_id) AS [Database Name],
    OBJECT_NAME(p.[object_id]) AS [Entity Name],
    CASE tl.resource_type
        WHEN N'PAGE' THEN tl.resource_description
        ELSE NULL
    END AS [FileID:PageID],
    CASE tl.resource_type
        WHEN N'KEY' THEN tl.resource_description
        ELSE NULL
    END AS [Hash Key],
    tl.resource_associated_entity_id AS [Hobt Id],
    tl.lock_owner_address AS [Lock Owner Address],
    es.[session_id] AS [Session Id],
    tl.request_request_id AS [Request Id],
    es.login_name AS [Login],
    es.[host_name] AS [Host],
    es.[program_name] AS [Program Name],
    es.[status] AS [Session Status],
    es.cpu_time AS [CPU Time],
    es.memory_usage AS [Memory Usage],
    es.reads AS [Reads],
    es.writes AS [Writes]
FROM sys.dm_tran_locks tl
LEFT JOIN sys.dm_exec_sessions AS es ON tl.request_session_id = es.session_id
LEFT JOIN sys.partitions AS p ON p.hobt_id = tl.resource_associated_entity_id
WHERE request_type = 'LOCK' AND es.is_user_process = 1 AND es.session_id IN (57, 58) --AND tl.resource_associated_entity_id = 72057594049986560
ORDER BY 
    request_session_id,
    CASE tl.resource_type
        WHEN 'DATABASE' THEN 1
        WHEN 'OBJECT' THEN 2
        WHEN 'PAGE' THEN 3
        WHEN 'KEY' THEN 4
     END ASC
GO



-- Verify if there is lock contention
IF OBJECT_ID('tempdb..#contention') IS NOT NULL 
    DROP TABLE #contention
GO

CREATE TABLE #contention (lock1 Nvarchar(8), lock2 Nvarchar(8), is_contention Bit DEFAULT 0)

INSERT INTO #contention(lock1, lock2, is_contention)
VALUES ('S', 'S', 0),
        ('S', 'U', 0),
        ('S', 'X', 1),
        ('S', 'IS', 0),
        ('S', 'IX', 1),
        ('S', 'SIX', 1),
        ('S', 'SCH-S', 0),
        ('S', 'SCH-M', 1),
        ('S','RangeS-S',0),
        ('S','RangeS-U',0),
        ('S','RangeI-N',0),
        ('S','RangeX-X',1),
        ('U', 'SIX', 1),
        ('U', 'IX', 1),
        ('U', 'IS', 0),
        ('U', 'X', 1),
        ('U', 'U', 1),
        ('U', 'S', 0),
        ('U', 'SCH-S', 0),
        ('U', 'SCH-M', 1),
        ('U','RangeS-S',0),
        ('U','RangeS-U',1),
        ('U','RangeI-N',0),
        ('U','RangeX-X',1),
        ('X', 'SIX', 1),
        ('X', 'IX', 1),
        ('X', 'IS', 1),
        ('X', 'X', 1),
        ('X', 'U', 1),
        ('X', 'S', 1),
        ('X', 'SCH-S', 0),
        ('X', 'SCH-M', 1),
        ('X','RangeS-S',1),
        ('X','RangeS-U',1),
        ('X','RangeI-N',1),
        ('X','RangeX-X',1),
        ('IS', 'SIX', 0),
        ('IS', 'IX', 0),
        ('IS', 'IS', 0),
        ('IS', 'X', 1),
        ('IS', 'U', 0),
        ('IS', 'S', 0),
        ('IS', 'SCH-S', 0),
        ('IS', 'SCH-M', 1),
        ('IX', 'SIX', 1),
        ('IX', 'IX', 0),
        ('IX', 'IS', 0),
        ('IX', 'X', 1),
        ('IX', 'U', 1),
        ('IX', 'S', 1),
        ('IX', 'SCH-S', 0),
        ('IX', 'SCH-M', 1),
        ('SIX', 'SIX', 1),
        ('SIX', 'IX', 1),
        ('SIX', 'IS', 0),
        ('SIX', 'X', 1),
        ('SIX', 'U', 1),
        ('SIX', 'S', 1),
        ('SIX', 'SCH-S', 0),
        ('SIX', 'SCH-M', 1),
        ('SCH-S', 'S', 0),
        ('SCH-S', 'U', 0),
        ('SCH-S', 'X', 0),
        ('SCH-S', 'IS', 0),
        ('SCH-S', 'IX', 0),
        ('SCH-S', 'SIX', 0),
        ('SCH-S', 'SCH-S', 0),
        ('SCH-S', 'SCH-M', 1),
        ('SCH-M', 'S', 1),
        ('SCH-M', 'U', 1),
        ('SCH-M', 'X', 1),
        ('SCH-M', 'IS', 1),
        ('SCH-M', 'IX', 1),
        ('SCH-M', 'SIX', 1),
        ('SCH-M', 'SCH-S', 1),
        ('SCH-M', 'SCH-M', 1),
        ('RangeS-S','RangeS-S',0),
        ('RangeS-S','RangeS-U',0),
        ('RangeS-S','RangeI-N',0),
        ('RangeS-S','RangeX-X',1),
        ('RangeS-S','S',0),
        ('RangeS-S','U',0),
        ('RangeS-S','X',1),
        ('RangeS-U','RangeS-S',0),
        ('RangeS-U','RangeS-U',1),
        ('RangeS-U','RangeI-N',0),
        ('RangeS-U','RangeX-X',1),
        ('RangeS-U','S',0),
        ('RangeS-U','U',1),
        ('RangeS-U','X',1),
        ('RangeI-N','RangeS-S',0),
        ('RangeI-N','RangeS-U',0),
        ('RangeI-N','RangeI-N',0),
        ('RangeI-N','RangeX-X',1),
        ('RangeI-N','S',0),
        ('RangeI-N','U',0),
        ('RangeI-N','X',1),
        ('RangeX-X','RangeS-S',1),
        ('RangeX-X','RangeS-U',1),
        ('RangeX-X','RangeI-N',1),
        ('RangeX-X','RangeX-X',1),
        ('RangeX-X','S',1),
        ('RangeX-X','U',1),
        ('RangeX-X','X',1);

CREATE NONCLUSTERED INDEX Idx_contention_lock1_lock2_IsContention
ON #contention(lock1, lock2, is_contention)



IF OBJECT_ID('tempdb..#temp') IS NOT NULL 
    DROP TABLE #temp
GO

SELECT 
    tl.resource_type AS resource_type,
    tl.request_mode AS request_mode,
    tl.request_status AS request_status,
    DB_NAME(tl.resource_database_id) AS db_name,
    OBJECT_NAME(p.[object_id]) AS entity_name,
    CASE tl.resource_type
        WHEN N'PAGE' THEN tl.resource_description
        ELSE NULL
    END AS file_page,
    CASE tl.resource_type
        WHEN N'KEY' THEN tl.resource_description
        ELSE NULL
    END AS hash_key,
    resource_description,
    tl.resource_associated_entity_id AS resource_associated_entity_id,
    tl.lock_owner_address AS lock_owner_address,
    es.[session_id] AS session_id,
    tl.request_request_id AS request_request_id,
    es.login_name AS login_name,
    es.[host_name] AS host_name,
    es.[program_name] AS program_name,
    es.[status] AS status,
    es.cpu_time AS cpu_time,
    es.memory_usage AS memory_usage,
    es.reads AS reads,
    es.writes AS writes,
    ROW_NUMBER() OVER(ORDER BY request_session_id, 
        CASE tl.resource_type
            WHEN 'DATABASE' THEN 1
            WHEN 'OBJECT' THEN 2
            WHEN 'PAGE' THEN 3
            WHEN 'KEY' THEN 4
            END ASC) AS rn
INTO #temp
FROM sys.dm_tran_locks tl
LEFT JOIN sys.dm_exec_sessions AS es ON tl.request_session_id = es.session_id
LEFT JOIN sys.partitions AS p ON p.hobt_id = tl.resource_associated_entity_id
WHERE request_type = 'LOCK' AND es.is_user_process = 1 AND es.session_id IN (57, 58) --AND tl.resource_associated_entity_id = 72057594049986560

CREATE NONCLUSTERED INDEX Idx_temp_RN_DBName_EntityName_ResourceType_ResourceDescription_RequestMode 
ON #temp(rn, db_name, entity_name, resource_type, resource_description, request_mode)




IF OBJECT_ID('tempdb..#result') IS NOT NULL
    DROP TABLE #result
GO

CREATE TABLE #result (
    Id Int,
    [Resource Type] Nvarchar(60),
    [Lock Mode] Nvarchar(60),
    [Request Status] Nvarchar(60),
    [Database Name] Nvarchar(128),
    [Entity Name] Nvarchar(128),
    resource_description Nvarchar(256),
    [FileID:PageID] Nvarchar(256),
    [Hash Key] Nvarchar(256),
    [Hobt ID] bigint,
    [Lock Owner Address] varbinary(8),
    [Session ID] smallint,
    [Request ID] int,
    [Login] nvarchar(128),
    [Host] nvarchar(128),
    [Program Name] nvarchar(128),
    [Session Status] nvarchar(30),
    [CPU Time] int,
    [Memory Usage] int,
    [Reads] bigint,
    [Writes] bigint,
    [Conflict] Int NULL
)
GO

DECLARE @rn Int,
    @db_name Nvarchar(128),
    @entity_name Nvarchar(128),
    @resource_type Nvarchar(60),
    @lock_mode Nvarchar(60),
    @resource_description Nvarchar(256)
DECLARE csTemp CURSOR LOCAL FAST_FORWARD FOR SELECT rn, db_name, entity_name, resource_type, resource_description, request_mode FROM #temp

OPEN csTemp
FETCH NEXT FROM csTemp INTO @rn, @db_name, @entity_name, @resource_type, @resource_description, @lock_mode

WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO #result ([Id], [Resource Type], [Lock Mode], [Request Status], [Database Name], [Entity Name], resource_description, [FileID:PageID], [Hash Key], [Hobt ID], [Lock Owner Address], [Session ID], [Request ID], [Login], [Host], [Program Name], [Session Status], [CPU Time], [Memory Usage], [Reads], [Writes], [Conflict])
    SELECT
        rn AS [Id],
        resource_type AS [Resource Type],
        request_mode AS [Lock Mode],
        request_status AS [Request Status],
        db_name AS [Database Name],
        entity_name AS [Entity Name],
        resource_description,
        file_page AS [FileID:PageID],
        hash_key AS [Hash Key],
        resource_associated_entity_id AS [Hobt ID],
        lock_owner_address AS [Lock Owner Address],
        session_id AS [Session ID],
        request_request_id AS [Request ID],
        login_name AS [Login],
        host_name AS [Host],
        program_name AS [Program Name],
        status AS [Session Status],
        cpu_time AS [CPU Time],
        memory_usage AS [Memory Usage],
        reads AS [Reads],
        writes AS [Writes],
        @rn AS [Conflict]
    FROM #temp
    WHERE rn <> @rn 
        AND db_name = @db_name 
        AND entity_name = @entity_name 
        AND resource_type = @resource_type
        AND resource_description = @resource_description
        AND EXISTS (SELECT * FROM #contention WHERE lock1 = @lock_mode AND lock2 = request_mode AND is_contention = 1)

    --IF @@ROWCOUNT > 0
    --BEGIN
    --    INSERT INTO #result ([Id], [Resource Type], [Lock Mode], [Request Status], [Database Name], [Entity Name], [FileID:PageID], [Hash Key], [Hobt ID], [Lock Owner Address], [Session ID], [Request ID], [Login], [Host], [Program Name], [Session Status], [CPU Time], [Memory Usage], [Reads], [Writes], [Conflict])
    --    SELECT
    --        rn AS [Id],
    --        resource_type AS [Resource Type],
    --        request_mode AS [Lock Mode],
    --        request_status AS [Request Status],
    --        db_name AS [Database Name],
    --        entity_name AS [Entity Name],
    --        file_page AS [FileID:PageID],
    --        hash_key AS [Hash Key],
    --        resource_associated_entity_id AS [Hobt ID],
    --        lock_owner_address AS [Lock Owner Address],
    --        session_id AS [Session ID],
    --        request_request_id AS [Request ID],
    --        login_name AS [Login],
    --        host_name AS [Host],
    --        program_name AS [Program Name],
    --        status AS [Session Status],
    --        cpu_time AS [CPU Time],
    --        memory_usage AS [Memory Usage],
    --        reads AS [Reads],
    --        writes AS [Writes],
    --        NULL AS [Conflict]
    --    FROM #temp
    --    WHERE rn = @rn 
    --END

    FETCH NEXT FROM csTemp INTO @rn, @db_name, @entity_name, @resource_type, @resource_description, @lock_mode
END

CLOSE csTemp;
DEALLOCATE csTemp;



SELECT 
    [Id],
    [Conflict],
    [Resource Type],
    [Lock Mode],
    [Request Status],
    [Database Name],
    [Entity Name],
    [FileID:PageID],
    [Hash Key],
    [Hobt ID],
    [Lock Owner Address],
    [Session ID],
    [Request ID],
    [Login],
    [Host],
    [Program Name],
    [Session Status],
    [CPU Time],
    [Memory Usage],
    [Reads],
    [Writes]
FROM #result
ORDER BY [Database Name], [Entity Name], [Resource Type], resource_description, [Request Status]
GO
