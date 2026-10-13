
-- Collations provide sorting rules, case, and accent sesitivity properties for character data types.
-- Unicode is a standard for mapping code points to characters.


-- View collation settings of a server
SELECT CONVERT(Varchar(256), SERVERPROPERTY('collation'))
;
EXEC sp_helpsort



-- View collation settings of a database
SELECT name, collation_name FROM sys.databases
;
SELECT CONVERT(Varchar(256), DATABASEPROPERTYEX('AdventureWorksDW2025', 'collation'));



-- View collation settings of a column
SELECT name, collation_name FROM sys.columns WHERE object_id = OBJECT_ID('BasicDemo') AND name = 'Level'
;
SELECT t.name TableName, c.name ColumnName, collation_name  
FROM sys.columns c  
inner join sys.tables t on c.object_id = t.object_id;  



-- View all collations supported by SQL Server
SELECT name, description FROM sys.fn_helpcollations()
--WHERE name LIKE 'v%';




-- Apply collation explicitly in queries (Expression level)
-- By default the collation 'SQL_Latin1_General_CP1_CI_AS' is used for the Microsoft Fabric server
USE [SQLTestDB]
GO

-- case-sensitive, accent sensitive collation
SELECT * FROM BasicDemo 
WHERE Location = 'spain'
COLLATE Latin1_General_CS_AS

-- case-insensitive accent sensitive collation
SELECT * FROM BasicDemo 
WHERE Location = 'spain'
COLLATE Latin1_General_CI_AS