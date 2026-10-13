
-- LOGON TRIGGERS

-- 1. A logon trigger fires on the LOGON event when a new connection is established to a SQL Server instance.

-- 2. It executes after authentication but before the user session is fully established.

-- 3. Common uses include:
--	+ Auditing and tracking login activity.
--	+ Controlling or restricting server sessions.

-- 4. Multiple logon triggers can be defined:
--	+ Use the sp_settriggerorder system stored procedure to specify which trigger fires first and last.
--	+ The order of other triggers cannot be explicitly controlled.

-- 5. Transaction behavior:
--	+ When the first logon trigger fires, the transaction count is set to 0.
--	+ If the last trigger completes successfully and the transaction count remains 1, all logon triggers are considered successfully.
--	+ ROLLBACK TRANSACTION resets the count to 0 and cancels the login attempt.
--	+ COMMIT TRANSACTION is not recommended inside logon triggers, as it may interfere with transaction handling (might set count to 0).
--	+ If rolled back, all changes made by current and previous triggers are undone.






-- PRACTICE
USE master;
GO

-- CREATE LOGON TRIGGER TO RESTRICT TO HAVE ONLY THREE SESSIONS OF LOGIN 'sa' AT A TIME
CREATE OR ALTER TRIGGER connection_limit_trigger ON ALL SERVER
WITH EXECUTE AS N'sa'
FOR LOGON AS BEGIN
	IF ORIGINAL_LOGIN() = N'sa'
		AND (
			SELECT COUNT(*)
			FROM sys.dm_exec_sessions
			WHERE is_user_process = 1
				AND original_login_name = N'sa'
		) > 10
	BEGIN
		PRINT N'Reached maximum of three session with sa login'
		ROLLBACK;
	END
END;