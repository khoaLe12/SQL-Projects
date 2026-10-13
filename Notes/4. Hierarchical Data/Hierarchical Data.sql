
-- Use Hierarchyid as a data type to create tables with a hierarchical structure
-- Key properties: Extremely compact, Comparison is in depth-first order, Support for arbitrary insertions and deletions



USE AdventureWorks2025;
GO

CREATE TABLE Organization (
	BusinessEntityID HierarchyID,
	OrgLevel AS BusinessEntityID.GetLevel(),
	EmployeeName Nvarchar(50) NOT NULL
)


-- Index Strategies for hierarchical data
-- 1. Depth-first: stores the rows in a subtree near each other, efficient for answering queries about subtrees "Find all files in this folder and its subfolders"
CREATE UNIQUE INDEX Org_Depth_First
ON Organization (BusinessEntityID)
GO

-- 2.Breadth-first: stores the rows each level of the hierarchy together, efficient for answering queries about immediate children "Find all employees who report directly to this manager"
CREATE CLUSTERED INDEX Org_Breadth_First
ON Organization (OrgLevel, BusinessEntityID);
GO







-- Ex1
USE SQLTestDB
CREATE TABLE BasicDemo (
    [Level] HIERARCHYID NOT NULL, -- By default duplicate key is allowed, the restriction is based on requirement
    [GroupLevel] AS [Level].GetLevel(),
    Location NVARCHAR(30) NOT NULL,
    LocationType NVARCHAR(9) NULL
)
;
CREATE CLUSTERED INDEX idx_breath_first_order
ON BasicDemo([GroupLevel], [Level])
;
CREATE UNIQUE NONCLUSTERED INDEX idx_depth_first_order
ON BasicDemo([Level])
;
INSERT BasicDemo
VALUES ('/', 'Earth', 'Planet');
;
INSERT BasicDemo
VALUES ('/1/', 'Europe', 'Continent'),
    ('/2/', 'South America', 'Continent'),
    ('/1/1/', 'France', 'Country'),
    ('/1/1/1/', 'Paris', 'City'),
    ('/1/2/1/', 'Madrid', 'City'),
    ('/1/2/', 'Spain', 'Country'),
    ('/3/', 'Antarctica', 'Continent'),
    ('/2/1/', 'Brazil', 'Country'),
    ('/2/1/1/', 'Brasilia', 'City'),
    ('/2/1/2/', 'Bahia', 'State'),
    ('/2/1/2/1/', 'Salvador', 'City'),
    ('/3/1/', 'McMurdo Station', 'City');
;
--INSERT BasicDemo
--VALUES ('/1/3/1/', 'Kyoto', 'City'),
--    ('/1/3/1/', 'London', 'City');
;
-- Query with depth first order
SELECT CAST([Level] AS NVARCHAR(100)) AS [Converted Level],
    *
FROM BasicDemo
ORDER BY [Level];
;
-- Query with breath first order
SELECT CAST([Level] AS NVARCHAR(100)) AS [Converted Level],
    *
FROM BasicDemo
ORDER BY [GroupLevel], [Level];
-- get all countries belong to Continent Europe
SELECT 
    CAST([Level] AS NVARCHAR(100)) AS [Converted Level],
    Location, 
    LocationType
FROM BasicDemo
WHERE Level.GetAncestor(1) = (SELECT level FROM BasicDemo WHERE Location = 'Europe')
-- get al descendants of Continent 'South America' with depth first order
DECLARE @level HIERARCHYID, @grouplevel int
;
select 
    @level = [Level],
    @grouplevel = [GroupLevel]
from BasicDemo
where Location = 'South America'
    and LocationType = 'Continent'
;
-- solution 1 (not so good)
select
    CAST(Level AS Nvarchar(100)) AS [Converted Level],
    Location,
    LocationType
from BasicDemo
WHERE [GroupLevel] - @grouplevel > 0 AND Level.GetAncestor([GroupLevel] - @grouplevel) = @level
order by [Level]
;
-- solution 2 (better)
select
    CAST(level AS nvarchar(50)) AS [Converted Level],
    Location,
    LocationType
from BasicDemo
where Level.IsDescendantOf(@level) = 1 AND Level <> @level
ORDER BY [level]
-- #endregion





-- Ex2:
USE SQLTestDB
CREATE TABLE Org_T1 (
    EmployeeId HIERARCHYID PRIMARY KEY,
    OrgLevel AS EmployeeId.GetLevel(),
    EmployeeName NVARCHAR(50)
);
GO
;
CREATE INDEX Org_BreadthFirst ON Org_T1 (
    OrgLevel,
    EmployeeId
);
GO
;
CREATE PROCEDURE AddEmp (
    @mgrid HIERARCHYID,
    @EmpName Nvarchar(50)
)
AS
BEGIN
    DECLARE @last_child HIERARCHYID;

    INS_EMP:

    SELECT @last_child = MAX(EmployeeId)
    FROM Org_T1
    WHERE EmployeeId.GetAncestor(1) = @mgrid

    INSERT INTO Org_T1 (EmployeeId, EmployeeName)
    SELECT @mgrid.GetDescendant(@last_child, NULL), @EmpName;

    IF @@ERROR <> 0
        GOTO INS_EMP
END
GO







-- Ex3: Using a serializable transaction
USE [SQLTestDB]
CREATE TABLE Org_T2 (
    EmployeeId HIERARCHYID PRIMARY KEY,
    LastChild HIERARCHYID NULL,
    EmployeeName NVARCHAR(50)
);
GO

CREATE OR ALTER PROCEDURE AddEmp_T2 (
    @mgrid HIERARCHYID,
    @EmpName Nvarchar(50)
)
AS
BEGIN
    DECLARE @last_child HIERARCHYID;

    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

    BEGIN TRANSACTION;

    SELECT @last_child = EmployeeId.GetDescendant(LastChild, NULL)
    FROM Org_T2
    WHERE EmployeeId = @mgrid;

    UPDATE Org_T2
    SET LastChild = @last_child
    WHERE EmployeeId = @mgrid;

    INSERT Org_T2 (EmployeeId, EmployeeName)
    VALUES (@last_child, @EmpName);

    COMMIT;
END

INSERT Org_T2 (EmployeeId, EmployeeName)
VALUES (HIERARCHYID::GetRoot(), 'David');
GO

EXECUTE AddEmp_T2 0x, 'Sariya';
GO

EXECUTE AddEmp_T2 0x58, 'Mary';
GO

SELECT *, CASt(EmployeeId AS Nvarchar(100)) AS id FROM Org_T2;







-- Ex4: Enforce a tree
CREATE TABLE Org_T3 (
    EmployeeId HIERARCHYID PRIMARY KEY,
    ParentId AS EmployeeId.GetAncestor(1) PERSISTED FOREIGN KEY REFERENCES Org_T3(EmployeeId),
    LastChild HIERARCHYID,
    EmployeeName Nvarchar(50)
);
GO





-- MOVE SUBTREES
-- Create a procedure to move subtree of @oldMgr to @newMgr
-- Or Takes the subtree of @oldMgr and makes it (including @oldMgr) a subtree of @newMgr.
USE SQLTestDB

SELECT 
    CAST(Level AS Nvarchar(100)) AS Level,
    GroupLevel,
    Location,
    LocationType
FROM BasicDemo
ORDER By Level
GO

CREATE OR ALTER PROCEDURE MoveLocation (
    @oldLocation Nvarchar(30),
    @newLocation Nvarchar(30)
)
AS
BEGIN
    DECLARE @lv_old HIERARCHYID, @lv_new HIERARCHYID;

    -- get a location required to move
    SELECT @lv_old = Level
    FROM BasicDemo
    WHERE Location = @oldLocation

    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE

    BEGIN TRANSACTION;

    -- get a destination location
    SELECT @lv_new = Level
    FROM BasicDemo
    WHERE Location = @newLocation

    -- create new child of the destination location
    SELECT @lv_new = @lv_new.GetDescendant(MAX(Level), NULL)
    FROM BasicDemo
    WHERE Level.GetAncestor(1) = @lv_new

    -- Move the subtree
    UPDATE BasicDemo
    SET Level = Level.GetReparentedValue(@lv_old, @lv_new)
    WHERE Level.IsDescendantOf(@lv_old) = 1

    COMMIT;
END

-- Move Country 'Brazil' to Continent 'Antarctica'
EXEC MoveLocation 'Brazil', 'Antarctica'