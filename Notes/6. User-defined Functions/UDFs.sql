

-- USER DEFINED FUNCTIONS (UDFs)

-- 1. Definition:
--	+ A UDF is a predefined block of logic/code that can be reused multiple times.
--	+ Similar to programming language functions: accepts parameters, perform actions, and return results.
--	+ Stored as a database object; its compiled plan can be cached and reused for faster execution.
--	+ A UDF cannot call a stored procedure, but can can call extended stored procedures or other functions.

-- 2. Types of UDFs:
--	+ T-SQL functions → best for data-access intensive logic.
--	+ CLR functions → best for computational tasks, string manipulation, and complex business logic.

-- 3. Usage:
--	+ Can be invoked in SELECT, WHERE, or APPLY clause.
--	+ Helps reduce network traffic by performing more actions in a single batch.

-- 4. Side effects:
--	+ UDFs cannot produce side effect (permanent changes outside their scope).
--	+ Disallowed operations include:
--		- Modifying external tables.
--		- Using non-local cursors.
--		- Sending emails, catalog modifications, or returning result sets directly.
--	+ Nondeterministic side-effecting functions (NEWID(), NEWSEQUENTIALID(), RAND(), TEXTPTR()) cannot be called inside UDFs.

-- 5. Valid statements inside UDFs:
--	+ DECLARE (local variables, cursors).
--	+ SET (assign values to local variables).
--	+ FETCH (assign cursor values to local variables).
--	+ control-of-flow statements (except TRY...CATCH).
--	+ UPDATE, INSERT, DELETE (only on local table variables).
--	+ EXECUTE (extended stored procedure).

-- 6. Schema-bound functions:
--	+ Created with WITH SCHEMABINDING option.
--	+ Bind referenced objects (tables, views, other UDFs).
--	+ Prevents altering or dropping referenced objects.

-- 7. Determinism:
--	+ Deterministic → always returns the same result for the same inputs.
--	+ Nondeterministic → may return different results for the same inputs.

-- 8. Indexing requirements:
--	+ To create indexes on computed columns or views based on UDFs, the function must be deterministic and schema-bound.

-- 9. Scalar UDF inlining:
--	+ Optimizes scalar UDFs by substituting expression directly into queries.
--	+ Eliminates repeated context switching between caller and function.
--	+ Enabled with WITH INLINE = ON or database option TSQL_SCALAR_UDF_INLINING = ON.
--	+ Can be disabled with OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING')).
--	+ Requirements for inlining: https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/scalar-udf-inlining?#inlineable-scalar-udf-requirements

-- 10. Scalar functions:
--	+ Return a single value of a defined data type.
--	+ Inline scalar function → single statement returning a scalar value.
--	+ Multistatement scalar function → multiple statements returning a single value.
--	+ Return type can be any data type except text, ntext, image, cursor, timestamp.

-- 11. Table-valued functions (TVFs):
--	+ Return a table data type.
--	+ Inline TVF → defined by a single SELECT statement (no function body).
--	+ Multistatement TVF → multiple statements build and return a table variable.

-- 12. System functions:
--	+ Built-in functions provided by SQL Server.
--	+ Nondeterministic system functions can be used in UDFs, except NEWID(), NEWSEQUENTIALID(), RAND(), TEXTPTR().






-- PRACTICE
-- Create a scalar function
IF OBJECT_ID(N'dbo.ufnGetInventoryStock', N'FN') IS NOT NULL
	DROP FUNCTION dbo.ufnGetInventoryStock
GO
CREATE FUNCTION dbo.ufnGetInventoryStock (@ProductID INT)
RETURNS INT
AS 
-- Return the stock level for the product.
BEGIN
	DECLARE @ret AS INT;
	SELECT @ret = SUM(p.Quantity)
	FROM Production.ProductInventory AS p
	WHERE p.ProductID = @ProductID AND p.LocationID = '6'
	IF (@ret IS NULL)
		SET @ret = 0;
	RETURN @ret;
END
GO



-- Create an inline table-value function
IF OBJECT_ID(N'Sales.ufn_SalesByStore', N'IF') IS NOT NULL
	DROP FUNCTION Sales.ufn_SalesByStore
GO
CREATE OR ALTER FUNCTION Sales.ufn_SalesByStore (@storeid INT)
RETURNS TABLE
AS
RETURN 
(
	SELECT 
		p.ProductID,
		p.Name,
		SUM(sd.LineTotal) AS 'Total'
	FROM Production.Product AS p
	INNER JOIN Sales.SalesOrderDetail AS sd ON sd.ProductID = p.ProductID
	INNER JOIN Sales.SalesOrderHeader AS sh ON sh.SalesOrderID = sd.SalesOrderID
	INNER JOIN Sales.Customer AS c ON c.CustomerID = sh.CustomerID
	WHERE c.StoreID = @storeid
	GROUP BY p.ProductID, p.Name
);
GO



-- Create a multi-statement table-valued function
IF OBJECT_ID(N'dbo.ufn_FindReports', N'TF') IS NOT NULL
	DROP FUNCTION dbo.ufn_FindReports;
GO
CREATE FUNCTION dbo.ufn_FindReports (@InEmpID INT)
RETURNS @retFindReports TABLE 
(
	EmployeeID INT PRIMARY KEY NOT NULL,
	OrganizationNode HIERARCHYID NOT NULL,
	FirstName NVARCHAR (255) NOT NULL,
	LastName NVARCHAR(255) NOT NULL,
	JobTitle NVARCHAR(50) NOT NULL,
	RecursionLevel INT NOT NULL
)
-- Returns a result set that lists all the employee who report to the
-- specific employee directly or indirectly.
AS
BEGIN
	WITH EMP_cte (EmployeeID, OrganizationNode, FirstName, LastName, JobTitle, RecursionLevel)
	AS (
		SELECT 
			e.BusinessEntityID,
			e.OrganizationNode,
			p.FirstName,
			p.LastName,
			e.JobTitle,
			0
		FROM HumanResources.Employee AS e
		INNER JOIN Person.Person AS p ON p.BusinessEntityID = e.BusinessEntityID
		WHERE e.BusinessEntityID = @InEmpID
		UNION ALL
		SELECT
			e.BusinessEntityID,
			e.OrganizationNode,
			p.FirstName,
			p.LastName,
			e.JobTitle,
			RecursionLevel + 1
		-- Join recursive member to anchor
		FROM HumanResources.Employee AS e
		INNER JOIN EMP_cte ON e.OrganizationNode.GetAncestor(1) = EMP_cte.OrganizationNode
		INNER JOIN Person.Person AS p ON p.BusinessEntityID = e.BusinessEntityID
	)
	-- copy the required columns to the result of the function
	INSERT @retFindReports
	SELECT 
		EmployeeId,
		OrganizationNode,
		FirstName,
		LastName,
		JobTitle,
		RecursionLevel
	FROM EMP_cte
	RETURN;
END
GO



-- Determine if a function is deterministic
SELECT 
	CASE OBJECTPROPERTY(OBJECT_ID('dbo.ufnGetContactInformation'), 'IsDeterministic')
		WHEN 1 THEN N'True'
		ELSE N'False'
	END AS [Is deterministic]
GO



-- Check if a scalar function is inlinable
SELECT 
	o.name AS [function name],
	o.type_desc AS [function type],
	CASE m.is_inlineable 
		WHEN 1 THEN N'True'
		ELSE N'False'
	END AS [is inlinable]
FROM sys.sql_modules AS m
INNER JOIN sys.objects AS o ON m.object_id = o.object_id
WHERE o.type IN ('IF', 'TF', 'FN');
GO



-- Enable/Disable scalar UDF inlining
-- 1. Set database compatibilty level to 150 or higher to enable
ALTER DATABASE [AdventureWorks2025]
SET COMPATIBILITY_LEVEL = 150;
GO

-- 2. Enable/Disable at database scope (ony work if compatibility level >= 150)
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = ON;
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;
GO

-- 3. Explicitly define a function with inline enabled
CREATE OR ALTER FUNCTION Sales.af_sales_orderdetail_calculate_payment (
	@OrderQty smallint,
	@UnitPrice money,
	@UnitPriceDiscount money
)
RETURNS money
WITH INLINE = ON
AS 
BEGIN
	RETURN @OrderQty * (@UnitPrice - @UnitPriceDiscount)
END;
GO

-- 4. Explicity disable when invoking the function
SELECT 
	SalesOrderID,
	OrderQty AS [quantity],
	UnitPrice AS [unit price],
	UnitPriceDiscount AS [unit price discount],
	Sales.af_sales_orderdetail_calculate_payment(OrderQty, UnitPrice, UnitPriceDiscount) AS [payment]
FROM Sales.SalesOrderDetail
OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'));
GO