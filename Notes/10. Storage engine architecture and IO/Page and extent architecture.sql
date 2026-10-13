
-- PAGE AND EXTENT ARCHITECTURE

-- 1. Pages:
--	+ A page is the fundamental unit of data storage, each 8 KB in size.
--	+ Disk I/O operations against data files are performed at the page level.
--	+ A page consists of three parts:
--		- Header: 96-byte header containing metadata (object ID, index ID, etc.).
--		- Body: actual row data, stored contiguously from top to bottom.
--		- Slot array: at the end of the page, each slot (2 bytes) stores the offset byte of a row.
--		  This allows logical ordering independent of physical row placement.
--	+ Page types include:
--		- Data: stores row data; can also store partial LOB values.
--		- Text/LOB: stores large object data (text, varchar(max), varbinary(max), etc.).
--		- Index: stores B-tree index structures.
--		- GAM (Global Allocation Map): tracks allocated extents.
--		- SGAM (Shared GAM): tracks mixed extents with free pages.
--		- PFS (Page Free Space): tracks allocation and free space at the page level.
--		- IAM (Index Allocation Map): maps extents used by a heap or index.
--		- BCM (Bulk Changed Map): tracks extents modified by bulk operations since last log backup.
--		- DCM (Differential Changed Map): tracks extents changed since last full backup.
--	+ IN_ROW_DATA is limited to 8060 bytes per row. LOB_DATA and ROW_OVERFLOW_DATA units are not.
--	+ If a row exceeds 8060 bytes:
--		- LOB columns are stored in seperate LOB pages, referenced by a 16-byte pointer.
--		- Large variable-length columns may spill into ROW_OVERFLOW pages, referenced by a 24-byte pointer.
--		- Overflow data can be moved back if row size shrinks.
--		- Row-overflow storage increases I/O; avoid it by normalizing schema or splitting columns into other tables.
--		- Use sys.dm_db_index_physical_stats to identify tables and indexes using row-overflow or large object storage.

-- 2. Extents: 
--	+ An extent is a collection of 8 contiguous pages (64 KB).
--	+ Types:
--		- Uniform: owned entirely by one object.
--		- Mixed: shared by up to 8 objects, each owning individual pages.

-- 3. System pages:
--	+ GAM and SGAM pages track extent allocation, and the type of extent being used:
--		- GAM: ~64,000 extents per GAM page.
--		- SGAM: ~64,000 extents per SGAM page.
--	+ PFS pages track allocation status and free space of each pages.
--	+ IAM pages map extents used by allocation units within a GAM interval.
--		- One IAM page per allocation unit per partition per ~64,000 extents.
--	+ BCM and DCM pages track extents modified since last log/full backup.

-- 4. Data file structure (simplified):
--	+ File header → PFS → GAM → SGAM → BCM → DCM → interval of <1011 extents → PFS> → ~64,000 extents → GAM → SGAM → <repeated ...>
--	+ Partition 1 → Data File → Allocation unit 1 → IAM page → interval of <~64,000 extents → IAM page>
--							  → Allocation unit 2 → IAM page → interval of <~64,000 extents → IAM page>

-- 5. Reading pages:
--	+ Physical read: copies pages from disk into buffer cache.
--	+ Logical read: reads pages directly from buffer cache (no I/O).
--	+ Read-ahead: anticipates needed pages to optimize query execution.
--	+ IAM pages help build sorted lists of disk addresses for efficient reads.
--	+ Index pages are read serially in key order; intermediate pages guide read-ahead scheduling.
--	+ Advanced scanning allows multiple queries to share a single table scan:
--		- Concurrent scans are merged into one physical scan.
--		- Late-arriving scans join the current scan and wrap around to complete.

-- 6. Writing pages:
--	+ Logical write: modified a page in buffer cache, the page is marked as dirty.
--	+ Physical write: writes/flushes dirty pages from cache to disk.
--	+ Dirty pages are modified in cache; multiple logical writes can be combined into one physical write (gather-write).
--	+ Write-ahead logging (WAL): ensures log records are written before dirty pages.
--	+ Page protection:
--		- Torn page protection: page latched exclusively (EX) during write, no thread can access the page.
--		- Checksum protection: page latched with update (UP) latch; allows reads but blocks modifications.
--	+ Writing dirty pages:
--		- Lazy writer: flushes dirty pages and removes infrequently used pages in buffer cache.
--		- Eager writer: writes new pages in parallel especially for minimally logged operations such as bulk operations.
--		- Checkpoint: periodically flushes all dirty pages; can be triggered manually with CHECKPOINT.




-- Obtains tables or indexes that has row-overflow data and large object data
SELECT
	OBJECT_NAME(ips.object_id) AS [table],
	i.name AS [index],
	ips.index_type_desc AS [index type],
	ips.alloc_unit_type_desc AS [allocation unit]
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
LEFT JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.alloc_unit_type_desc IN ('ROW_OVERFLOW_DATA', 'LOB_DATA')