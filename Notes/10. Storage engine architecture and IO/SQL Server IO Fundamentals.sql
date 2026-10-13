
-- SQL SERVER I/O FUNDAMENTALS

-- 1. Definition
--  + Disk I/O is a core operation of the Database Engine; understanding it is key to performance tuning.
--  + Intensive disk I/O consumes resources, takes time, and can degrade performance.
--  + The buffer manager performs only read/write operations; open, close, extend, and shrink are handled by the database/file manager.
--  + Characteristics of buffer manager I/O:
--      - I/O is typically asynchronous, allowing threads to continue processing.
--      - All I/Os are issued in the calling thread; the affinity I/O mask can bind I/O to specific CPUs.
--      - Scatter-gather I/O allows to process multiple page I/Os in a single operation, reducing physical requests.

-- 2. Long I/O Requests
--  + Requests lasting ≥15 seconds are logged with event MSSQLSERVER_833.
--  + A long I/O message may indicate a permanently blocked (lost) I/O or not yet complete.
--  + Frequent long I/O messages or high disk latency/queues suggest the disk subsystem cannot handle workload.
--  + Causes:
--      - Misconfiguration or path failure (old requests postponed).
--      - Heavy workload (backup/restore, scans, sorts, index builds, bulk loads, file initialization).
--      - Hardware/driver issues, antivirus/security software interference.
--      - Inefficient queries (missing indexes/statistics).



-- LONG I/O REQUESTS: ISSUES AND SOLUTIONS

-- 1. Troubleshooting methodology:
--  + Bottleneck threshold: I/O consistently >10-15 ms.
--  + Step 1: Verify SQL Server reports slow I/O
--      - sys.dm_exec_requests:  check I/O wait type >15 ms.
--      - sys.dm_io_virtual_file_stats: check file-level latency.
--      - Error log: look for error 833.
--  + Step 2: Verify OS counters
--      - Perfmon: check disk transfer times >15 ms.
--      - If OS counters show no latency, suspect filter drivers (antivirus, backup, encryption).
--          * Solution: exclude SQL data/log files from scanning.
--  + Step 3: Check I/O subsystem throughput
--      - Compare actual throughput vs hardware capacity.
--      - Example: HBA supports 2 GB/sec but subsystem delivers only 200 MB/sec at maximum.
--      - Solution: fix SAN/NAS misconfiguration, update drivers/firmware, repair hardware.
--  + Step 4: Identify SQL Server-driven heavy I/O
--      - Use Perfmon, DMVs, XEvents, SQL Trace, DTA, error logs.
--      - Find queries causing heavy I/O and their wait types.
--      - Solution: tune queries, increase max server memory (better caching), improve hardware throughput.

-- 2. Common I/O-related wait types:
--  + PAGEIOLATCH_EX: waiting for exclusive latch (page being written).
--  + PAGEIOLATCH_SH: waiting for shared latch (page being read).
--  + PAGEIOLATCH_UP: waiting for update latch during I/O.
--  + WRITELOG: waiting for log flush (commits, checkpoints).
--      - Causes: log disk latency, too many VLFs, too many small transactions, log writer thread limits.
--  + ASYNC_IO_COMPLETION: bulk insert, undo file reads, backup reads.
--  + IO_COMPLETION: non-buffer I/O (tempdb spills, eager spools, log block reads, snapshot copy-on-write, file close/uncompression).
--  + BACKUPIO: backup waiting for data or buffer availability.

-- 3. Affinity I/O Mask
--  + Advanced option; default Windows affinity is usually best.
--  + Binds SQL Server disk I/O to specific CPUs.
--  + Each byte covers 8 CPUs; up to 4-byte value (32 CPUs).
--  + Rightmost bit = CPU0, next bit = CPU1, etc.
--  + Must coordinate with affinity mask option; no CPU can be in both.
--  + Configure via sp_configure; set mask = 0 for default.

-- 4. Antivirus Configuration
--  + Exclude SQL Server executables:
--      - sqlservr.exe, sqlagent.exe, sqlbrowser.exe, SQLDumper.exe.
--  + Exclude SQL Server data/log/backup files:
--      - .mdf, .ndf, .ldf, .bak, .trn.
--  + Exclude default data/backup directories:
--      - %ProgramFiles%\Microsoft SQL Server\MSSQL<NN>.<InstanceName>\MSSQL\DATA
--      - %ProgramFiles%\Microsoft SQL Server\MSSQL<NN>.<InstanceName>\MSSQL\Backup
--  + Exclude Full-Text catalog files:
--      - %ProgramFiles%\Microsoft SQL Server\MSSQL<NN>.<InstanceName>\MSSQL\FTDATA







-- PRACTICE
-- To troubleshoot slow I/O performance, see note "Troubleshoot slow IO performance.txt"





-- CONFIGURE affinity I/O mask
-- Check current affinity I/O mask
sp_configure 'affinity I/O mask';
GO

-- Enable advanced options
sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

-- Set the affinity I/O mask to use last 10 CPUs
sp_configure 'affinity I/O mask', 4290772992;
RECONFIGURE;
GO





-- CHECK FOR REQUESTS THAT HAVE I/O WAIT
SELECT 
	r.session_id, 
	r.wait_type, 
	r.wait_time AS wait_time_ms
FROM sys.dm_exec_requests r 
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
WHERE r.wait_type IN ('PAGEIOLATCH_SH', 'PAGEIOLATCH_EX', 'WRITELOG', 'IO_COMPLETION', 'ASYNC_IO_COMPLETION', 'BACKUPIO')
AND is_user_process = 1;
GO





-- GET ACCUMULATIVE DATA OF WAIT_TYPE PAGEIOLATCH
SELECT 
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'PAGEIOLATCH%'
ORDER BY wait_time_ms DESC;
GO





-- View database file-level latency
SELECT 
    LEFT(mf.physical_name, 100) AS [File],
    LEFT (mf.physical_name, 2) AS Volumn,
    LEFT (DB_NAME(vfs.database_id), 32) AS [Database Name],
    ReadLatency = CASE WHEN num_of_reads = 0 THEN 0 ELSE (io_stall_read_ms / num_of_reads) END,
    WriteLatency = CASE WHEN num_of_writes = 0 THEN 0 ELSE (io_stall_write_ms / num_of_writes) END,
    AvgLatency = CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0 ELSE (io_stall / (num_of_reads + num_of_writes)) END,
    LatencyAssessment = CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 'No data' ELSE
        CASE WHEN (io_stall / (num_of_reads + num_of_writes)) < 2 THEN 'Excellent'
             WHEN (io_stall / (num_of_reads + num_of_writes)) BETWEEN 2 AND 5 THEN 'Very good'
             WHEN (io_stall / (num_of_reads + num_of_writes)) BETWEEN 6 and 15 THEN 'Good'
             WHEN (io_stall / (num_of_reads + num_of_writes)) BETWEEN 16 AND 100 THEN 'Poor'
             WHEN (io_stall / (num_of_reads + num_of_writes)) BETWEEN 100 AND 500 THEN 'Bad'
             ELSE 'Deplorable' 
        END END,
    [Avg KBs/Transfer] = CASE WHEN (num_of_reads = 0 AND num_of_writes = 0) THEN 0
        ELSE (((num_of_bytes_read + num_of_bytes_written) / (num_of_reads + num_of_writes)) / 1024) END
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
JOIN sys.master_files AS mf ON vfs.database_id = mf.database_id
    AND vfs.file_id = mf.file_id
WHERE vfs.database_id = DB_ID()
ORDER BY AvgLatency DESC



-- Find which volumes host the database files
SELECT
    DISTINCT LEFT(volume_mount_point, 32) AS volume_mount_point
FROM sys.master_files f
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) vs