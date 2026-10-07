
-- Create and start an Extended Event Session
IF EXISTS (
	SELECT 1
	FROM sys.server_event_sessions
	WHERE name = 'TrackLockEscalation'
)
	DROP EVENT SESSION TrackLockEscalation ON SERVER;
GO

-- Create the Extended Event session
CREATE EVENT SESSION TrackLockEscalation ON SERVER
ADD EVENT sqlserver.lock_escalation
(
	SET collect_database_name = 1, collect_statement = 1
	ACTION (
		sqlserver.sql_text,			-- Captures the SQL statement
		sqlserver.session_id,		-- Captures the SPID
		sqlserver.database_id,		-- Captures the database ID
		sqlserver.client_app_name,	-- Captures the application name
		sqlserver.client_hostname,	-- Captures the host name,
		sqlserver.username			-- Captures the user
	)
)
--ADD TARGET package0.histogram
--(
--	SET source=N'sqlserver.database_id'
--)
ADD TARGET package0.event_file
(
	SET filename = 'D:\event_file\LockEscalation.xel',
		max_file_size = 10, -- MB
		max_rollover_files = 5
)
WITH (
	MAX_MEMORY = 4096 KB,
	EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
	MAX_DISPATCH_LATENCY = 5 SECONDS,
	TRACK_CAUSALITY = ON,
	STARTUP_STATE = OFF
)
GO

-- Start the session
ALTER EVENT SESSION TrackLockEscalation ON SERVER STATE = START;
GO

-- Read from event file
SELECT 
	tab.event_data.value('(event/@name)[1]', 'nvarchar(50)') AS event_name,
	tab.event_data.value('(event/@timestamp)[1]', 'datetime2') AS [timestamp],
	tab.event_data.value('(event/data[@name="mode"]/value)[1]', 'nvarchar(50)') AS lock_mode,
	tab.event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text,
	tab.event_data.value('(event/action[@name="session_id"]/value)[1]', 'int') AS [session_id],
	tab.event_data.value('(event/action[@name="database_id"]/value)[1]', 'int') AS database_id,
	tab.event_data.value('(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(256)') AS client_app_name,
	tab.event_data.value('(event/action[@name="client_hostname"]/value)[1]', 'nvarchar(256)') AS client_hostname
FROM sys.fn_xe_file_target_read_file('D:\event_file\LockEscalation*.xel', NULL, NULL, NULL)
CROSS APPLY (SELECT CAST(event_data AS XML)) AS tab(event_data);

-- Read from histogram (if use)
SELECT 
	CAST(xet.target_data AS XML) AS XML_data,
	*
FROM sys.dm_xe_session_targets xet
JOIN sys.dm_xe_sessions xe ON xe.address = xet.event_session_address
WHERE xe.name = 'TrackLockEscalation' AND xet.target_name = 'histogram';


-- Stop and clean up the session
ALTER EVENT SESSION TrackLockEscalation ON SERVER STATE = STOP;
DROP EVENT SESSION TrackLockEscalation ON SERVER;