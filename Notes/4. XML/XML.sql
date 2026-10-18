
-- XML DATA

-- 1. Overview:
--	+ SQL Server provides native support for XML data.
--	+ XML can be stored in an xml data type column or variable.
--	+ XML instances can be typed (validated against an XML schema collection) or untyped.
--	+ Querying is supported through XQuery, based on XPath.
--	+ Supports bulk loading via OPENROWSET.
--	+ Enables conversion between relational and XML data.
--	+ XML columns can be compressed (SQL Server 2022+) and indexed.
--	+ Preserves document order, structure, namespace, and declarations.
--	+ Efficient for fine-grained queries (predicate evaluation).
--	+ Supports transactional modifications (insert/update/delete sections) of XML data.
--	+ Validation against XML schemas guarantees format correctness.
--	+ More flexible than relational structures when schemas change frequently.

-- 2. Storage options:
--	+ Native xml data type (fast parsing via PSVI).
--	+ Annotated schema (AXSD) → decomposes XML into relational columns (XML view).
--	+ Large object storage (nvarchar(max), varbinary(max)) → stores identical copy of XML.

-- 3. Typed XML:
--	+ Associated with an XML schema collection.
--	+ Schema can be bound to variables, parameters, or columns.
--	+ Provides validation constraints.
--	+ Stores type information for attributes/elements → improves query percision.
--	+ Facets: DOCUMENT (exactly one top-level element) vs CONTENT (zero/many top-level elements or text nodes).

-- 4. Encoding:
--	+ XML data stored/returned in UTF-16.
--	+ If source encoding is not Unicode and not declared, parsing errors may occur.
--	+ Explicit encoding can be declared in the XML header.

-- 5. XML indexes:
--	+ Improve query performance but add maintenance overhead.
--	+ Primary XML index: shredded representation (row per node).
--		- Stores node name, type, value, document order, path.
--		- Avoid runtime shredding.
--	+ Secondary XML indexes (built on primary):
--		- PATH index → speeds up path-based queries.
--		- VALUE index → speeds up value-based queries (full path is not specified or using wildcards, query with unkonw element/attribute names).
--		- PROPERTY index → speeds up queries using value() method in the SELECT statement.
--	+ Selective XML indexes → index only chosen paths/nodes for efficiency.

-- 6. XML Compression:
--	+ Compress XML data using Xpress algorithm.
--	+ XML indexes can also use data compression.

-- 7. XML Schemas (XSD):
--	+ XML schema collections hold multiple schemas for validation.
--	+ Define metadata and data type information for XML instances.
--	+ Components: ELEMENT, ATTRIBUTE, SIMPLE TYPE, COMPLEX TYPE, ATTRIBUTEGROUP, MODELGROUP.
--	+ SQL Server stores schema components, not the XML itself.

-- 8. FOR XML:
--	+ Converts rowset results into XML.
--	+ Modes:
--		- RAW(<element name>) → one element per row (<row> default).
--		- AUTO → nested XML based on table order.
--		- EXPLICIT → complex shapes (attributes + elements).
--		- PATH → simpler alternative to EXPLICIT, supports nesting.
--	+ Directives:
--		- XMLDATA → inline XDR schema.
--		- XMLSCHEMA → inline XSD schema.
--		- ELEMENTS → format columns as subelements.
--		- TYPE → return xml type instead of string.
--		- ROOT(<root name>) → add a top-level element (<root> default).
--		- BINARY BASE64 → encode binary data.
--		- XSINIL → create xsi:nill for NULL values.
--		- ABSENT → omit NULL values (default).

-- 9. OPENXML:
--	+ Parses in-memory XML into rowsets.
--	+ Uses sp_xml_preparedocument / sp_xml_removedocument for handling DOM tree of document.
--	+ Parameters:
--		- idoc (document handle).
--		- XPath expression (rowpattern).
--		- Rowset schema (WITH clause).
--	+ Mapping options:
--		- Flags: 1 (attribute-centric), 2 (element-centric), 3 (both), 8 (overflow), etc.
--		- ColPattern in WITH clause for flexible mapping.

-- 10. XML DML:
--	+ Extensions to XQuery for modifying XML.
--	Keywords:
--		- insert → add nodes (elements, attributes, comments, text, etc.).
--		- delete → remove nodes/attributes.
--		- replace value of → update node/attribute values (simple types only).

-- 11. XML Data Type Methods
--	+ SQL Server provides built-in methods on the xml data type to query and manipulate XML instances using XQuery.
--	Methods:
--	+ query(XQuery) → returns XML nodes (elements/attributes). Can also construct new XML fragments.
--	+ value(XQuery, SQLType) → extracts a scalar value from XML and returns it as a SQL type.
--		- Must return a singleton (one value only).
--	+ exist(XQuery) → returns:
--		- 1 if the query returns a non-empty result,
--		- 0 if empty,
--		- NULL if the XML instance is NULL.
--	+ modify(XML DML) → used in UPDATE statements to modify XML content (insert, delete, replace).
--	+ nodes(XQuery) AS Table(Column) → shreds XML into relational rowsets.
--		- Each row contains a logical copy of the XML instance with context node identified by XQuery.
--		- Typically used with CROSS APPLY, not standalone SELECT.

-- 12. XQuery and XPath
--	+ XQuery is the language used to query and construct XML in SQL Server.
--	+ Based on XPath, but extended with:
--		- Iteration and looping constructs.
--		- Ability to construct new XML instances.
--		- Functions for transformation and binding relational data.
--	+ Special functions:
--		- sql:column() → bind relational column values into XML.
--		- sql:variable() → bind SQL variables into XML.
--	+ Structure:
--		- Prolog → declaration environment for query (e.g., namespaces)
--		- Body → sequence of expressions to query or transform XML.




-- PRACTICE
USE AdventureWorks2025
GO




-- Create XML Schema collections
CREATE XML SCHEMA COLLECTION XSD1 
	AS N'<?xml version="1.0" encoding="UTF-16"?>
    <xsd:schema targetNamespace="schema1" xmlns="schema1" xmlns:schema1="schema1"
        elementFormDefault="qualified"
        attributeFormDefault="unqualified"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema">

        <xsd:complexType name="BonusItem">
            <xsd:choice minOccurs="0" maxOccurs="unbounded">
                <xsd:element name="Item1">
                    <xsd:complexType>
                        <xsd:attribute name="id" type="xsd:string" use="required"/>
                        <xsd:attribute name="quantity" type="xsd:integer" use="optional"/>
                    </xsd:complexType>
                </xsd:element>
                <xsd:element name="Item2">
                    <xsd:complexType>
                        <xsd:attribute name="id" type="xsd:string" use="required"/>
                        <xsd:attribute name="quantity" type="xsd:integer" use="optional"/>
                    </xsd:complexType>
                </xsd:element>
                <xsd:element name="Item3">
                    <xsd:complexType>
                        <xsd:attribute name="id" type="xsd:string" use="required"/>
                        <xsd:attribute name="quantity" type="xsd:integer" use="optional"/>
                    </xsd:complexType>
                </xsd:element>
            </xsd:choice>
        </xsd:complexType>

        <xsd:complexType name="ProductType">
            <xsd:sequence>
                <xsd:element name="ProductName" type="xsd:string"/>
                <xsd:element name="Price" type="xsd:decimal"/>
                <xsd:element name="Quantity" type="xsd:integer"/>
                <xsd:element name="Category" type="xsd:string"/>
                <xsd:element name="Promotion" type="xsd:boolean"/>
                <xsd:element name="BonusItems" type="schema1:BonusItem"/>
            </xsd:sequence>
        </xsd:complexType>

        <xsd:simpleType name="PaymentType">
            <xsd:restriction base="xsd:string">
                <xsd:enumeration value="cash"/>
                <xsd:enumeration value="card"/>
            </xsd:restriction>
        </xsd:simpleType>

        <xsd:element name="root">
            <xsd:complexType>
                <xsd:sequence>
                    <xsd:element name="Order" minOccurs="0" maxOccurs="unbounded">
                        <xsd:complexType>
                            <xsd:sequence>
                                <xsd:element name="Product" type="schema1:ProductType" minOccurs="1" maxOccurs="unbounded"/>
                            </xsd:sequence>
                            <xsd:attribute name="OrderID" type="xsd:integer" use="required"/>
                            <xsd:attribute name="OrderDate" type="xsd:dateTime" use="optional"/>
                            <xsd:attribute name="TotalPrice" type="xsd:decimal" use="optional"/>
                            <xsd:attribute name="PaymentType" type="schema1:PaymentType" use="optional"/>
                        </xsd:complexType>
                    </xsd:element>
                </xsd:sequence>
                <xsd:attribute name="ImportID" type="xsd:string" use="required"/>
            </xsd:complexType>
        </xsd:element>
    </xsd:schema>';
GO

CREATE XML SCHEMA COLLECTION XSD2 
    AS N'<xsd:schema targetNamespace="schema2a" xmlns="schema2a" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <xsd:element name="Element1" type="xsd:string" />
    </xsd:schema>
    <xsd:schema targetNamespace="schema2b" xmlns="schema2b" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <xsd:element name="Element2" type="xsd:integer" />
    </xsd:schema>'
GO




-- Specify constraints for XML data type column
CREATE OR ALTER FUNCTION dbo.afCheckExists_CustomerID(@var XML)
RETURNS Bit
AS BEGIN
	IF @var.exist('/Customer/@CustomerID') = 1 AND @var.exist('/Customer/CustomerName') = 1
        RETURN 1;
    RETURN 0;
END;
GO




-- Declare XML data type variable/parameter/column (with/without XSD, XML constraints)
DECLARE @xml1 XML(DOCUMENT XSD2); 
GO

DECLARE @xml2 XML(CONTENT XSD2); 
GO

CREATE OR ALTER PROCEDURE [dbo].[ProcX] @xml XML(XSD2) AS;
GO

IF OBJECT_ID('dbo.XMLDemo', 'U') IS NOT NULL 
	DROP TABLE dbo.XMLDemo
CREATE TABLE dbo.XMLDemo (
    ID Int Identity(1,1) NOT NULL PRIMARY KEY,
    Orders XML (DOCUMENT XSD1) NOT NULL DEFAULT CAST(N'<?xml version="1.0" encoding="UTF-16"?><root xmlns="schema1" ImportID="IMP001"></root>' AS XML),
    Customer XML CHECK(dbo.afCheckExists_CustomerID(Customer) = 1) NOT NULL DEFAULT CAST(N'<Customer CustomerID="0"><CustomerName></CustomerName></Customer>' AS XML) 
)
GO




-- Create primary/secondary XML indexes ON XML data type column
CREATE PRIMARY XML INDEX Idx_XMLDemo_Orders ON XMLDemo(Orders)
GO

CREATE XML INDEX Idx_XMLDemo_Orders_PATH ON XMLDemo(Orders)
USING XML INDEX Idx_XMLDemo_Orders
FOR PATH
GO

CREATE XML INDEX Idx_XMLDemo_Orders_VALUE ON XMLDemo(Orders)
USING XML INDEX Idx_XMLDemo_Orders
FOR VALUE
GO

CREATE XML INDEX Idx_XMLDemo_Orders_PROPERTY ON XMLDemo(Orders)
USING XML INDEX Idx_XMLDemo_Orders
FOR PROPERTY
GO




-- Instantiate XML data
DECLARE @xml1 XML(DOCUMENT XSD2); 
DECLARE @xml2 XML(CONTENT XSD2); 
SET @xml1 = CAST(N'<Element1 xmlns="schema2a">Content</Element1>' AS XML)
SET @xml2 = CAST(N'<Element1 xmlns="schema2a">Content</Element1><Element2 xmlns="schema2b">1</Element2>' AS XML)
GO

INSERT INTO dbo.XMLDemo(Orders, Customer)
VALUES(N'<?xml version="1.0" encoding="UTF-16"?>
    <root xmlns="schema1" xmlns:ns="schema1" ImportID="IMP001">
        <ns:Order OrderID="1" OrderDate="2026-03-29T09:30:00" TotalPrice="199.99" PaymentType="card">
            <Product>
                <ProductName>Wireless Mouse</ProductName>
                <Price>99.99</Price>
                <Quantity>2</Quantity>
                <Category>Electronics</Category>
                <Promotion>true</Promotion>
                <BonusItems>
                    <Item1 id="MOUSEPAD01" quantity="1"/>
                </BonusItems>
            </Product>
        </ns:Order>
        <ns:Order OrderID="2">
            <Product>
                <ProductName>Laptop</ProductName>
                <Price>170.00</Price>
                <Quantity>1</Quantity>
                <Category>Computers</Category>
                <Promotion>false</Promotion>
                <BonusItems />
            </Product>
            <Product>
                <ProductName>SmartPhone</ProductName>
                <Price>120.00</Price>
                <Quantity>1</Quantity>
                <Category>Phones</Category>
                <Promotion>false</Promotion>
                <BonusItems />
            </Product>
        </ns:Order>
    </root>',
    DEFAULT)
GO

SELECT DepartmentID, Name, GroupName, ModifiedDate 
FROM HumanResources.Department
FOR XML RAW, TYPE
GO

SELECT DepartmentID, Name, GroupName, ModifiedDate 
FROM HumanResources.Department
FOR XML AUTO, TYPE
GO

DECLARE @s varchar(MAX) = 
N'
<products>
  <product id="1">
    <name>Café au lait</name>
    <price>2.50</price>
  </product>
  <product id="2">
    <name>Crème brûlée</name>
    <price>5.00</price>
  </product>
</products>'
SELECT CAST(
	CAST(('<?xml version="1.0" encoding="iso8859-1"?>' + @s) AS VARBINARY (MAX)) 
	AS XML) AS [xml data with encoding ISO‑8859‑1]
GO

SELECT BulkColumn AS [binary data stream]
FROM OPENROWSET(
	BULK 'D:\Projects\SQL-Projects\Notes\4. XML\SampleData1.txt',
	SINGLE_BLOB
) AS x
GO

SELECT CONVERT(XML, BulkColumn, 2) AS [xml data with DTD]
FROM OPENROWSET(
	BULK 'D:\Projects\SQL-Projects\Notes\4. XML\SampleData2.txt',
	SINGLE_BLOB
) AS x
GO




-- Get information about XML schemas and schema collections
SELECT 
    'Get namespaces of a collection' AS [content],
    XSC.name AS [collection name],
    XSN.name AS [schema name/namespace],
    NULL AS XSD
FROM sys.xml_schema_collections XSC
INNER JOIN sys.xml_schema_namespaces XSN ON XSN.xml_collection_id = XSC.xml_collection_id
WHERE XSC.name = 'XSD1'
UNION ALL
SELECT 
    N'Get contents of a collection',
    N'XSD1',
    NULL,
    XML_SCHEMA_NAMESPACE (N'dbo', N'XSD1')
UNION ALL
SELECT 
    N'Output a specified schema from an XML schema collection',
    N'XSD2',
    N'schema2b',
    XML_SCHEMA_NAMESPACE(N'dbo', N'XSD2', 'schema2b')
GO

-- Get XSD of XML columns of table
SELECT	
	tb.name AS [Table name],
	c.name AS [Column name],
	ISNULL(xsc.name, '') AS [XSD collection name],
	ISNULL(xsn.name, '') AS [XSD namespace],
	XML_SCHEMA_NAMESPACE(SCHEMA_NAME(tb.schema_id), xsc.name, xsn.name) AS [XSD]
FROM sys.columns c
INNER JOIN sys.tables tb ON tb.object_id = c.object_id
INNER JOIN sys.types t ON t.system_type_id = c.system_type_id AND t.user_type_id = c.user_type_id AND t.name = 'xml'
LEFT JOIN sys.xml_schema_collections xsc ON xsc.xml_collection_id = c.xml_collection_id
LEFT JOIN sys.xml_schema_namespaces xsn ON xsn.xml_collection_id = xsc.xml_collection_id
WHERE tb.object_id = OBJECT_ID('Production.ProductModel', 'U');
GO




-- Get information about XML indexes
SELECT 
	OBJECT_NAME(object_id) AS [table],
	name AS [index name],
	type_desc AS [index type]
FROM sys.indexes
WHERE [type] = 3
GO

SELECT 
	OBJECT_NAME(object_id) AS [table],
	name AS [index name],
	CASE
		WHEN secondary_type IS NULL THEN N'True'
		ELSE N'False'
	END AS [is primary xml index],
	CASE secondary_type
		WHEN 'P' THEN N'PATH'
		WHEN 'R' THEN N'PROPERTY'
		WHEN 'V' THEN N'VALUE'
		ELSE N''
	END AS [secondary index type]
FROM sys.xml_indexes;
GO




-- FOR XML
-- WITH NAMESPACE
WITH XMLNAMESPACES ('uri' AS ns1)
SELECT
	ProductID AS 'ns1:ProductID',
	Name AS 'ns1:Name',
	Color AS 'ns1:Color'
FROM Production.Product
WHERE ProductID IN (316, 317)
FOR XML RAW ('ns1:Prod'), ELEMENTS XSINIL, ROOT;
GO

-- RAW mode
DECLARE @x nvarchar(100) =
(
    SELECT 
        ID,
        Orders.query('
        declare namespace ns="schema1";
        //ns:Order') AS Orders,
        Customer
    FROM XMLDemo root
    FOR XML RAW, TYPE
).value('
    declare namespace ns="schema1";
    (/row/Orders/ns:Order[@OrderID="2"][1]/ns:Product[1]/ns:ProductName[1]/text())[1]', 
    'nvarchar(100)');
SELECT @x AS [Name of the first product of Order with OrderID = "2"];
GO

-- AUTO mode
SELECT 
	IndividualCustomer.CustomerID, 
	IndividualCustomer.Name,
	IndividualCustomer.NoOfOrders,
	SOH.SalesOrderID,
	SOD.SalesOrderDetailID,
	SOD.LineTotal,
	SOD.ProductID,
	SOD.OrderQty,
	P.Name
FROM (
	SELECT 
		C.CustomerID, 
		P.FirstName + ' ' + P.LastName AS Name,
		COUNT(*) AS NoOfOrders
	FROM Sales.Customer AS C
	INNER JOIN Person.Person AS P ON p.BusinessEntityID = C.PersonID
	INNER JOIN Sales.SalesOrderHeader SOH ON SOH.CustomerID = C.CustomerID
	WHERE C.CustomerID IN (29672, 29734)
	GROUP BY C.CustomerID, P.FirstName, P.LastName
) AS IndividualCustomer
INNER JOIN Sales.SalesOrderHeader SOH ON SOH.CustomerID = IndividualCustomer.CustomerID
INNER JOIN Sales.SalesOrderDetail AS SOD ON SOD.SalesOrderID = SOH.SalesOrderID
INNER JOIN Production.Product AS P ON P.ProductID = SOD.ProductID
ORDER BY IndividualCustomer.CustomerID, SOh.SalesOrderID
FOR XML AUTO, ROOT;
GO

-- Nested AUTO mode
SELECT XmlCol.query('<Root> { /* } </Root>')
FROM (
	SELECT 
		(
			SELECT 
				TOP 2 SalesOrderID, SalesPersonID, CustomerID,
				(
					SELECT TOP 3 SalesOrderID, ProductID, OrderQty, UnitPrice
					FROM Sales.SalesOrderDetail
					WHERE SalesOrderDetail.SalesOrderID = SalesOrderHeader.SalesOrderID
					FOR XML AUTO, TYPE
				)
			FROM Sales.SalesOrderHeader
			WHERE Sales.SalesOrderHeader.SalesOrderID = SalesOrder.SalesOrderID
			FOR XML AUTO, TYPE
		),
		(
			SELECT * FROM 
			(
				SELECT SP.BusinessEntityID, E.NationalIDNumber
				FROM Sales.SalesPerson SP
				INNER JOIN HumanResources.Employee E ON E.BusinessEntityID = SP.BusinessEntityID
			) AS SalesPerson
			WHERE SalesPerson.BusinessEntityID = SalesOrder.SalesPersonID
			FOR XML AUTO, TYPE
		)
	FROM (
		SELECT SOH.SalesOrderID, SOH.SalesPersonID
		FROM Sales.SalesOrderHeader SOH
		INNER JOIN Sales.SalesPerson SP ON SP.BusinessEntityID = SOH.SalesPersonID
	) AS SalesOrder
	WHERE SalesOrder.SalesOrderID IN (43669, 43670)
	ORDER BY SalesOrder.SalesOrderID
	FOR XML AUTO, TYPE
) AS T(XmlCol);
GO

-- PATH mode
SELECT 
	N'Columns without name' AS [content],
	CAST((
		SELECT 1, ', ', 2, ', ', 3, ', ', 4, ', ', 5, ', ', 6
		FOR XML PATH('')
	) AS XML) AS [XML PATH]
UNION ALL
SELECT
	N'Complex query',
	CAST((
		SELECT 
			ProductModelID AS '@ProductModelID',
			(
				SELECT ProductID AS 'data()'
				FROM Production.Product
				WHERE Production.Product.ProductModelID = Production.ProductModel.ProductModelID
				FOR XML PATH('')
			) AS '@ProductIDs',
			[Name] AS 'Nested1/Nested2/@Name',
			[Name] AS 'Nested1/Nested2/Name',
			Instructions.query(
				'declare namespace MI="http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/ProductModelManuInstructions";
				/MI:root/MI:Location
				') AS ManuWorkCenterInformation,
			Instructions.query(
				'declare namespace MI="http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/ProductModelManuInstructions";
				/MI:root/MI:Location[1]
				') -- query with no column name, same with wildcard character '*'
		FROM Production.ProductModel
		WHERE ProductModelID = 7
		FOR XML PATH, ELEMENTS XSINIL
	) AS XML)
UNION ALL
SELECT 
	N'Complex query',
	CAST((
		SELECT 
			P.BusinessEntityID AS '@PersonID',
			'Example of using node tests such as text(), comment(), processing-instruction()' AS 'comment()',
			'Some pi' AS 'processing-instruction(PI)',
			P.FirstName AS 'Name/First/text()',
			p.MiddleName AS 'Name/Middle',
			p.LastName AS 'Name/Last',
			ISNULL(P.FirstName + ' ', '') + ISNULL(P.MiddleName + ' ', ' ') + ISNULL(P.LastName, '') AS 'Fullname',
			A.AddressLine1 AS 'Address/AddressLine1',
			A.AddressLine2 AS 'Address/AddressLine2',
			A.City AS 'Address/City'
		FROM Person.Person P
		INNER JOIN Person.BusinessEntityAddress B ON B.BusinessEntityID = P.BusinessEntityID
		INNER JOIN Person.Address A ON A.AddressID = B.AddressID
		WHERE P.BusinessEntityID IN (1, 2)
		FOR XML PATH, ELEMENTS XSINIL
	) AS XML)
GO




-- OPENXML
CREATE OR ALTER PROCEDURE [dbo].[OPENXMLDemo1]
AS
BEGIN
	-- Create tables for later population using OPENXML.
	IF OBJECT_ID('[dbo].[CustomersDemo]', 'U') IS NOT NULL
		DROP TABLE [dbo].[CustomersDemo]
	IF OBJECT_ID('[dbo].[OrdersDemo]', 'U') IS NOT NULL
		DROP TABLE [dbo].[OrdersDemo]

	CREATE TABLE [dbo].[CustomersDemo] (CustomerID Varchar(20) PRIMARY KEY,
					ContactName Varchar(20),
					CompanyName Varchar(20));
	CREATE TABLE [dbo].[OrdersDemo] (CustomerID varchar(20), OrderDate Datetime);
	
	DECLARE @docHandle Int;
	DECLARE @xmlDocument Nvarchar(MAX); -- or xml type
	SET @xmlDocument = 
	N'<ROOT>
		<Customers CustomerID="XYZAA" ContactName="Joe" CompanyName="Company1">
			<Orders CustomerID="XYZAA" OrderDate="2026-03-31T00:00:00" />
			<Orders CustomerID="XYZAA" OrderDate="2026-03-30T00:00:00" />
		</Customers>
		<Customers CustomerID="XYZBB" ContactName="Steve" CompanyName="Company2">
			No Orders yet!
		</Customers>
	</ROOT>';

	EXEC sp_xml_preparedocument @docHandle OUTPUT, @xmlDocument;

	-- Use OPENXML to provide rowset consisting of customer data.
	INSERT [dbo].[CustomersDemo]
	SELECT * 
	FROM OPENXML(@docHandle, N'/ROOT/Customers')
	WITH [dbo].[CustomersDemo];

	-- Use OPENXML to provide rowset consisting of order data.
	INSERT [dbo].[OrdersDemo]
	SELECT *
	FROM OPENXML(@docHandle, N'//Orders')
	WITH [dbo].[OrdersDemo];

	-- Remove the internal representation of the XML document.
	EXEC sp_xml_removedocument @docHandle

	SELECT * FROM [dbo].[CustomersDemo]
	SELECT * FROM [dbo].[OrdersDemo]
END
GO

CREATE OR ALTER PROCEDURE [dbo].[OPENXMLDemo2]
AS
BEGIN
	DECLARE @XmlDocumentHandle Int;
	DECLARE @XmlDocument Nvarchar(1000);
	SET @XmlDocument =
		N'<ROOT>
			<Customer>
				<CustomerID>VINET</CustomerID>
				<ContactName>Paul Henriot</ContactName>
				<Order OrderID="10248" CustomerID="VINET" EmployeeID="5" OrderDate="1996-07-04T00:00:00">
					<OrderDetail ProductID="11">
						<Quantity>12</Quantity>
						<Product ProductName="Phone" />
					</OrderDetail>
					<OrderDetail ProductID="42">
						<Quantity>10</Quantity>
						<Product ProductName="Watch" />
					</OrderDetail>
					Customer was very satisfied
				</Order>
			</Customer>
			<Customer>
				<CustomerID>LILAS</CustomerID>
				<ContactName>Carlos Gonzalez</ContactName>
				<Order OrderID="10283" CustomerID="LILAS" EmployeeID="3" OrderDate="1996-08-16T00:00:00">
					<OrderDetail ProductID="72" TotalPayment="1000">
						<Quantity>3</Quantity>
						<Product ProductName="Laptop" />
					</OrderDetail>
					Happy Customer
				</Order>
			</Customer>
		</ROOT>';

	-- Create an internal representation of the XML document.
	EXEC sp_xml_preparedocument @XmlDocumentHandle OUTPUT, @XmlDocument;

	-- Execute a SELECT statement using OPENXML rowset provider.
	SELECT *
	FROM OPENXML (@XmlDocumentHandle, '/ROOT/Customer/Order/OrderDetail', 3)
	WITH (CustomerID	Varchar(10) '../../CustomerID',
		  ContactName	Varchar(20)	'../../ContactName',
		  OrderID		Int			'../@OrderID',
		  OrderDate		Datetime	'../@OrderDate',
		  Comment		ntext		'../text()',
		  ProductID		Int,
		  Quantity		Int,
		  ProductName	Varchar(20)	'Product/@ProductName');

	-- Execute a SELECT statement using a rowpattern ending with an attribute
	SELECT *
	FROM OPENXML (@XmlDocumentHandle, '/ROOT/Customer/Order/OrderDetail/@ProductID')
	WITH (ProductID Int '.',
		  TotalPayment Decimal(19,4) '../@TotalPayment',
		  Quantity Int '../Quantity',
		  ProductName Varchar(20) '../Product/@ProductName');

	-- Execute a SELECT statement returns all the columns in the edge table.
	WITH CTE_Edge_Table AS (
		SELECT id, parentid, nodetype, localname, prefix, namespaceuri, datatype, prev, text
		FROM OPENXML (@XmlDocumentHandle, '/ROOT/Customer')
	)
	SELECT [text] AS [Edge table - Customer ID]
	FROM CTE_Edge_Table
	WHERE localname = '#text' AND parentid IN (SELECT id FROM CTE_Edge_Table WHERE localname = 'CustomerID' AND nodetype = 1);

	-- Execute a SELECT statement using XML data type in the WITH clause
	SELECT *
	FROM OPENXML (@XmlDocumentHandle, '/ROOT/Customer', 10)
	WITH (CustomerID	Varchar(10),
		  xmlCustomerID	XML 'CustomerID',
		  OverFlow XML '@mp:xmltext');

	EXEC sp_xml_removedocument @XmlDocumentHandle;
END
GO

EXEC [dbo].[OPENXMLDemo1]
GO

EXEC [dbo].[OPENXMLDemo2]
GO




-- XML Modification
CREATE OR ALTER PROCEDURE [dbo].[XMLDMLDemo]
AS
BEGIN
	DECLARE @myDoc XML;
	SET @myDoc = 
		N'<Root>
			<ProductDescription ProductID="1" ProductName="Road Bike">
				<Features>
				</Features>
			</ProductDescription>
		</Root>';
	

	-- INSERT
	-- Insert first feature child
	SET @myDoc.modify(
		'insert <Maintenance>3 year parts and labor extended maintenance is available</Maintenance>
		into (/Root/ProductDescription/Features)[1]'
	);

	-- Insert second feature at the first position
	SET @myDoc.modify(
		'insert <Warranty>1 year parts and labor</Warranty>
		as first
		into (/Root/ProductDescription/Features)[1]'
	);

	-- Insert third feature at the last position
	SET @myDoc.modify(
		'insert <Material>Aluminum</Material>
		as last
		into (/Root/ProductDescription/Features)[1]'
	);

	-- Insert fourth feature before the feature Material
	SET @myDoc.modify(
		'insert <BikeFrame>Strong long lasting</BikeFrame>
		before (/Root/ProductDescription/Features/Material)[1]'
	);

	-- Insert multiple elements after the feature BikeFrame
	DECLARE @newFeatures XML;
	SET @newFeatures =
		N'<Warranty2>1 year parts and labor</Warranty2>
		<Maintenance2>3 year parts and labor extended maintenance is available</Maintenance2>';
	SET @myDoc.modify(
		'insert sql:variable("@newFeatures")
		after (/Root/ProductDescription/Features/BikeFrame)[1]'
	)

	-- Insert attributes into a document
	DECLARE @price Money = 20.00;
	SET @myDoc.modify(
		'insert (
			attribute Price {sql:variable("@price")},
			attribute Quantity {"5"},
			attribute State {"0"}
		)
		into (/Root/ProductDescription[@ProductID=1])[1]'
	);

	-- Insert a comment node after features node
	SET @myDoc.modify(
		'insert <!-- some comment -->
		after (/Root/ProductDescription/Features)[1]'
	);

	-- Insert a processing instruction at the start of the document
	SET @myDoc.modify(
		'insert <?Program = "Instructions.exe" ?>
		before (/Root)[1]'
	);

	-- Insert data using CDATA section
	--SET @myDoc.modify(
	--	'insert <![CDATA[ <notxml> as text </notxml> or cdata ]]>
	--	after (/Root/ProductDescription/Features)[1]'
	--);

	-- Insert text node with line breaker '&#x0A;'
	SET @myDoc.modify(
		'insert text{"&#x0A;Product Catalog Description&#x0A;"}
		as last into (/Root)[1]'
	);

	-- Insert data based on an if condition statement
	SET @myDoc.modify(
		'insert
		if (/Root/ProductDescription[@ProductID=1])
		then element ProductCategory { "Bike" }
		else ()
		as first into (/Root/ProductDescription[@ProductID=1])[1]'
	);

	SELECT @myDoc;


	-- DELETE
	-- Delete an attribute
	SET @myDoc.modify(
		'delete /Root/ProductDescription/@Quantity'
	);

	-- Delete an element ProductCategory
	SET @myDoc.modify(
		'delete /Root/ProductDescription/ProductCategory[1]'
	);

	-- Delete the second Features element
	SET @myDoc.modify(
		'delete /Root/ProductDescription/Features/*[2]'
	);

	-- Delete text node
	SET @myDoc.modify(
		'delete /Root/text()'
	);

	-- Delete all processing instructions
	SET @myDoc.modify(
		'delete //processing-instruction()'
	)

	SELECT @myDoc;


	-- UPDATE
	-- Update text in the warranty feature
	SET @myDoc.modify(
		'replace value of (/Root/ProductDescription/Features/Warranty[1]/text())[1]
		with "2 year parts and labor"'
	);

	-- Update attribute value
	SET @myDoc.modify(
		'replace value of (/Root/ProductDescription/@Price)[1]
		with "100.0"'
	);

	-- Update based on if condition statement
	SET @myDoc.modify(
		'replace value of (/Root[1]/ProductDescription[1]/@State)[1]
		with (
			if (count(/Root[1]/ProductDescription[1]/Features/*) > 3) then 
				"1"
			else 
				"2"
		)'
	);

	SELECT @myDoc;
END
GO

EXEC [dbo].[XMLDMLDemo];
GO




-- XML data type methods (with XQuery expression and XQuery functions)
WITH XMLNAMESPACES (
	'http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/ProductModelDescription' AS PD,
	'http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/ProductModelWarrAndMain' AS wm,
	'http://www.w3.org/1999/xhtml' AS html
)
SELECT
	ProductModelID,
	CatalogDescription AS [origin XML],
	CatalogDescription.query(
		'/PD:ProductDescription/PD:Summary'
	) AS [query node],
	CatalogDescription.query(
		'<Product ProductModelID="{/PD:ProductDescription[1]/@ProductModelID}" />
	') AS [query construct XML],
	CatalogDescription.value(
		'(/PD:ProductDescription/@ProductModelID)[1]', 'Int'
	) AS [value ProductModelID],
	CatalogDescription.value(
		'(/PD:ProductDescription/@ProductModelName)[1]', 'Varchar(50)'
	) AS [value ProductModelName],
	CatalogDescription.value(
		'(/PD:ProductDescription/PD:Summary/html:p/text())[1]', 'Varchar(MAX)'
	) AS [value Summary>p content]
FROM Production.ProductModel
WHERE CatalogDescription.exist('/PD:ProductDescription/PD:Features/wm:Warranty') = 1
	AND CatalogDescription.exist('/PD:ProductDescription[xs:integer(@ProductModelID)=sql:column("ProductModelID")]') = 1;
GO

DECLARE @x XML = '<Somedate date="2002-01-01Z">2002-01-01Z</Somedate>';
DECLARE @d Nvarchar(12) = '2002-01-01Z';
SELECT @x.exist('/Somedate[(@date cast as xs:date?) eq xs:date("2002-01-01Z")]') AS [exist eq],
	@x.exist('/Somedate[(text()[1] cast as xs:date ?) = xs:date(sql:variable("@d"))]') AS [exist =],
	@x.exist('/Somedate[not(OtherElements)]') AS [exist not],
	@x.query('/Somedate[not(OtherElements)]')
GO

DECLARE @x XML = 
	N'<Root1>  
		<Root2>
			<Location LocationID="10">  
				<step>Step101</step>  
				<step>Step102</step>  
			</Location>  
			<Location LocationID="20">  
				<step>Step201</step>
				<step>Step202</step>
			</Location>  
			<Location LocationID="30">  
				<step>Step301</step>
				<step>Step302</step>
			</Location>  
		</Root2>
	</Root1>';
SELECT
	@x AS [original XML],
	T.c.query('/') AS [nodes - logical copy of XML],
	T.c.query('..') AS [nodes Location context - direct parent accessor Root2],
	T.c.query('*') AS [nodes Location context - all child elements],
	T.c.query('.') AS [nodes Location context - first location],
	T.c.query('../*') AS [nodes Location context - all child elements of parent Root2]
FROM @x.nodes('/Root1/Root2/Location') AS T(c)
GO

WITH XMLNAMESPACES (
	'http://schemas.microsoft.com/sqlserver/2004/07/adventure-works/ProductModelManuInstructions' AS MI
)
SELECT 
	ProductModelID,
	T1.Locations.value('./@LocationID', 'Int') AS LocationID,
	T2.steps.query('.') AS Step
FROM Production.ProductModel
CROSS APPLY Instructions.nodes('/MI:root/MI:Location') AS T1(Locations)
CROSS APPLY T1.Locations.nodes('./MI:step') AS T2(steps)
WHERE ProductModelID = 7
GO
