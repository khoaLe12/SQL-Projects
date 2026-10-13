
-- SQL SERVER TRANSACTION LOG ARCHITECTURE AND MANAGEMENT

-- 1. Transaction log records all transactions and the database modifications that made by each transaction.

-- 2. Transaction log logical architecture
--	+ Conceptually, the log file is a string of log records, the insertion of records are performed sequentially to the end of the log.
--	+ Each record is identified by a log sequence number (LSN) whose value is higher than the LSN of the record before it.
--	+ Each log record is associated with a transaction by the transaction ID; all records in a transaction are individually linked in a chain.
--	+ Logical operation logged:
--		- Roll forward: the operation is performed again.
--		- Roll back: the reverse logical operation is performed.
--	+ The active part of the log is identified as a range between LSN of the first log and the last log; the active log will not be truncated.

-- 3. Transaction log physical architecture
--	+ The transaction log maps over one or more physical files, and efficiently store the sequence of log records in that set of files.
--	+ Each physical log file consists of number of virtual log files (VLFs) that each VLF has no fixed size.
--	+ The size or number of VLFs can't be configured or set manually, those factors are dynamically choosed by the server.
--	+ Too many small virtual files could slow down database startup, log backup and restore operations, and cause transactional replication/CDC and Always On redo latency.
--	+ Some common symptoms if the number of VLFs reaches the range of several hundred thousand:
--		- Database take a very long time to finish recovery.
--		- Restoring a database takes a very long time to complete.
--		- Attempts to attach a database take a very long time to complete.
--		- Encounter error messages 1413, 1443, and 1479, indicating a timeoute while set up database mirroring.
--		- Encounter memory-related errors like 701 when attempting to restore a database.
--		- Transactional replication or CDC might experience significant latency.
--	+ It is recommended to observe and estimate the ideal initial size and growth increment for log file, view Fixing-VLFs script for more information.

-- 4. Log truncation
--	+ Log truncation deletes inactive virtual log files from logical transaction log, freeing space for reuse by the physical transaction log.
--	+ If a transaction log is never truncated, it will eventually fill all the disk space which can make logical log wrap unused VLFs.
--	+ Perform a CHECKPOINT operation to mark inactive portion of logical log as reusable, which then freed for physical log.

-- 5. Write-ahead transaction log (WAL algorithm)
--	+ All data page modifications are marked as dirty pages and keep on cache before written to disk.
--	+ A dirty page can have more than one logical write, each associated with a transaction log records inserted in the log cache.
--	+ SQL Server uses this algorithm to guarantees that any data modification must be written to disk only after its associated log record is written to disk.
--	+ Perform CHECKPOINT operation will flush all log records and dirty pages to disk.
