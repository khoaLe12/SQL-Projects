
-- DEADLOCKS GUIDE

-- 1. Deadlock:
--	+ A deadlock occurs when two or more tasks permanently block each other's resource.
--	+ This condition is also called a cyclic dependency where both transactions have dependency on each other.
--	+ Deadlock causes transactions to wait forever, unless it is broken by an external process or handled by Database Engine Deadlock Monitor.
--	+ The Deadlock Monitor periodically checks for cyclic dependency, one transaction in deadlock is choosed as a victim and is terminated with an error.
--	+ Deadlocks are resolved almost immediately, whereas blocking can, in theory, persist indefinitely.
--	+ A deadlock can occur on any system with multiple threads, where competing shared resources concurrently.

-- 2. Resources that can deadlock:
--	+ Locks: Waiting to acquire locks on resources, such as objects, pages, rows, metadata, and applications can cause a deadlock.
--		- Ex: Transaction T1 has a shared lock on row R1, and is waiting to get an exclusive lock on row R2 (blocked by T2)
--			  Transaction T2 has a shared lock on row R2, and is waiting to get an exclusive lock on row R1 (blocked by T1)
--			  -> This results in a lock cycle in which T1 and T2 wait for each other to release the locked resources.
--	+ Worker threads: A queued task waiting for an available worker thread can cause a deadlock.
--		- Ex: Session S1 start a transaction and acquired a shared lock on row R1, then goes to sleep (release worker thread).
--			  Other active sessions run all available threads are trying to acquire exclusive locks on row R1 (blocked by S1).
--			  Session S1 continue its task but can acquire a worker thread -> it can't commit and release the lock on R1.
--	+ Memory: When concurrent requests are waiting for memory grants that can't be satisfied with the available memory, a deadlock can occur.
--		- Ex: Two concurrent queries Q1 and Q2 acquire 10MB and 20MB of memory.
--			  Both queries require additional 30MB but the total available memory is 20MB.
--			  -> Q1 and Q2 must wait for each other to release memory, which results in a deadlock.
--	+ Parallel query execution-related resources: Coordinator, producer, or comsumer threads associated with an exchange port might block each other causing a deadlock usually when including at least one other process that isn't a part of the parallel query.
--	+ Multiple Active Result Sets (MARS) resources: These resources are used to control interleaving of multiple active requests under MARS.

-- 3. Deadlock detection:
--	+ Deadlock detection is performed by a lock monitor thread that periodically initiates a search through all the tasks in a instance of the Database Engine.
--	+ The default interval is 5 seconds; the interval drops from 5 seconds to as low as 100 ms if deadlocks are detected; or add more 5 seconds after each search if no deadlock found.
--	+ If a deadlock is detected, the first few lock waits after a deadlock immediately trigger a deadlock search, rather than wait fot next deadlock detection interval.
--	+ In deadlock search, the system identifies the resource on which the thread is waiting, then finds the owners for that resource and recusively continues the process for those threads until it finds a cycle -> a cycle identified in this manner forms a deadlock.
--	+ The Database Engine ends a deadlock by choosing one of the threads as a deadlock victim; that thread is terminated, rolled back and returns error 1205 to the application.
--	+ By default, the Engine choose a transaction that is the least expensive as the deadlock victim.
--	  Or by specifying the priority of sessions in a deadlock situation using the SET DEADLOCK_PRIORITY statement, DEADLOCK_PRIORITY can be set to LOW, NORMAL, or HIGH, or can be set to any integer value between -10 and 10; the default value is NORMAL or 0.

-- 4.Deadlock information tools:
--	+ Deadlock extended event (xml_deadlock_report):
--		- Available in SQL Server 2012 (11.x) and later versions, prefer over deadlock graph event class in SQL Trace or SQL Profiler.
--		- The event is captured by the system_health event session by default -> don't need to configure a seperate event session for deadlock.
--		- The deadlock graph captured 3 distinct nodes: 
--			* victim-list: The deadlock victim process identifier.
--			* process-list: Information on all the processes involved in the deadlock.
--			* resource-list: Information about the resources involved in the deadlock.
--		- To view deadlock event in SSMS: choose an instance -> Management -> Extended Events -> Sessions -> system_health -> event_file -> View Target Data (check if any xml_deadlock_report events occurred).
--	+ Trace flag 1204 and trace flag 1222:
--		- Trace flag 1204 reports deadlock information formatted by each node involved in the deadlock.
--		- Trace flag 1222 formats deadlock information, first by processes and then by resources.
--		- It's possible to enable both trace flags to obtain two representations of the same deadlock event.
--	+ Profiler deadlock graph event:
--		- SQL Profiler has an event that presents a graphical depiction of the tasks and resources involved in a deadlock.
--		- The SQL Profiler and SQL Trace features are deprecated and replaced by Extended Events.

-- 5.Minimize deadlocks:
--	+ Minimizing deadlocks can increase transaction throughput and reduce system overhead:
--		- Fewer transactions are rolled back.
--		- Reduce resubmission of victim transaction by applications (if implement).
--	+ Following certain coding conventions can minimize the chance of generating deadlock:
--		- Access objects in the same order: using stored procedures for all data modifications can standardize the order of accessing objects.
--		- Avoid user interaction in transactions.
--		- Keep transactions short and in one batch: long-running transaction holds locks in a longer period -> cause blocking other activity and leading to possible deadlock situations.
--		  Keeping transactions in one batch minimizes network roundtrips, reducing possible delays in completing the transaction.
--	+ Avoid higher isolation levels: low isolation level holds shared locks for a shorter duration than a higher one, reducing lock contention.
--	+ Use a row versioning-based isolation level: no shared locks are acquired during read operations -> eliminate contention of shared lock.
--	+ Use bound connections: connections opened by the same application can cooperate with each other, prevent blocking each other since acquired locks of a transaction are also held by other transactions.

-- 6. Cause a deadlock:
--	+ Creating a deadlock scenario for demonstration purposes.
--	+ Ex (https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-deadlocks-guide?view=sql-server-ver17#cause-a-deadlock):
--		Open two query windows in SSMS to create two sessions S1 and S2.
--		S1 open a transaction and update on row R1 (but not yet commit).
--		S2 try to update on row R1 with the value read from R2 (but is blocked by S1).
--		S1 continue process by updating R2 (but is blocked by S2).
--		-> S1 and S2 now has a cycle dependency.


-- Query all deadlock events captured by the ring_buffer target of the system_health session (read data stored in memory).
SELECT 
	xdr.value('@timestamp', 'datetime') AS deadlock_time,
	xdr.query('.') AS event_data
FROM (
	SELECT CAST([target_data] AS XML) AS target_data
	FROM sys.dm_xe_session_targets AS xt
	INNER JOIN sys.dm_xe_sessions AS xs 
		ON xs.address = xt.event_session_address
	WHERE xs.name = N'system_health' 
		AND xt.target_name = N'ring_buffer'
) AS XML_Data
CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(xdr)
ORDER BY deadlock_time DESC;
GO


-- Query all deadlock events captured by the event_file target of the system_health session (read from .xel file stored in disk).
SELECT 
	event_data.timestamp_utc AS deadlock_time,
	CAST(event_data.event_data AS XML) AS event_data
FROM (
	SELECT xdr.value('@name', 'nvarchar(MAX)') AS event_file
	FROM (
		SELECT CAST([target_data] AS XML) AS target_data
		FROM sys.dm_xe_session_targets AS xt
		INNER JOIN sys.dm_xe_sessions AS xs 
			ON xs.address = xt.event_session_address
		WHERE xs.name = N'system_health' 
			AND xt.target_name = N'event_file'
	) AS XML_Data
	CROSS APPLY target_data.nodes('EventFileTarget/File') AS XEventFile(xdr)
) AS file_data
CROSS APPLY sys.fn_xe_file_target_read_file(file_data.event_file, null, null, null) AS event_data
WHERE event_data.[object_name] = N'xml_deadlock_report'
ORDER BY deadlock_time DESC;
GO









-- DEADLOCKS GUIDE

-- 1. Deadlock Basics:
--    + A deadlock occurs when two or more tasks block each other by holding resources the other needs.
--    + This creates a cyclic dependency: each transaction waits for the other to release its lock.
--    + Deadlocks cause transactions to wait indefinitely unless resolved.
--    + SQL Server’s Deadlock Monitor detects cycles and resolves them by terminating one transaction (the victim).
--    + Deadlocks are resolved quickly, unlike blocking which can persist indefinitely.
--    + Deadlocks can occur in any multi-threaded system with shared resources.

-- 2. Resources Prone to Deadlocks:
--    + Locks: common cause when transactions hold conflicting locks.
--      Example: T1 holds S lock on R1, requests X lock on R2; T2 holds S lock on R2, requests X lock on R1 → cycle.
--    + Worker Threads: if a session releases its worker while holding locks, and all threads are consumed, it may deadlock when trying to resume.
--    + Memory: queries waiting for memory grants can deadlock if total available memory is insufficient.
--    + Parallel Query Execution: exchange ports (producer/consumer threads) can block each other.
--    + MARS (Multiple Active Result Sets): interleaving multiple requests under MARS can cause deadlocks.

-- 3. Deadlock Detection:
--    + Performed by a lock monitor thread scanning tasks for cycles.
--    + Default interval: 5 seconds; reduced to 100 ms if deadlocks are frequent, increased if none are found.
--    + After a deadlock, subsequent lock waits trigger immediate detection.
--    + Detection process: identify waiting resource → find owners → recursively trace dependencies → detect cycle.
--    + Resolution: one transaction chosen as victim, rolled back, error 1205 returned.
--    + Victim selection: least costly transaction by default, or based on DEADLOCK_PRIORITY (LOW, NORMAL, HIGH, or -10 to 10).

-- 4. Deadlock Information Tools:
--    + Extended Events (xml_deadlock_report):
--      - Available from SQL Server 2012 onward; preferred over Profiler/Trace.
--      - Captured by default in system_health session.
--      - Deadlock graph includes victim-list, process-list, resource-list.
--      - View in SSMS: Management → Extended Events → Sessions → system_health → event_file → View Target Data.
--    + Trace Flags:
--      - 1204: formats deadlock info by nodes.
--      - 1222: formats info by processes then resources.
--      - Both can be enabled together for different perspectives.
--    + SQL Profiler Deadlock Graph:
--      - Provides graphical view of deadlocks.
--      - Deprecated; use Extended Events instead.

-- 5. Minimizing Deadlocks:
--    + Benefits: higher throughput, fewer rollbacks, reduced resubmissions.
--    + Techniques:
--      - Access objects in consistent order (use stored procedures).
--      - Avoid user interaction inside transactions.
--      - Keep transactions short and in a single batch (reduces lock duration and network delays).
--      - Use lower isolation levels when possible (shorter shared lock duration).
--      - Prefer row versioning isolation (RCSI, SNAPSHOT) to eliminate shared lock contention.
--      - Use bound connections so related sessions share locks.

-- 6. Demonstrating a Deadlock:
--    + Example scenario:
--      - Session S1: begins transaction, updates R1 (no commit).
--      - Session S2: attempts to update R1 using value from R2 (blocked by S1).
--      - S1 then tries to update R2 (blocked by S2).
--      - Result: cycle dependency → deadlock.

-- Queries to Capture Deadlocks:

-- From system_health ring_buffer (in-memory):
SELECT 
    xdr.value('@timestamp', 'datetime') AS deadlock_time,
    xdr.query('.') AS event_data
FROM (
    SELECT CAST([target_data] AS XML) AS target_data
    FROM sys.dm_xe_session_targets AS xt
    INNER JOIN sys.dm_xe_sessions AS xs 
        ON xs.address = xt.event_session_address
    WHERE xs.name = N'system_health' 
      AND xt.target_name = N'ring_buffer'
) AS XML_Data
CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(xdr)
ORDER BY deadlock_time DESC;
GO

-- From system_health event_file (.xel on disk):
SELECT 
    event_data.timestamp_utc AS deadlock_time,
    CAST(event_data.event_data AS XML) AS event_data
FROM (
    SELECT xdr.value('@name', 'nvarchar(MAX)') AS event_file
    FROM (
        SELECT CAST([target_data] AS XML) AS target_data
        FROM sys.dm_xe_session_targets AS xt
        INNER JOIN sys.dm_xe_sessions AS xs 
            ON xs.address = xt.event_session_address
        WHERE xs.name = N'system_health' 
          AND xt.target_name = N'event_file'
    ) AS XML_Data
    CROSS APPLY target_data.nodes('EventFileTarget/File') AS XEventFile(xdr)
) AS file_data
CROSS APPLY sys.fn_xe_file_target_read_file(file_data.event_file, null, null, null) AS event_data
WHERE event_data.[object_name] = N'xml_deadlock_report'
ORDER BY deadlock_time DESC;
GO
