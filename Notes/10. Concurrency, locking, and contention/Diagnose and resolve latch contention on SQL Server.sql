
-- DIAGNOSE AND RESOLVE LATCH CONTENTION ON SQL SEREVR

-- 1. Latch:
--	+ Latches are lightweight synchronization primitives that are used to guarantee consistency of in-memory structures including: index, data pages, non-leaf pages, ...
--	+ Server uses buffer latches to protect pages in the buffer pool and I/O latches to protect pages not yet loaded into the buffer pool.
--	+ Whenever a worker thread write data to or read data from a page in the buffer pool, it must first be queued to acquire a buffer latch for the page, waiting for latch will accumulate wait time on requesting latch type.
--	+ There are various buffer latch types for accessing pages in the buffer pool including exclusive latch (PAGELATCH_EX), shared latch (PAGELATCH_SH), ...
--	+ To performed I/O disk operations, it required I/O latch; the type of latch depend on request, types including exclusive (PAGEIOLATCH_EX) or shared (PAGEIOLATCH_SH), etc.
--	+ I/O latches help to prevent another worker thread from loading the same page into the buffer pool with an incompatible latch.
--	+ Latches are also used to protect access to internal memory structures other than buffer pool pages, known as non-buffer latches.
 
-- 2. Latch vs Lock:
--	+ Buffer latches are held only for the duration of the physical operation on the page, locks are held for the duration of the logical transaction.
--	+ Latches are used to provide memory consistency, whereas locks are used to provide logical transactional consistency.
--	+ Performance cost of latch is low, allow for maximum concurrency and provide maximum performance.
--	+ Performance cost of lock is high as it must be held for the duration of the transaction.

-- 3. Latch modes and compatibility:
--	+ Latches are acquired in one of five different modes, which relate to level of access:
--		- KP: Keep latch. Ensures that the referenced structure can't be destroyed.
--		- SH: Shared latch. Required to read the referenced structure.
--		- UP: Update latch. Used to mark pages that are intended to be modified/written.
--		- EX: Exclusive latch. Blocks other threads from writing to or reading from the referenced structure.
--		- DT: Destroy latch. Must be acquired before destroying contents of referenced structure; Ex: used by lazy writer process to free up a clean page.
--	+ Latch modes have different levels of compatibility (Y indicates compatibility and N indicates incompatibility):
--			KP	SH	UP	EX	DT
--		KP	Y	Y	Y	Y	N
--		SH	Y	Y	Y	N	N
--		UP	Y	Y	N	N	N
--		EX	Y	N	N	N	N
--		DT	N	N	N	N	N
--	+ Multiple latches can be concurrently acquired on the same structure as long as the latch are compatible.
--	+ SQL Server enforces latch compatibility by requiring the incompatible latch requests to wait in a queue until a signal indicating the outstanding latch requests are completed.
--	+ A spinlock of type SOS_Task is used to protect the wait queue by enforcing serialized access to the queue, this spinlock is responsible for signaling threads in the queue.
--	+ The wait queue is processed on a first in, first out (FIFO) basis.

-- 4. latch wait types:
--	+ Cumulative wait information is tracked by SQL Server, stored in DMV sys.dm_os_wait_stats.
--	+ SQL Server employs three latch wait types as defined by wait_type in sys.dm_os_wait_stats.
--		- Buffer (BUF) latch: used to guarantee consistency of user objects, and protect data pages used by Server including: PFS, GAM, SGAM, and IAM pages; buffer latches are reported as type PAGELATCH_*
--		- Non-buffer (Non-BUF) latch: used to guarantee consistency of any in-memory structures other than buffer pool pages; non-buffer latches are reported as type LATCH_*
--		- IO latch: a subset of buffer latches that protect the structures when laoding into the buffer pool with an I/O operation; these latches are reported as type PAGEIOLATCH_*

-- 5. Latch contention:
--	+ Contention on page latches is the most common scenario encountered on multi-CPU systems (high busy-concurrency system).
--	+ Latch contention occurs when multiple threads concurrently attempt to acquire incompatible latches to the same in-memory structure.
--	+ It's considered problematic when the contention and wait time increased as enough to reduce resource (CPU) utilization, and hinders throughput.
--	+ Symptoms and causes:
--		- Observable in Performance Monitor with two counters (Transactions per second as throughput, average page latch wait time, number of CPU available), inspect the values over a period of time.
--		- As number of CPU increased, the overall throughtput has decreased and the page latch wait time has increased -> less CPU is used by Server cause concurrent threads are waiting for latches.
--		- This inverse relationship between throughput and page latch wait time is a common scenario that is easily diagnosed as latch contention.
--	+ Factors affecting latch contention:
--		- High number of logical CPUs used by SQL Server: Latch contention can occur on any multi-core system, commonly observed on system with 16+ CPU cores.
--		- Depth of B-tree, clustered and non-clustered index design, size and density of rows per page, and access patterns (read/write/delete activity) are factors that can contribute to excessive page latch contention.
--		- High degree of concurrency at the application level: occurs in conjunction with a high level of concurrent requests from the application tier.
--		- Layout of logical files uses by SQL Server databases: Logical file layout can affect the level of latch contention caused by allocation structures.
--		- I/O subsystem performance: Significant PAGEIOLATCH waits indicate SQL Server is waiting on the I/O subsystem.

-- 6. Indicators of latch contention:
-- The following measures of latch wait time are indicators that excessive latch contention is affecting application performance:
--	+ Average page latch wait time consistently increases with throughput:
--		- Query waiting task and calculate wait time over a time period using sys.dm_os_waiting_tasks DMV.
--		- Query buffer descriptors to determine objects causing latch contention using sys.dm_os_buffer_descriptors with know resource description.
--		- Measure average page latch wait time with the Performance Monitor counter Wait Statistics\Page Latch Waits\Average Wait Time.
--	+ Percentage of total wait time spent on latch wait types during peak load:
--		- If the average latch wait time as a percentage of overall wait time increases in line with application load, then latch contention might be affecting performance.
--		- Compare the values of performance counters of page latch waits and non-page latch waits with computer's resources like CPU, I/O, memory, and network throughput.
--	+ Throughput doesn't increase, and in some case decreases, as application load increases and the number of CPUs available to SQL Server increases.
--	+ CPU Utilization doesn't increase as application workload increases: If the CPU utilization on the system doesn't increases as concurrency driven by application throughput increases, this is an indicator that SQL Server is waiting on something and symptomatic of latch contention.
--	+ Suboptimal CPU utilization can be caused by other types of wait such as blocking on locks, I/O related waits or network-related issues -> required carefully analyze root cause.

-- 7. SQL Server latch contention scenarios:
-- Last page/trailing page insert contention:
--	+ Commonly occur on schema design that create an index containing a sequentially increasing leading key column such as identity or date column.
--		-> All insertion happend at the right-most edge of the B-tree -> cause EX latch contentions to be concentrated at a single page at high-concurrency traffic scenarios.
--	+ Design factors to consider: Use non-sequential column as leading column key column, or use hash value of key columns to distribute insertion across hash partition.
-- Latch contention on small tables with a non-clustered index and random inserts (queue table):
--	+ This scenario is typically seen when a SQL table is used as a temporary queue (like asynchronous messaging system).
--	+ EX and SH latch contention can occur under the following conditions:
--		- Insert, select, update, or delete operations occus under high concurrency.
--		- Row size is relatively small (leading to dense page).
--		- The number of roes in the table is relatively small, leading to a shallow B-tree.
--



-- Query the current wait buffer latches:
SELECT 
	wt.session_id,
	wt.wait_type,
	er.last_wait_type AS last_wait_type,
	wt.wait_duration_ms,
	wt.blocking_session_id,
	wt.blocking_exec_context_id,
	resource_description
FROM sys.dm_os_waiting_tasks AS wt
INNER JOIN sys.dm_exec_sessions AS es ON es.session_id = wt.session_id
INNER JOIN sys.dm_exec_requests AS er ON er.session_id = wt.session_id
WHERE es.is_user_process = 1
	AND wt.wait_type <> 'SLEEP_TASK'
ORDER BY wt.wait_duration_ms DESC