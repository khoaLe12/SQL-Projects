
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
--	+ Is is considererd problematic when contention introduces significant CPU overhead, which costs on spinning intead of doing useful work.
--	+ This issue is hard to diagnose, it required many deep investigation into possible spinlock contentions.
--	+ 

--	+ It can be observed on the system with high CPU consumption and large number of spins/backoffs .
--	+ 