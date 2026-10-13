
-- THREAD AND TASK ARCHITECTURE

-- 1. Request:
--	+ A request is the logical representation of a query or batch.
--	+ Each request can be assigned to:
--		- A single task (serial execution).
--			* Serial requests have only one active task at a time
--		- Multiple tasks (parallel execution).
--			* Parallel requests have one parent task and multiple child tasks.
--			* The parent coordinates child tasks and execute serial portions of the plan.

-- 2. Task:
--	+ A task is a unit of work containing instructions to execute.
--	+ It tracks the request's state and accumulative waits.
--	+ DMV: sys.dm_os_tasks shows task state and wait times.
--	+ A task requires a worker thread to run on a CPU.
--	+ Task states:
--		- PENDING: waiting for a worker thread.
--		- RUNNABLE: ready, waiting for CPU quantum.
--		- RUNNING: executing on a scheduler.
--		- SUSPENDED: has a worker, waiting on resources/events.
--		- DONE: completed.
--		- SPINLOOP: stuck in a spinlock.

-- 3. Workers / Worker Threads:
--	+ A worker thread is SQL Server's logical representation of an OS thread.
--	+ Managed by the SQL Server scheduler (SOS scheduler).
--	+ MAXDOP controls maximum worker threads for parallel requests.
--	+ DMV: sys.dm_os_workers shows worker states.
--	+ Worker states:
--		- INIT: initializing.
--		- RUNNING: executing (preemptive or non-preemptive).
--		- RUNNABLE: ready to run.
--		- SUSPENDED: waiting for an event signal.

-- 4. Schedulers:
--	+ SQL Server uses SOS scheduler to manage workers.
--	+ Each scheduler maps to a CPU.
--	+ Cooperative (non-preemptive) scheduling:
--		- Threads get a quantum (~4 ms).
--		- Must yield after quantum or when its task is finished.
--		- Maximizes CPU access and reduces blocking on resources (I/O, remote calls, etc.,).
--	+ Threads are distributed across CPUs in round-robin fashion.

-- 5. Best Practices (servers >64 CPUs):
--	+ Use ALTER SERVER CONFIGURATION with SET PROCESS AFFINITY to bind processors.
--	+ Preallocate log file space to avoid auto-growth.
--	+ Configure MAXDOP for index operations.
--	+ Set maximum worker threads (starting point: ~7 x CPU count).
--	+ Avoid SQL Trace/Profiler in production.
--	+ Configure tempdb with multiple data files (generally one per CPU core).

-- 6. How SQL Server Uses Threads:
--	+ Each SSMS query window = seperate session.
--	+ Each ADO.NET SqlConnection  = seperate session.
--	+ A session can have multiple requests (seperated by GO keyword).
--	+ A request (batch) may contain multiple queries.
--	+ Queries may spawn multiple tasks/threads if parallel execution is chosen.
--		- Each batch has a sql_handle which refer to its sql/statement text, and query_hash generated from that text.
--		- For each batch, its plans are compiled or reused from cache, identified by plan_handle and query_plan_hash.




SELECT
	s.session_id,
	s.database_id,
	s.host_name,
	s.status AS [session status],
	r.status AS [request status],
	r.wait_type AS [wait type],
	r.last_wait_type AS [last wait type],
	r.wait_time AS [wait time],
	r.wait_resource AS [wait resource],
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
	) AS [request sql text],
	deqp.query_plan AS [request plan],
	deqs.query_hash AS [query identifier],
	deqs.query_plan_hash AS [plan identifier],
	deqs.statement_sql_handle,

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
	) AS [blocking request - sql text]
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
LEFT JOIN sys.dm_exec_query_stats deqs ON deqs.plan_handle = r.plan_handle AND deqs.sql_handle = r.sql_handle
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS dest
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS deqp
LEFT JOIN sys.dm_exec_requests br ON br.session_id = r.blocking_session_id
OUTER APPLY sys.dm_exec_sql_text(br.sql_handle) AS dest_br
--WHERE s.session_id = @@SPID
WHERE is_user_process = 1
GO

select * from sys.dm_exec_query_stats

select * from sys.dm_exec_sql_text(0x020000004C4B980D6635C20E5125F4C29EA2B786F56D8A900000000000000000000000000000000000000000)