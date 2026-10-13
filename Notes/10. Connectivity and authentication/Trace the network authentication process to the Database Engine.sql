
-- TRACE THE NETWORK AUTHENTICATION PROCESS TO THE DATABASE ENGINE

-- 1. SQL AUTHENTICATION
--	+ Step 1: TCP three-way handshake
--		- Initialize the conversation, client usually is the starting point.
--		- Client uses an ephemeral port to send a SYN packet with S flag set to the server.
--		- The server replies with its own SYN packet with the ACK flag set.
--		- Finally, the client responds with an ACK packet to announce it received reply from the server.
--	+ Step 2: Driver handshake
--		- Provide informations and requirements about each other including: whether to encypt data packets, use Multiple Active Result Sets, its version number, ...
--		- The client sends TDS packet with those above information.
--		- The server responds with its TDS, such as authentication requirements.
--		- This sequence happends before any sort of security negotiation is performed.
--	+ Step 3: SSL/TLS handshake
--		- This step is where the security key is negotiated for encrypting packets.
--		- The client or server can close the connection at this stage if the TLS versions don't line up, or they don't have any cipher suites in common.
--		- The client send Hello packet and then the server respond with its Hello packet, plus some extra packets related to Secure Channel.
--	+ Step 4: Login and authentication
--		- The client sends an encrypted login packet, the data might shown as 'SSL Application Data' or 'TDS:Data'.
--		- The server sends response which either confirms the login (with ACK token), or returns a Login Failed error message.
--	+ Step 5: Execute a command and read the response
--		- If the connection is encrypted, all the packets are shown as 'SSL Application Data'.
--		- Commands are sent as either a TDS:SQLBatch (plain T-SQL statements) or a TDS:RPCRequest (executed stored procedures) packet.
--	+ Step 6: TCP four-way closing handshake
--		- Microsoft drivers use the four-way handshake to close connections.
--		- Firstly, the client sends a FIN packet to ther server, which the server responds to with an ACK.
--		- The server then sends its own FIN packet, which the client acknowledges (ACK).



-- Find host that establishes most connections
-- Can be used to compare the host throughput and its number of connections which used to identify if connection pool is limit
SELECT 
	c.client_net_address, 
	s.host_name, 
	s.host_process_id, 
	count(*) AS 'No. sessions',
	SUM(CASE WHEN status = N'sleeping' THEN 1 ELSE 0 END) AS 'No. sleeping sessions',
	SUM(CASE WHEN status = N'running' THEN 1 ELSE 0 END) AS 'No. running sessions',
	SUM(s.reads) AS 'reads',
	SUM(s.writes) AS 'writes',
	SUM(s.cpu_time) AS 'Total CPU time ms',
	SUM(s.memory_usage) * 8.0 / 1024 AS 'Total session memory usage MB'
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
WHERE s.is_user_process = 1
GROUP BY c.client_net_address, s.host_name, s.host_process_id
ORDER BY [No. sessions] DESC


