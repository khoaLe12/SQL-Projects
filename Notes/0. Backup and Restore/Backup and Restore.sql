USE [master];
GO

CREATE DATABASE [SQLTestDB];
GO

USE [SQLTestDB];
GO
CREATE TABLE SQLTest (
    ID INT NOT NULL PRIMARY KEY,
    c1 VARCHAR(100) NOT NULL,
    dt1 DATETIME NOT NULL DEFAULT GETDATE()
);
GO

USE [SQLTestDB];
GO

INSERT INTO SQLTest (ID, c1) VALUES (1, 'test1');
INSERT INTO SQLTest (ID, c1) VALUES (2, 'test2');
INSERT INTO SQLTest (ID, c1) VALUES (3, 'test3');
INSERT INTO SQLTest (ID, c1) VALUES (4, 'test4');
INSERT INTO SQLTest (ID, c1) VALUES (5, 'test5');
GO

SELECT * FROM SQLTest;
GO





-- + A backup of transaction logs that includes all log records that weren't backed up in a previous log backup (full recovery model).

-- [SQLTestDB] database is set to use the full recovery model
USE [master];
ALTER DATABASE [SQLTestDB] SET RECOVERY FULL;

-- Create backup (backup set 1)
USE [master];
BACKUP DATABASE [SQLTestDB]
TO DISK = N'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB.bak'
WITH NOFORMAT, NOINIT,
NAME = N'SQLTestDB-Full Database Backup', SKIP, NOREWIND, STATS = 10;

-- Create a routine log backup (backup set 2) - this append all new transaction logs since the last full backup (backup set 1) to the backup file
BACKUP LOG [SQLTestDB] TO DISK = 'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB.bak';

-- Create a routine log backup (backup set 3) into new backup file - this contains only the log records generated since the last log backup (backup set 2)
BACKUP LOG [SQLTestDB] TO DISK = 'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB_LogSet2.bak';

-- Restore a database to the backup set 2
USE [master];
RESTORE DATABASE [SQLTestDB]
FROM DISK = N'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB.bak';

-- Restore a database to the backup set 3
RESTORE LOG [SQLTestDB]
FROM DISK = 'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB_LogSet2.bak'
WITH NORECOVERY;

-- Drop database and backup history in msdb database
-- msdb database is used by SQL Server Agent for scheduling alerts and jobs.
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'SQLTestDB'
USE [master];
DROP DATABASE [SQLTestDB];






-- FULL DATABASE BACKUP, followed by differential backup
--  + Full database backups represent the whole database at the time the backup finished.
--  + Differential database backups is based on the latest full backup, it contains changed data pages since the latest backup

-- 1. Estimate the size of full database 
USE [SQLTestDB]
EXEC sp_spaceused;

-- 2. To Suppress backup log entries, using trace flag 3266 (IF NONE OF SCRIPTS DEPEND ON THOSE ENTRIES)
DBCC TRACEON (3226 , -1) -- enable suppress
DBCC TRACEOFF (3226 , -1) -- disable

-- 3. Create an encrypted backup with a specified certificate
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<password>';
OPEN MASTER KEY DECRYPTION BY PASSWORD = '<password>'

CREATE CERTIFICATE MyCertificate
WITH SUBJECT = 'Backup Cert', EXPIRY_DATE = '20261231';

-- 4. Backup to a disk device
USE [master];
BACKUP DATABASE [SQLTestDB]
TO DISK = N'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB.bak'
    WITH 
        SKIP, 
        NOREWIND, 
        FORMAT,
        MEDIANAME = 'SQLServerBackups',
        NAME = N'Full backup of SQLTestDB', 
        COMPRESSION (ALGORITHM = ZSTD), -- compression cost performance but reduce the backup size
        ENCRYPTION (
            ALGORITHM = AES_256,
            SERVER CERTIFICATE = MyCertificate
        ),
        STATS = 10;

-- 5. NOTES: since the On-Premise is not available, consider using simple backup strategy
USE [master];
BACKUP DATABASE [SQLTestDB]
TO DISK = N'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB.bak'
    WITH 
        SKIP, 
        NOREWIND, 
        FORMAT, -- FORMAT indicates overwrite any existing backup
        MEDIANAME = 'SQLServerBackups',
        NAME = N'Full backup of SQLTestDB', 
        STATS = 10;

-- 6. Identify the backup ratio of compressed backup
SELECT name AS backup_name, database_name, backup_size, compressed_backup_size, compression_algorithm, backup_size/compressed_backup_size AS ratio FROM msdb..backupset;  

-- 7. Differntial backup with Full backup as Base of differential
-- Recommend strategy, Full backup weekly and differential backups during the week
-- Day 1 (backup of 1 day)
USE [master];
BACKUP DATABASE [SQLTestDB]
TO DISK = N'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB_diff1.bak'
    WITH DIFFERENTIAL;
GO

-- Day 2 (backup of 2 days)
USE [master];
BACKUP DATABASE [SQLTestDB]
TO DISK = N'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB_diff2.bak'
    WITH DIFFERENTIAL;
GO

-- 8. Restore in a sequence from full backup to differential backups
-- Restore base
RESTORE DATABASE [SQLTestDB] FROM DISK = 'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB.bak' WITH NORECOVERY;
-- Restore state of day 3
RESTORE DATABASE [SQLTestDB] FROM DISK = 'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB_diff3.bak' WITH RECOVERY;
-- Restore state of day 2
RESTORE DATABASE [SQLTestDB] FROM DISK = 'D:\Projects\SQL-Projects\Notes\1. Backup and Restore\SQLTestDB_diff2.bak' WITH RECOVERY;