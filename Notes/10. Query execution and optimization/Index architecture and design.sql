
-- INDEX ARCHITECTURE AND DESIGN

-- 1. Index design is one of the most important strategies to improve query performance.
--	+ A lack of indexes, over-indexing, or poorly designed indexes are common source of performance problems.
--	+ Designing the right indexes requires balancing query speed, index maintenance cost, and storage overhead.

-- 2. There are multiple index types with different storage formats, each suitable for specific scenarios.
--	+ Choosing the right index requires careful analysis of database characteristic, applications, and frequently used queries.

-- 3. Index design tasks:
--	+ Understand database and application characteristics:
--		- OLTP systems with frequent modifications benefit from a few narrow rowstore indexes.
--		- OLAP systems benefit from clustered columnstore indexes for analytics.
--	+ Understand query characteristics:
--		- Use Query Store to identify frequent and resource-intensive queries.
--		- Examine WHERE and JOIN predicates to determine useful indexes.
--	+ Understand data distribution:
--		- For columns with many NULLs or subsets of data, consider filtered indexes.
--	+ Evaluate index options:
--		- Data compression (row/page) improves I/O but increases CPU usage.
--		- Lower fill factor reduces page splits but increases storage usage.

-- 4. Index design considerations:
--	+ Over-indexing impacts performance of INSERT, UPDATE, DELETE, and MERGE operations.
--	+ Batch modifications (multi-row statements) reduce index maintenance overhead.
--	+ Write queries with SARGable predicates to leverage indexes.
--	+ Use covering indexes with included columns to avoid lookups, but avoid excessive included columns.
--	+ Keep index keys short, especially for clustered indexes.

-- 5. Index placement on filegroups/partitions:
--	+ By default, indexes reside in the same filegroup of the base table.
--	+ Moves indexes to other filegroups for performance:
--		- Place frequently accessed tables on faster disks.
--		- Archive tables can reside on slower disks.
--	+ Partition tables and indexes across filegroups:
--		- Makes large databases manageable (e.g., OLAP ETL).
--		- Enables partition elimimation and parallel query processing.

-- 6. Clustered index design guidelines:
--	+ Desirable properties:
--		- Narrow: small key length reduces storage and overhead.
--		- Unique: avoids the cost of additional 4-byte internal uniqueifier and improves query plans.
--		- Ever-increasing: minimizes page splits by appending new rows.
--		- Immutable: avoid clustered key changes, since the changes affect all nonclustered indexes.
--		- Non-nullable: avoid NULL block (3-4 bytes of storage) per row in an index.
--		- Fixed-width types: avoid extra bytes for variable-length types.
--	+ Ideal clustered index: single int/bigint non-nullable column populated by IDENTITY or SEQUENCE.
--	+ Architecture:
--		- One row in sys.partitions per partition (index_id = 1).
--		- Each partition has a seperate B+ tree.
--		- Allocation units:
--			+ IN_ROW_DATA (always present).
--			+ LOB_DATA (if large object columns exist).
--			+ ROW_OVERFLOW_DATA (if total variable-length columns exceed 8060 bytes).

-- 7. Nonclustered index design guidelines:
--	+ Designed to improve performance of frequent queries.
--	+ Architecture:
--		- Same B+ tree structure as clustered indexes.
--		- Leaf level contains key columns and optionally included columns.
--		- Row locators point to base table rows (heap or clustered key).
--		- One row in sys.partitions per partition (index_id > 1).
--		- Allocation units: IN_ROW_DATA, LOB_DATA, ROW_OVERFLOW_DATA as needed.

-- 8. Included columns in nonclustered indexes:
--	+ Cover queries to avoid lookups.
--	+ Balance performance gains against increased modification cost and storage usage.

-- 9. Memory-optimized hash index:
--	+ Array of hash buckets (8 bytes each) pointing to linked lists of key entries.
--	+ Each entry stores key value and row address, linked to next entry in the bucket.
--	+ Bucket count specified at creation:
--		- Too few buckets → long chains, collisions, slower lookups.
--		- Too many buckets → wasted memory.
--	+ Best for exact maches (exact values of all key columns), small range search, and table has no dulicates.
--	+ Poor choice for columns with many duplicate values.

-- 10. Memory-optimized nonclustered index (Bw-tree):
--	+ Uses a lock-free, latch-free Bw-tree structure.
--	+ Components: page map (PidMap), page allocator (PidAlloc), and linked pages.
--	+ Updates stored as delta records; consolidated into new pages when chains grow.
--	+ Operations:
--		- Delta consolidation: merges delta records into a new page when chains reach ~16 changes.
--		- Page split: creates two new leaf page, updates mapping table, and adjust parent pointers.
--		- Page merge: triggered when a page is <10% full and can merge with a contiguous sibling.
--			+ Redirects pointers, rebuilds parent page, updates mapping table, and allocates a new merged leaf page.





-- Create a new database with In-Memory OLTP enabled
CREATE DATABASE InMemory
ON PRIMARY (
	NAME = InMemoryDB_data,
	FILENAME = 'D:\Projects\SQL-Projects\Notes\InMemoryDB_data.mdf'
),
FILEGROUP InMemoryDB_mod CONTAINS MEMORY_OPTIMIZED_DATA(
	NAME = InMemoryDB_mod1,
	FILENAME = 'D:\Projects\SQL-Projects\Notes\InMemoryDB_mod1'
)
LOG ON (
	NAME = InMemoryDB_log,
	FILENAME = 'D:\Projects\SQL-Projects\Notes\InMemoryDB_log.ldf'
);
GO

-- Create a memory-optimized table
USE InMemory;
GO

CREATE TABLE dbo.InMemoryTable
(
	Id INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1024),
	Column1 Nvarchar(100) NOT NULL
)
WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA); -- use SCHEMA_ONLY to avoid logging, but data is volatile
GO