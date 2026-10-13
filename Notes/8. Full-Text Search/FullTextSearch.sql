
-- FULL TEXT SEARCH

-- 1. Full-Text Search enables full-text queries against character-based data.

-- 2. It is an optional component of the SQL Server Database Engine, available only if enabled.

-- 3. To add the feature to an existing instance: SQL Server Installation Center → Add features to an existing installation.

-- 4. Full-text indexes support all character-based data types, including binary types that represent text files.

-- 5. Full-text queries perform linguistic searches against text data, following the rules of a specified language.

-- 6. A table can be full-text indexed only if it has a unique, single-column, non-nullable index.
--	+ Choosing a small index (e.g., 4-byte integer) reduces resource usage.

-- 7. By default, the system stoplist is applied to every full-text index.
--	+ Custom stoplists can be created and associated with specific indexes.

-- 8. Updating a full-text index immediately after each change can be resource-intensive.
--	+ Consider manual or scheduled change tracking updates.

-- 9. To reduce index fragmentation, rebuild or reorganize the full-text index.

-- 10. Compared with LIKE, Full-Text Search is faster and works on both character patterns and formatted binary data.

-- 11. Full-text queries support the following term types:
--	+ Simple: specific words or phrases.
--	+ Prefix: words or phrases where tokens begin with the specified prefix.
--		- Phrase prefixes can also match derivative or inflectional forms of each token.
--	+ Generation: inflectional forms of a word (FORMSOF(INFLECTIONAL)).
--	+ Proximity: words or phrases near each other (NEAR).
--	+ Thesaurus: synoyms defined in thesaurus files.
--	+ Weighted: terms with assigned relevance weights.
--	+ Queries can combine multiple terms, increasing complexity and resource usage.

-- 12. Full-Text Search architecture:
--	+ SQL Server process (sqlserver.exe):
--		- Query processor: compiles and executes queries, cooperates with Full-Text Engine for full-text queries.
--		- Full-Text Engine: compiles and executes full-text queries, applies thesaurus and stoplist rules.
--		- Thesaurus files: contain synonyms of search terms.
--		- Stoplist objects: contain common words excluded from searches.
--		- Full-text gatherer: schedules and drives population of full-text indexes.
--		- Index writer (indexer): build structures to store index tokens.
--		- Filter daemon manager: monitors the filter daemon host.
--	+ Filter daemon host process (fdhost.exe)
--		- Runs seperately under FDHOST launcher service, started by Full-Text Engine.
--		- Protocol handler: gathers data and passes it to the host.
--		- Filters: extract text from binary formats (.doc, .xls, .xml, etc.), remove formatting.
--		- Word breakers and stemmers: tokenize text and apply language-specific stemming.

--	13. Full-Text indexing process:
--	+ Full-Text Engine pushes batches of data into memory and starts the filter daemon host.
--	+ The host filters and word-breaks the data into tokens (keywords).
--	+ Optional processing removes stopwords and normalizes tokens.
--	+ Tokens are stored in full-text index fragments.
--	+ When population completes, fragments are merged into a master full-text index.

-- 14. Full-Text querying process:
--	+ Full-text portions of queries are passed to the Full-Text Engine.
--	+ Engine performs word breaking, thesaurus expansion, stemming, and stopword processing.
--	+ Queries are converted into SQL operators, primarily stemming table-valued functions (STVFs).
--	+ STVFs search full-text indexes for matches during execution.

-- 15. Full-Text index structure:
--	+ Full-text indexes may consist of multiple fragments; ideally, one master fragment is persisted.
--	+ A fragment is an internal table storing inverted index data, with columns:
--		- Keyword: token extracted at indexing time.
--		- ColId: column ID for the indexed column.
--		- DocId: document ID referencing the row in the table.
--		- Occurrence: position of the keyword within the document.
--	+ Each row of indexed text data is associated with a unique DocId.






-- PRACTICE
USE AdventureWorks2025;
GO


-- Verify if Full-Text Search is available
SELECT SERVERPROPERTY('IsFullTextInstalled') AS IsFullTextInstalled;


-- Create full-text catalog
CREATE FULLTEXT CATALOG AdvWksDocFTCat;
GO


-- Check accent-sensitivity property of a catalog
SELECT FULLTEXTCATALOGPROPERTY('AdvWksDocFTCat', 'AccentSensitivity') AS IsAccentSensitivity;
GO


-- Create a custom stoplist
CREATE FULLTEXT STOPLIST myStoplist FROM SYSTEM STOPLIST;
ALTER FULLTEXT STOPLIST myStoplist ADD 'and' LANGUAGE 'Spanish';
ALTER FULLTEXT STOPLIST myStoplist ADD 'and' LANGUAGE 'French';
GO


-- Create a unique, single-column, non-nullable index on a full-text indexed table
CREATE UNIQUE INDEX Idx_FT_Document_DocumentNode ON Production.Document(DocumentNode);
GO


-- Create full-text index on the column
CREATE FULLTEXT INDEX ON Production.Document 
(
	Document						-- Full-text index column name
		TYPE COLUMN FileExtension	-- Name of column that contains file type information
		Language 2057				-- 2057 is the LCID for British English
)
KEY INDEX Idx_FT_Document_DocumentNode ON AdvWksDocFTCat	-- Unique index
WITH CHANGE_TRACKING AUTO,									-- Population type
	 STOPLIST = myStoplist;									-- Stoplist that associated with
GO


-- Drop full-text index
DROP FULLTEXT INDEX ON Production.Document
GO


-- Rebuild/Reorganize index
ALTER FULLTEXT CATALOG AdvWksDocFTCat REBUILD WITH ACCENT_SENSITIVITY = ON;
ALTER FULLTEXT CATALOG AdvWksDocFTCat REORGANIZE;
GO





-- QUERY

-- Prepare full-text index for demo
CREATE UNIQUE INDEX Idx_FT_Product_ProductID ON Production.Product(ProductID);
CREATE FULLTEXT INDEX ON Production.Product 
(
	Name
		Language 2057
)
KEY INDEX Idx_FT_Product_ProductID ON AdvWksDocFTCat
WITH CHANGE_TRACKING AUTO;
GO

CREATE UNIQUE INDEX Idx_FT_ProductDescription_ProductDescriptionID ON Production.ProductDescription(ProductDescriptionID);
CREATE FULLTEXT INDEX ON Production.ProductDescription
(
	Description
		Language 2057
)
KEY INDEX Idx_FT_ProductDescription_ProductDescriptionID ON AdvWksDocFTCat
WITH CHANGE_TRACKING AUTO;
GO

CREATE UNIQUE INDEX Idx_FT_Address_AddressID ON Person.Address(AddressID);
CREATE FULLTEXT INDEX ON Person.Address
(
	AddressLine1
		Language 2057
)
KEY INDEX Idx_FT_Address_AddressID ON AdvWksDocFTCat
WITH CHANGE_TRACKING AUTO;
GO



-- Find products that contain the word "Mountain"
SELECT Name, ListPrice
FROM Production.Product
WHERE CONTAINS(Name, 'Mountain');
GO


-- Search for all documents that contain words related to "vital safety components"
SELECT Title
FROM Production.Document
WHERE FREETEXT (Document, 'vital safety components')


-- Query product description that contains the word "aluminum" near either the word "light" or the word "lightweight" with rank of 2 or higher.
SELECT 
	FT_TBL.ProductDescriptionID,
	FT_TBL.Description,
	KEY_TBL.Rank
FROM Production.ProductDescription AS FT_TBL 
INNER JOIN CONTAINSTABLE (
	Production.ProductDescription, 
	Description, 
	'(light NEAR aluminum) OR (lightweight NEAR aluminum)'
) AS KEY_TBL ON KEY_TBL.[KEY] = FT_TBL.ProductDescriptionID
WHERE KEY_TBL.RANK > 2
ORDER BY KEY_TBL.RANK DESC;
GO


-- Search for product description that contain the word "cats", the phrase "hunting mice", and any word beginning with "dog" (such as "dog" or "dogs"), 
--	with all of them appearing in order and within three intervening non-search terms.
-- Ex: Cats enjoy hunting mice``, but avoid dogs``. 
--	   Cats enjoy hunting mice``, but avoid dog``.
SELECT 
	ProductDescriptionID,
	Description
FROM Production.ProductDescription
WHERE CONTAINS(Description, 'NEAR((cats, "hunting mice", "dog*"), 3, TRUE)');
GO


-- Query product description that contains the word related to "perfect all-around bike" and rank them
SELECT 
	KEY_TBL.RANK,
	FT_TBL.Description
FROM Production.ProductDescription AS FT_TBL
INNER JOIN FREETEXTTABLE (
	Production.ProductDescription,
	Description,
	'perfect all-around bike'
) AS KEY_TBL ON KEY_TBL.[KEY] = FT_TBL.ProductDescriptionID
ORDER BY KEY_TBL.RANK DESC
GO


-- Search for product descriptions that contain any word whose spelling begin with the prefix "top"
SELECT Description, ProductDescriptionID
FROM Production.ProductDescription
WHERE CONTAINS (Description, '"top*"');
GO


-- Search for product descriptions that contain any inflectional form of "extract" followed by any word starting with "word".
-- Ex: the results could be "extract word", "extracts word", "extracting words", "extracted words"
SELECT Description, ProductDescriptionID
FROM Production.ProductDescription
WHERE CONTAINS (Description, '"extract word*"');
GO


-- Search for any form of the word "foot" (e.g. "foot", "feet", and so on) in the Comments column
SELECT Comments, ReviewerName
FROM Production.ProductReview
WHERE CONTAINS (Comments, 'FORMSOF(INFLECTIONAL, "foot")');
GO


-- Search for synonyms of the word "car" in the Comments column
SELECT Comments, ReviewerName
FROM Production.ProductReview
WHERE CONTAINS (Comments, 'FORMSOF(THESAURUS, "car")');
GO
SELECT Comments, ReviewerName
FROM Production.ProductReview
WHERE FREETEXT (Comments, 'car');
GO