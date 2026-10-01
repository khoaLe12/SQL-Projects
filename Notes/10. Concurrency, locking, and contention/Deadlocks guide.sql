
-- DEADLOCKS GUIDE

-- 1. Deadlock Basics:
--	+ A deadlock ocuurs when two or more tasks block each other by holding resources the other needs.
--	+ This creates a cyclic dependency: each transaction waits for the other to release its lock.
--	+ Deadlocks cause transactions to wait indefinitely unless resolved.
--	+ SQL Server's Deadlock Monitor detects cycles and resolves them by terminating one transaction (the victim).
--	+ Deadlocks are resolved quickly, unlike blocking which can persist indefinitely.
--	+ Deadlocks can occur in any multi-threaded system with shared resources.

-- 2. Resources Prone to Deadlocks: 
--	+ Locks: common cause when transactons hold conflicting locks.
--	  Ex: T1 holds S lock on R1, requests X lock on r2; T2 holds S lock on R2, requests X lock on R1 → cycle.
--	+ Worker Threads: if a session releases its worker while holding locks, and other sessions run all available threads that wait for the locks to be released 
--	  → the session A continues its task but can't acquire a worker thread → the session can't commit and release the locks.
--	+ Memory: queries waiting for memory grants can deadlock if total available memory is insufficient.
--	  Ex: 2 concurrent queries acquire 10MB and 20MB of memory.
--		  Both queries require additional 30MB but the available memory is 10MB.
--		  → both queries must wait for each other to release memory, which results in deadlock.
--	+ Parallel Query Execution: exchange ports (producer/consumer threads) can block each other.
--	+ MARS (Multiple Active Result Sets): interleaving multiple requests under MARS can cause deadlocks.

-- 3. Deadlock Detection:
--	+ Performed by a lock monitor thread scanning tasks for cycles.
--	+ Default interval: 5 seconds; reduced to 100 ms if deadlocks are frequent, increased if none are found.
--	+ After a deadlock, subsequent lock waits trigger immediate detection.
--	+ Detection process: identify waiting resource → find owners → recursively trace dependencies → detect cycle.
--	+ Resolution: one transaction chosen as victim, rolled back, error 1205 returned.
--	+ Victim selection: least costly transaction by default, or based on DEADLOCK_PRIORITY (LOW, NORMAL, HIGH, or -10 to 10).

-- 4. Deadlock Information Tools:
--	+ Extended Events (xml_deadlock_report):
--		- Available from SQL Server 2012 onward; preferred over Profiler/Trace.
--		- Captured by default in system_health session.
--		- Deadlock graph includes victim-list, process-list, resource-list.
--		- View in SSMS: Management → Extended Events → Sessions → system_health → event_file → View Target Data (check if any xml_deadlock_report events occurred).
--	+ Trace Flags:
--		- 1204: formats deadlock info by nodes.
--		- 1222: formats info by processes then resources.
--		- Both can be enabled together for different perspectives.
--	+ SQL Profiler Deadlock Graph:
--		- Provides graphical view of deadlocks.
--		- Deprecated; use Extended Events instead.

-- 5. Minimizing Deadlocks:
--	+ Benefits: higher throughput, fewer rollbacks, reduced resubmissions.
--	+ Techniques: 
--		- Access objects in consistent order (use stored procedures).
--		- Avoid user interaction inside transactions.
--		- Keep transactions short and in a single batch (reduces lock duration and network delays).
--		- Use lower isolation levels when possible (shorter shared lock duration).
--		- Prefer row versioning isolation (RCSI, SNAPSHOT) to eliminate shared lock contention.
--		- Use bound connections so related sessions can share locks and cooperate with each other

-- 6. Demonstrating a Dealock:
--	+ Example scenario:
--		- Session S1: begins transaction, updates R1 (no commit).
--		- Session S2: attempt to update R2 using value from R1 (blocked by S1) → S2 has to wait until S1 commit.
--		- S1 the tries to update R2 (blocked by S2).
--		- Result: cycle dependency → deadlock.

-- Queries to Capture Deadlocks:

-- From system_health_ring_buffer (in-memory):
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