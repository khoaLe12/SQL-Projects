
-- DIAGNOSE AND RESOLVE SPINLOCK CONTENTION ON SQL SERVER

-- 1. SPINLOCK:
--	+ Spinlocks are lightweight synchronization primitives that are used to protect access to data structure for a short time.
--	+ A thread waiting on spinlock will execute in a loop periodically trying to obtain it instead of immediately yielding.
--		- This helps reducing expensive operations that is context switching of a thread off the CPU.
--		- It is efficient if the requesting resources are held for a short duration.
--	+ After some period of time, the thread waiting on a spinlock will yield to other threads running on the same CPU to execute.
--		- The behavior is called backoff, it is performed after a constant time interval.
--		- It ensure spinlock doesn't excessively use CPU resources like spinning indefinitely.
--	+ Spinlock statistics are exposed by the sys.dm_os_spinlock_stats DMV with some particular interest:
--		- Collisions: the number of threads is blocked from accessing a resource protected by a spinlock.
--		- Spins: the number of loops executed by threads while waiting for a spinlock to become available.
--		- Backoffs: the number of backoffs events occurred.

-- 2. SPINLOCK CONTENTION:
--	+ Spinlock contention is one type of concurrency issue observed in real customer workloads on high scale systems.
--	+ Spinlock contention occurs when multiple threads repeatedly try to acquire the same spinlock.
--	+ Is is considererd problematic when contention introduces significant CPU overhead.
--		-> Causing all processing resources to spinning and trying to gain access to lock, instead of progressing the workload.
--	+ This issue is hard to diagnose, it requires many deep investigations into possible spinlock contentions that truthly detrimental to performance.
--	+ Some possible indicators of spinlock contention:
--		- A high number of spins and backoffs are observed for a particular spinlock type.
--		- Experienced heavy CPU utilization or spikes in CPU consumption
--		  Ex: high signal waits on SOS_SCHEDULER_YIELD from sys.dm_os_wait_stats DMV.
--		- The system is experiencing high concurrency.
--		- The CPU usage and spins are increased disproportionate to throughput.
--	+ Scenarios that are prone to this issue:
--		- Name resolution caused by a failure to fully qualify names of objects.
--		- Contention for lock hash buckets in the lock manager for workloads that frequently access the same lock.

-- 3. DIAGNOSE SPINLOCK CONTENTION:
--	+ Primary tools:
--		- Performance Monitor: look for high CPU conditions or divergence between between throughput and CPU consumption.
--		- Spinlock statistics: query the sys.dm_os_spinlock_stats DMV to look for a high number of spins and backoff events over periods of time.
--		- Wait statistics: starting with SQL Server 2025, query the sys.dm_os_wait_stats using SPINLOCK_EXT wait type.
--		- SQL Server extended events: used to track call stacks for spinlocks.
-- + Techniques:
--		- 