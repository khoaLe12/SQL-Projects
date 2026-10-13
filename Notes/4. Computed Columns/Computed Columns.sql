-- COMPUTED COLUMNS
--	+ A computed column defined by an expression whose inputs are columns from the same table, producing scalar value.
--	+ A computed column is virtual by default (not physically stored), unless explicitly marked as PERSISTED.
--	+ Computed columns cannot be used in DEFAULT, FOREIGN KEY, or CHECK constraint definitions, nor can they be declared with NOT NULL (unless PERSISTED and guaranteed non-null).
--	+ A computed column cannot be direct the target of an INSERT/UPDATE statements; its value is derived automatically.
--	+ Indexes can be created on computed columns only if certain requirements are met: the expression must be deterministic, precise, and conform to rules regarding ownership, data type, and SET options (see "Indexes on computed columns")
--	+ A computed column expression is deterministic if it always return the same result for a specified set of input
--	+ A computed column expression is precise if it does not involve FLOAT or REAL data types, and is not defined using expressions of those types.



USE SQLTestDB;
GO



-- Add computed columns
DROP TABLE IF EXISTS sc1.Table_ComputedColumns
CREATE TABLE sc1.Table_ComputedColumns (
	Id Int IDENTITY (1,1) NOT NULL,
	Quantity Smallint,
	UnitPrice Money,
	SellPrice Money,
	OrderDate Date,
	SellValue AS Quantity * SellPrice,
	FloatValue Float NOT NULL DEFAULT 0,
	Revenue AS Quantity * (SellPrice - UnitPrice) * FloatValue,
	NonDeterminismValue AS GETDATE(), -- GETDATE() is nondeterministic function
	CONSTRAINT PK_Table_ComputedColumns PRIMARY KEY (Id)
)
ALTER TABLE sc1.Table_ComputedColumns ADD [year] AS YEAR(OrderDate)


-- Create index on computed column ([year] is determinism and precise)
CREATE NONCLUSTERED INDEX Idx_Table_ComputedColumns_year ON sc1.Table_ComputedColumns([year])


-- Insert and display results
INSERT INTO sc1.Table_ComputedColumns (Quantity, UnitPrice, SellPrice, OrderDate)
VALUES (25, 2.00, 3.00, GETDATE()),
	   (10, 1.5, 1.5, GETDATE())
SELECT * FROM sc1.Table_ComputedColumns


-- Check properyties of computed columns
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'SellValue', 'IsComputed') AS 'Is computed column'
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'SellValue', 'IsDeterministic') AS 'Is deterministic'
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'SellValue', 'IsPrecise') AS 'Is precise'
;
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'Revenue', 'IsComputed') AS 'Is computed column'
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'Revenue', 'IsDeterministic') AS 'Is deterministic'
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'Revenue', 'IsPrecise') AS 'Is precise'
;
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'NonDeterminismValue', 'IsComputed') AS 'Is computed column'
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'NonDeterminismValue', 'IsDeterministic') AS 'Is deterministic'
SELECT COLUMNPROPERTY (OBJECT_ID('sc1.Table_ComputedColumns', 'U'), 'NonDeterminismValue', 'IsPrecise') AS 'Is precise'

