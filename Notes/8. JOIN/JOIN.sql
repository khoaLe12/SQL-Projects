
-- JOIN

-- 1. Definition:
--	+ Joins are fundamental operations used to combine data from two or more tables into a single result set.

-- 2. SQL Server implementation:
--	+ Logical join operators → defined by T-SQL syntax.
--	+ Physical join operators → actual algorithms chosen by the query optimizer to execute joins.

-- 3. Logical join types:
--	+ INNER JOIN → returns rows where both sides satisfy the join condition.
--	+ LEFT OUTER JOIN → returns all rows from the left table; unmatched rows have NULLs on the right.
--	+ RIGHT OUTER JOIN → returns all rows from the right table; unmatched rows have NULLs on the left.
--	+ FULL OUTER JOIN → returns all rows from both tables; unmatched rows have NULLs on the opposite side.
--	+ CROSS JOIN → Cartesian product; every row from left table joined with every row from right table.
--	+ SEMI JOIN → returns rows from the left table if a match exists in the right table (no duplicates, no right-side columns). Implemented with EXISTS or IN.
--	+ ANTI SEMI JOIN → returns rows from the left table where no match exists in the right table. Implemented with NOT EXISTS, NOT IN, or LEFT JOIN + IS NULL.

-- 4. Physical join algorithms:
--	+ Nested Loops Join:
--		- Iterates outer input rows, probing inner input for matches.
--		- Best when outer input is small (<10 rows) and inner input is indexed on join columns.
--		- Variants:
--			* Index Nested Loops → uses existing index.
--			* Temporary Index Nested Loops → builds index as part of query plan.
--	+ Merge Join:
--		- Requires both inputs sorted on join columns.
--		- Very efficient for large, similarly sized, sorted inputs.
--		- If input sizes differ greatly, hash join is often faster.
--		- Handles duplicates by buffering and rewinding rows from the inner input (if both input has duplicate values, this process reduces performance).
--	+ Hash Join:
--		- Efficient for large, unsorted, nonindexed inputs.
--		- Build input (smaller side) → hash table in memory.
--		- Probe input → scanned row by row, hashed to find matches.
--		- If memory insufficient:
--			* Partition phase: both inputs are hashed and split into partition files.
--			* Build/probe phase: each partition pair is processed separately.
--			* Reduces onr large join into multiple smaller joins.
--	+ Adaptive Join (SQL Server 2017+):
--		- Operator can switch between Nested Loops and Hash Joins during execution.
--		- Decision based on row count threshold:
--			* If build input is small → switch to Nested Loops.
--			* If build input exceeds threshold → continue with Hash Join.







-- PRACTICE
USE AdventureWorks2025;
GO



-- SEMI JOIN using EXISTS/IN keywords (returns customers who have placed at least one order)
SELECT c.*
FROM Sales.Customer c
WHERE EXISTS(SELECT 1 FROM Sales.SalesOrderHeader o WHERE o.CustomerID = c.CustomerID)
	AND c.CustomerID IN (SELECT CustomerID FROM Sales.SalesOrderDetail);
GO



-- ANTI SEMI JOIN using NOT EXISTS/NOT IN keywords, and LEFT JOIN clause (returns customers who have never placed an order)
SELECT c.*
FROM Sales.Customer c
WHERE NOT EXISTS(SELECT 1 FROM Sales.SalesOrderHeader o WHERE o.CustomerID = c.CustomerID)
	AND c.CustomerID NOT IN (SELECT CustomerID FROM Sales.SalesOrderHeader);
GO

SELECT c.*
FROM Sales.Customer c
LEFT JOIN Sales.SalesOrderHeader o ON o.CustomerID = c.CustomerID
WHERE o.CustomerID IS NULL