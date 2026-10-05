-- DIAGNOSE AND RESOLVE LATCH CONTENTION IN SQL SERVER

-- 1. OVERVIEW:
--	+ A latch is a lightweight synchronization primitive used by SQL Server to protect the physical consistency of in-memory structures. Example include:
--		- Data pages
--		- Index pages
--		- Allocation pages (PFS, GAM, SGAM, IAM)
--		- Internal SQL Server memory structures
--	+ Latches differ from locks:
--		- Latches protect physical consistency of memory structures.
--		- Locks protect logical consistency of data during transactions.
--		- Latches are typically held only for the duration of a physical operation.
--		- Locks are typically held for the duration required by transaction isolation rules.
--	+ SQL Server uses three broad categories of latches:
--		1. Buffer latches (PAGELATCH_*)
--			- Protect pages already loaded into the buffer pool.
--			- Used during read and write operations against in-memory pages.
--		2. IO latches (PAGEIOLATCH_*)
--			- Protect pages while they are being loaded from disk into the buffer pool.
--			- Prevent multiple workers from loading the same page simultaneously.
--		3. Non-buffer latches (LATCH_*)
--			- Protect internal structures other than data or index pages.
--			- Example: root splits latch (ACCESS_METHODS_HOBT_VIRTUAL_ROOT)

-- 2. LATCH MODES:
--	+ Latches can be acquired in five modes: 
--		- KP (Keep): prevents the protected structure from being destroyed.
--		- SH (Shared): required for read access.
--		- UP (Update): indicates intent to modify a structure.
--		- EX (Exclusive): allows one worker to modify the structure, incompatible requests must wait.
--		- DT (Destroy): required before destroying the protected structure, Ex: freeing a clean buffer page.
--	+ Compatibility Matrix:
--			KP	SH	UP	EX	DT
--		KP	Y	Y	Y	Y	N
--		SH	Y	Y	Y	N	N
--		UP	Y	Y	N	N	N
--		EX	Y	N	N	N	N
--		DT	N	N	N	N	N
--	+ Multiple latches may exist simultaneously if they are compatible.
--	+ Incompatible requests are queued until the current latch holder releases the latch.
--	+ A spinlock of type SOS_Task is used to protect the wait queue by enforcing serialized access to the queue, this spinlock is responsible for signaling threads in the queue.
--	+ The wait queue is processed on a first in, first out (FIFO) basis.

-- 3. LATCH WAIT TYPES:
--	+ SQL Server records cumulative wait statistics in sys.dm_os_wait_stats
--	+ Common latch-related waits:
--		- Buffer latch (PAGELATCH_*): waiting on pages already in memory, indicates memory-side page contention.
--		- IO latch (PAGEIOLATCH_*): waiting for pages to be read from disk, often indicates storage subsystem latency.
--		- Non-buffer latch (LATCH_*): waiting on internal memory structures that are not buffer pages.
--	+ Important:
--		- Not all latch waits indicate a performance problem.
--		- Some amount of latch waiting is normal in highly concurrent systems.

-- 4. WHAT IS LATCH CONTENTION?
--	+ Latch contention occurs when multiple worker threads attempt to acquire incompatible latches on the same in-memory structure.
--	+ Excessive latch contention becomes a problem when:
--		- Wait times increase significantly.
--		- Throughput stops increasing or decreases.
--		- CPU utilization remains low despite increasing workload.
--		- Workers spend substantial time waiting rather than performing useful work.
--	+ Typical symptoms (inspect with Performance Monitor with 2 counters: Transactions per second as throughput, average page latch wait time)
--		- Increased PAGELATCH waits.
--		- Reduces transaction throughput.
--		- Reduces scalability as CPU count increases.
--		- Lower than expected CPU utilization.
--	+ Factors affecting latch contention:
--		- High number of logical CPUs used by SQL Server: Latch contention can occur on any multi-core system, commonly observed on system with 16+ CPU cores.
--		- Depth of B-tree, clustered and non-clustered index design, size and density of rows per page, and access patterns (read/write/delete activity) are factors that can contribute to excessive page latch contention.
--		- High degree of concurrency at the application level: occurs in conjunction with a high level of concurrent requests from the application tier.
--		- Layout of logical files uses by SQL Server databases: Logical file layout can affect the level of latch contention caused by allocation structures.
--		- I/O subsystem performance: Significant PAGEIOLATCH waits indicate SQL Server is waiting on the I/O subsystem.

-- 5. COMMON CAUSES OF LATCH CONTENTION:
--	+ Last page insert contention:
--		- Common on tables inserts use a sequential index key: IDENTITY, BIGINT sequence, DATETIME
--		- All inserts target the same right-most leaf page of the B-tree, resulting in PAGELATCH_EX contention.
--		→ Solutions: Use a non-sequential leading key, reorder index keys, introduce hash partitioning.
--	+ Small table + shallow B-tree contention:
--		- Frequently observed in queu tables and messaging systems.
--		- Contributing factors: small row size, high page density, small table size, high concurrency.
--		- Many workers repeatedly access the same root and upper-level pages, generating SH and EX latch contention.
--	+ PFS page contention:
--		- PFS (Page Free Space) pages track allocation information.
--		- Page allocations and deallocations require UP latches.
--		- Contention typically occurs when: allocation rate is high, few data files exist, CPU concurrency is high.
--		→ Solutions: add multiple equally sized data files, distribute allocation activity across multiple PFS pages.
--	+ PAGEIOLATCH contention:
--		- Indicates workers are waiting for data pages to be loaded from disk.
--		- Common causes: slow storage subsystem, excessive physical reads, memory pressure.

-- 6. FACTORS THAT INFLUENCE LATCH CONTENTION:
--	+ Latch contention is commonly observed on servers with high concurrency and large CPU counts (16+ cores and above).
--	+ Factors:
--		- Number of logical CPUs.
--		- Degree of concurrency.
--		- B-tree depth.
--		- Row size and page density.
--		- Clustered and nonlustered index design.
--		- Access patterns (read/write/delete).
--		- Data file layout.
--		- I/O subsystem performance.

-- 7. IDENTIFYING LATCH CONTENTION:
--	+ Indicators include:
--		- Increasing average latch wait times.
--		- Growing percentage of total waits spent on latch waits.
--		- Throughput plateauing as workload increases.
--		- CPU utilizarion remaining low during peak load.
--	+ Always correlate latch waits with
--		- CPU utilization.
--		- Throughput.
--		- I/O latency.
--		- Lock waits.
--		- Network bottlenecks.
--	+ Similar symptoms can be caused by other bottlenecks.

-- 8. CONTENTION MITIGATION TECHNIQUE:
--	A. USE A NON-SEQUENTIAL LEADING KEY:
--	+ Options:
--		- Replace a sequential index key with a non-sequential key; Ex: ATM_ID (associate with a single customer) as key to insert a new withdrawal transaction (distribute inserts across a key range).
--		- Reordered index columns; this approach require modify select queries to utilize new index definition.
--		- Using a hash values as the leading column.
--		- Use a GUID as the leading key column; this technique can introduce potential downsides of more page-splits, poor physical organization and low page density.
--	+ Benefits:
--		- Inserts distributed across multiple leaf pages.
--		- Reduces right-most page contention.
--		- Allows the use of other partitioning features.
--	+ Trade-offs:
--		- Possible challenges when choosing a key/index to ensure 'close enough to' uniform distribution of inserts all of the time.
--		- GUID as leading column or random inserts across B-Tree can result in excessive page-split operations -> lead to latch contention on non-leaf pages.
--	B. Use hash partitioning with a computed column:
--	+ Approach:
--		1. Create a new filegroup or use an existing filegroup to hold the partitions.
--		2. Create the same number of files as number of physical CPU cores for the filegroup (less allocation contention).
--		3. Partitioning the tables into a number of partitions equal to the number of CPU cores (define partition scheme and function, bind it to the filegroup).
--		4. Add a tinyint or smallint hash column using a good computed hash distribution (use HASHBYTES or BINARY_CHECKSUM with modulo).
--		5. Create the index contains hash column on the new partitioning scheme.
--	+ Benefits:
--		- Distributes inserts across multiple B-trees.
--		- Eliminates a single hot insert page.
--		- The hash value modulus operation ensures that the inserts are split across the different B-trees, which alleviates the bottleneck.
--	+ Trade-offs:
--		- Select queries need to be modified to include the hash partition in the predicate.
--		- It eliminate the possibility of partition elimination on certain other queries, such as range-based reports.
--		- When joining other table, it requires hash value on the second table as join criteria.
--		- It prevents the use of partitioning for other management features (sliding window archiving, partition switch).

-- 9. KEY TAKEAWAY:
--	+ Latches are essential for protecting SQL Server's internal structures and some latch wait is normal.
--	+ Focus investigations on scenarios where increasing concurrency results in:
--		- Higher PAGELATCH/PAGEIOLATCH waits.
--		- Reduced throughput.
--		- Poor CPU utilization.
--	+ The most common causes are:
--		- Last-page insert contention.
--		- Queue-table contention.
--		- Allocation-page contention (PFS/GAM/SGAM).
--		- Storage latency (PAGEIOLATCH).
--	+ Correct diagnosis should always precede corrective action.






-- View active latch waits:
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





-- OBTAIN PAGE INFORMATION:
-- Isolate the object causing latch contention using sys.dm_os_buffer_descriptors
SELECT
	wt.session_id,
	wt.wait_type,
	wt.wait_duration_ms,
	s.name AS schema_name,
	o.name AS object_name,
	i.name AS index_name
FROM sys.dm_os_buffer_descriptors AS bd
INNER JOIN (
	SELECT 
		*,
		CHARINDEX(':', wt.resource_description) AS file_index,
		CHARINDEX(':', wt.resource_description, CHARINDEX(':', wt.resource_description) + 1) AS page_index,
		wt.resource_description as rd
	FROM sys.dm_os_waiting_tasks AS wt
	WHERE wt.wait_type LIKE 'PAGELATCH%'
) AS wt ON bd.database_id = SUBSTRING(wt.rd, 0, wt.file_index)
	AND bd.file_id = SUBSTRING(wt.rd, wt.file_index + 1, 1)
	AND bd.page_id = SUBSTRING(wt.rd, wt.page_index + 1, LEN(wt.rd))
INNER JOIN sys.allocation_units AS au ON bd.allocation_unit_id = au.allocation_unit_id
INNER JOIN sys.partitions AS p ON au.container_id = p.partition_id
INNER JOIN sys.indexes AS i ON p.index_id = i.index_id AND p.object_id = i.object_id
INNER JOIN sys.objects AS o ON i.object_id = o.object_id
INNER JOIN sys.schemas AS s ON o.schema_id = s.schema_id
ORDER BY wt.wait_duration_ms DESC;





-- Alternative technique to isolate the object causing latch contention
-- 1. Enable trace flag 3604 to enable console output
DBCC TRACEON (3604);

-- 2. Read information of resource_description column of sys.dm_os_waiting_tasks: '1:1:111305' | db_id:file_id:page_id
DBCC PAGE (1, 1, 111305, -1);

-- 3. Examine the DBCC output, find associated Metadata ObjectID





-- Use hash partitioning with a computed column
USE AdventureWorks2019;
GO

-- 1. Create new filegroup and optionally add 16 files (assumpt number of CPU cores is 16)
ALTER DATABASE AdventureWorks2019
ADD FILEGROUP AddressFG;

ALTER DATABASE AdventureWorks2019
ADD FILE (
	NAME = 'AddressFile1',
	FILENAME = 'D:\0. Khoa\0. SQL Projects\Notes\10. Concurrency, locking, and contention\AddressFile1.ndf',
	SIZE = 50MB,
	MAXSIZE = 500MB,
	FILEGROWTH = 10MB
) TO FILEGROUP AddressFG;

-- 2. Create partition scheme and function
CREATE PARTITION FUNCTION [pf_hash16](TINYINT)
	AS RANGE LEFT
	FOR VALUES (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);

CREATE PARTITION SCHEME [ps_hash16]
	 AS PARTITION [pf_hash16]
	 ALL TO ([AddressFG]);

-- 3. Add computed column to table (consider using bulk loading techniques)
ALTER TABLE [Person].[Address]
	ADD [HashValue] AS (CONVERT (TINYINT, ABS(BINARY_CHECKSUM([AddressID]) % (16)), (0))) PERSISTED NOT NULL;

-- 4. Add hash column as leading column of index
ALTER TABLE [Person].[Address] DROP CONSTRAINT [PK_Address_AddressID];

DROP INDEX [PK_Address_AddressID] ON [Person].[Address];

CREATE CLUSTERED INDEX [PK_Address_HashValue_AddressID] 
ON [Person].[Address] (HashValue, AddressID)
WITH (DROP_EXISTING = OFF);