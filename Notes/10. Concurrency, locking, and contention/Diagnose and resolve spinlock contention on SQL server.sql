
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
--	+ Possible symptoms:
--		- Periodic spikes in CPU which pushed CPU utilization to nearly 100%.
--		- Increasing divergence between throughput and CPU consumptions.
--		- A large number of spins occuring during the interval of high CPU usage.
--	+ Troubleshooting steps:
--		- Query sys.dm_os_spinlock_stats to determine which spinlock type experiencing the most contention.
--		- Create a SQL Server Extended Event to trace the backoff events for the most interest of spinlock type.
--		- Download and attach debug symbol file (sqlservr.pdb) for the appropriate version of SQL Server (helps converting XE result into readable format).
--		- Analyze the call stacks in the output, measure the backoff events, and identify code paths where the contention lies.
--		- Example: the call stack with the highest slot bucket count contains 2 code paths: "CMEDCatalogOwner::GetProxyOwnerBySID", "CMEDProxyDatabase::GetOwnerBySID"
--			-> these code paths perform security-related checks -> for demonstration, run the query with sysadmin priviledges could reduce spinlock contention.

-- 4. Resolve spinlock contention:
--	+ Fully Qualified Names: 
--		- Removing the need for SQL Server to execute code paths that are required to resolve names.
--	+ Parameterized Queries: 
--		- Utilizing parameterized and stored procedure calls.
--		- It reduces the work needed to generate execution plans.
--	+ Optimistic Concurrency Control or Optimized Locking:
--		- Preventing LOCK_HASH contention which is incurred by multiple concurrent threads access the same lock structure/hash bucket.





-- Ensure the sqlservr.pdb is in the same directory as the sqlservr.exe
-- Enable this trace flag to turn on symbol resolution
DBCC TRACEON(3656, -1);



-- Query the spinlock stats to find the most interest spinlock type
SELECT
	name,
	collisions,
	spins,
	spins_per_collision,
	sleep_time,
	backoffs
FROM sys.dm_os_spinlock_stats
ORDER BY spins DESC



-- Find the type value of a spinlock type
-- Ex: LOCK_HASH - 199, SOS_CACHESTORE - 23
SELECT 
	map_value, 
	map_key, 
	name
FROM sys.dm_xe_map_values
WHERE map_value IN ('SOS_CACHESTORE', 'LOCK_HASH', 'MUTEX')



-- Create the event session that will capture the callstacks to a bucketizer
IF NOT EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE name = 'spin_lock_backoff')
BEGIN
	CREATE EVENT SESSION spin_lock_backoff ON SERVER
	ADD EVENT sqlos.spinlock_backoff (
		ACTION(package0.callstack) WHERE 
			type = 199 -- LOCK_HASH
			OR TYPE = 23 -- SOS_CACHESTORE
	)
	ADD TARGET package0.asynchronous_bucketizer (
		SET filtering_event_name = 'sqlos.spinlock_backoff',
		source_type = 1,
		source = 'package0.callstack'
	)
	WITH (
		MAX_MEMORY = 50 MB,
		MEMORY_PARTITION_MODE = PER_NODE
	);
END



-- Run the session in 1 minute to measure the contention
ALTER EVENT SESSION spin_lock_backoff ON SERVER STATE = START;
WAITFOR DELAY '00:01:00'
ALTER EVENT SESSION spin_lock_backoff ON SERVER STATE = STOP;



-- Get the callstacks from the bucketizer target
SELECT
	event_session_address,
	target_name,
	execution_count,
	CAST(target_data AS XML)
FROM sys.dm_xe_session_targets xst
INNER JOIN sys.dm_xe_sessions xs ON xst.event_session_address = xs.address
WHERE xs.name = 'spin_lock_backoff';



-- Clean up the session
DROP EVENT SESSION spin_lock_backoff ON SERVER;



-- Example of a backoff output
SELECT CAST(
	N'
	<Root>
		<BucketizerTarget truncated="0" buckets="256"/>

		<Slot count="35668" trunc="0">
		  <value>
			  XeSosPkg::spinlock_backoff::Publish
			  SpinlockBase::Sleep
			  SpinlockBase::Backoff
			  Spinlock&lt;144,1,0&gt;::SpinToAcquireOptimistic
			  SOS_CacheStore::GetUserData
			  OpenSystemTableRowset
			  CMEDScanBase::Rowset
			  CMEDScan::StartSearch
			  CMEDCatalogOwner::GetOwnerAliasIdFromSid
			  CMEDCatalogOwner::LookupPrimaryIdInCatalog CMEDCacheEntryFactory::GetProxiedCacheEntryByAltKey
			  CMEDCatalogOwner::GetProxyOwnerBySID
			  CMEDProxyDatabase::GetOwnerBySID
			  ISECTmpEntryStore::Get
			  ISECTmpEntryStore::Get
			  NTGroupInfo::''vector deleting destructor''
			</value>
		</Slot>

		<Slot count="752" trunc="0">
			<value>
				XeSosPkg::spinlock_backoff::Publish
				SpinlockBase::Sleep
				SpinlockBase::Backoff
				Spinlock&lt;144,1,0&gt;::SpinToAcquireOptimistic
				SOS_CacheStore::GetUserData
				OpenSystemTableRowset
				CMEDScanBase::Rowset
				CMEDScan::StartSearch
				CMEDCatalogOwner::GetOwnerAliasIdFromSid CMEDCatalogOwner::LookupPrimaryIdInCatalog CMEDCacheEntryFactory::GetProxiedCacheEntryByAltKey             CMEDCatalogOwner::GetProxyOwnerBySID
				CMEDProxyDatabase::GetOwnerBySID
				ISECTmpEntryStore::Get
				ISECTmpEntryStore::Get
				ISECTmpEntryStore::Get
			</value>
		  </Slot>
	  </Root>' 
	AS XML
)
