
-- DIAGNOSE AND RESOLVE SPINLOCK CONTENTION IN SQL SERVER

-- 1. OVERVIEW
--	+ Spinlocks are lightweight synchronization primitives used to protect very short-duration access to internal SQL Server memory structures.
--	+ Common examples of structures protected by spinlocks include:
--		- Buffer hash tables
--		- Lock manager hash tables
--		- Plan cache structures
--		- Memory management structures
--		- Scheduler-related structures
--	+ A worker attempting to acquire a spinlock does not immediately yield the CPU when the spinlock is unvailable.
--	+ Instead, it repeatedly retries acquisition in a tight loop (spinning).
--	+ Benefits:
--		- Avoids expensive context switches.
--		- Very efficient when ownership duration is extremely short.
--	+ If a worker fails to acquire the spinlock after sufficient spin attempts, SQL Server performs a backoff operation:
--		- The worker yields execution
--		- Other worker may run
--		- The worker later retries acquisition
--	+ Backoff prevents workers from consuming CPU indefinitely.

-- 2. SPINLOCK STATISTICS
--	+ SQL Server exposes spinlock statistics throgh: sys.dm_os_spinlock_stats DMV
--	+ Important columns:
--		- collisions: number of times a worker thread attempted to acquired a spinlock but found it already owned by another worker (count after each failed acquisition).
--		- spins: number of spin attempts performed while waiting.
--		- spins_per_collision: average amount of spinning required after a collision.
--		- backoffs: number of times a worker gave up the spinning and yielded.
--		- sleep_time: total time spent backing off.
--	+ Important:
--		- High spin counts alone do not indicate a problem.
--		- Spin counts are cumulative since SQL Server startup and can naturally become very large on busy systems.
--		- Backoffs are usually a more important indicator of contention because
--		  they represent situations where spinning was unable to acquire the resource.

-- 3. SPINLOCK CONTENTION:
--	+ Spinlock contention occurs when multiple workers repeatedly attempt to acquire the same spinlock.
--	+ Excessive spinlock contention can cause:
--		- High CPU utilization
--		- Reduced throughput
--		- Poor scalability
--		- CPU resources spent spinning instead of performing useful work.
--	+ Unlike latch contention:
--		- Latch contention often appears as waiting.
--		- Spinlock contention often appears as CPU consumption.
--	+ This makes spinlock contention considerably more difficult to diagnose.

-- 4. INDICATORS OF SPINLOCK CONTENTION
--	+ Potential symptoms include:
--		- Sustained CPU utilization near 100%.
--		- Throughput does not increase proportionally with CPU consumption.
--		- Rapid growth of spins or backoffs for a particular spinlock type.
--		- High-concurrency workload.
--		- CPU spikes that coincide with increases in spinlock activity.
--	+ Important:
--		- Spinlock contention cannot be diagnosed from spin counts alone.
--		- Focus on scenarios where:
--			* Backoffs increase significantly.
--			* CPU consumption increases.
--			* Throughput remains flat or decreases.

-- 5. COMMON SPINLOCK CONTENTION SCENARIOS
-- A. NAME RESOLUTION CONTENTION
--	+ Common when object names are not fully qualified.
--	+ Example: (SELECT * FROM Orders) Instead of (SELECT * FROM dbo.Orders)
--	+ SQL Server must perform additional metadata lookups, which may contribute to contention on internal cache structures.
-- B. LOCK_HASH CONTENTION
--	+ Occurs when many concurrent workers repeatedly access the same lock manager hash buckets.
--	+ Frequently observed in:
--		- Hot rows
--		- Hot tables
--		- High-contention OLTP systems
-- C. PLAN CACHE CONTENTION
--		- Excessive compilations and ad hoc workloads may create pressure on internal cache structures protected by spinlocks.

-- 6. DIAGNOSING SPINLOCK CONTENTION
-- PRIMARY TOOLS:
--	+ Performance Monitor:
--		- Monitor:
--			* CPU utilization
--			* Batch Requests/sec
--			* Transaction throughput
--		- Look for divergence between throughput and CPU consumption.
--	+ sys.dm_os_spinlock_stats
--		- Identify spinlock types with:
--			* High backoffs
--			* High collisions
--			* Rapid increases over time
--	+ Wait Statistics
--		- SQL Server 2025 introduced SPINLOCK_EXT which can be observed through: sys.dm_os_wait_stats
--	+ Extended Events:
--		- Capture: sqlos.spinlock_backoff
--		- together with: package0.callstack
--		- to determine where contention originates.

-- 7. CALL STACK ANALYSIS
--	+ Extended Events can capture raw call stacks.
--	+ Raw call stack output contains memory addresses or unresolved symbols.
--	+ To resolve the call stack into SQL Server function names:
--		1. Download the matching SQL Server symbol files.
--		2. Ensure the symbol files match the SQL Server build.
--		3. Enable symbol resolution.
--		4. Analyze the resulting call stacks.
--	+ Useful files include:
--		- sqlservr.pdb
--		- sqldk.pdb
--		- sqlmin.pdb
--	+ Example code paths of a call stack:
--		- CMEDCatalogOwner::GetProxyOwnerBySID
--		- CMEDProxyDatabase::GetOwnerBySID
--		→ These functions indicate contention occuring during security principal and ownership lookups.

-- 8. RESOLVING SPINLOCK CONTENTION
-- A. USE FULLY QUALIFIED OBJECT NAMES
--	+ Benefits:
--		- Reduces metadata lookups
--		- Reduces name-resolution overhead
-- B. USE PARAMETERIZED QUERIES
--	+ Benefits:
--		- Reduces recompilation
--		- Reduces plan cache pressure
--		- Reduces cache-related spinlock contention.
--	+ Recommended:
--		- Stored procedures
--		- sp_executesql
-- C. REDUCE LOCK_HASH CONTENTION
--	+ Techniques: 
--		- Reduce hotspots
--		- Improve workload distribution
--		- Reduce concurrent access to the same rows.
-- D. OPTIMIZED LOCKING / OPTIMISTIC CONCURRENCY
--	+ SQL Server optimized locking can reduce the number of lock acquisition and 
--	  therefore reduce LOCK_HASH contention in some workloads.

-- 9. SPINLOCK VS LATCH VS LOCK
--	+ Spinlock:
--		- Purpose: protect internal memory structures
--		- Waiting strategy: spin on CPU
--		- Typical duration: nanoseconds to microseconds
--	+ Latch:
--		- Purpose: protect physical consistency of pages and memory structures
--		- Waiting strategy: spin, then potentially sleep
--		- Typical duration: microseconds to milliseconds
--	+ Lock:
--		- Purpose: protect logical transactional consistency
--		- Waiting strategy: suspend and wait
--		- Typical duration: milliseconds to seconds

-- 10. KEY TAKEAYAS
--	+ Spinlocks are an essential synchronization mechanism inside SQL Server.
--	+ Not all collisions and high spin counts indicate a performance problem.
--	+ Focus investigations on scenarios where:
--		- Backoffs increase significantly
--		- CPU utilization is high
--		- Throughput stops scaling
--		- A particular spinlock type dominates activity
--	+ The most effective troubleshooting workflow is:
--		sys.dm_os_spinlock_stats
--					↓
--		Identify hot spinlock type
--					↓
--		Capture spinlock_backoff Extended Events
--					↓
--		Resolve call stacks with symbols
--					↓
--		Identify code path causing contention
--					↓
--		Apply workload or design changes





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
