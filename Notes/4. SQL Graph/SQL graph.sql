

-- GRAPH DATABASE
-- 1. Purpose:
--	+ Designed to model complex many-to-many relationships more naturally than traditional relational tables.
-- 2. Core concepts:
--	+ Nodes represent entities (e.g., Person, Product).
--	+ Edges represent relationships between nodes (e.g., FriendOf, Purchased).
-- 3. Unique features:
--	+ Edges can have attributes/properties (e.g., relationship strength, date).
--	+ A single edge can connect multiple nodes.
--	+ Supports pattern matching and multi-hop navigation.
--	+ Enables transitive closure and polymorphic queries.
-- 4. Node tables:
--	+ Each node table has an implicit pseudo-column: $node_id.
--	+ $node_id is automatically generated (combination of object ID + bigint).
--	+ SQL Server creates a unique nonclustered index on $node_id.
--	+ $node_id cannot be inserted or updated manually.
--	+ Selecting $node_id returns a JSON-like representation, with column name formatted as [$node_id_<unqiue suffix>].
-- 5. Edge tables:
--	+ Include three pseudo-columns: $edge_id, $from_id, $to_id.
--	+ $edge_id uniquely identifies an edge (object ID + bigint).
--	+ $from_id = $node_id of the source node.
--	+ $to_id = $node_id of the target node.
--	+ SQL Server creates unique nonclustered indexes in these columns.
--	+ $edge_id cannot be inserted or updated manually.
-- 6. Metadata views:
--	+ sys.tables → column is_node, is_edge identify graph tables.
--	+ sys.columns → columns graph_type, graph_type_desc list graph column types.
-- 7. MATCH function:
--	+ Used in WHERE clauses for pattern matching and traversal.
--	+ Defines paths from one node to another via edges, following arrow direction.
-- 8. SHORTEST_PATH function:
--	+ Recursively searches a graph until a condition is satisfied.
--	+ Path definition includes source node, edges, and nodes (FOR PATH keyword).
--	+ Arbitrary length patterns:
--		+ '+' → traverse until shortest path found.
--		+ '{1,n}' → repeat 1 to n times, stop at shortest path.
--	+ Useful path functions:
--		+ LAST_NODE → merge paths ending at the same node.
--		+ STRING_AGG → concatenate node values with a separator.
--		+ LAST_VALUE → return last node value in path.
--		+ SUM → sum attributes along path.
--		+ COUNT → count non-null attributes along path.
--		+ MIN → minimum attribute value along path.
--		+ MAX → maximum attribute value along path.

-- CREATE DATABASE
IF NOT EXISTS (SELECT * FROM sys.databases WHERE NAME = 'graphdemo')
	CREATE DATABASE GraphDemo;
GO

USE GraphDemo;
GO

-- CREATE NODE TABLES
CREATE TABLE Person (
	ID Integer PRIMARY KEY,
	name Varchar(100)
) AS NODE;

CREATE TABLE Restaurant (
	ID Integer NOT NULL,
	name Varchar(100),
	city Varchar(100)
) AS NODE;

CREATE TABLE City (
	ID Integer PRIMARY KEY,
	name Varchar(100),
	stateName Varchar(100)
) AS NODE;

-- CREATE EDGE TABLES
CREATE TABLE likes (rating Integer) AS EDGE;
CREATE TABLE friendOf AS EDGE;
CREATE TABLE livesIn AS EDGE;
CREATE TABLE locatedIn AS EDGE;

-- INSERT DATA INTO NODE TABLES
INSERT INTO Person (ID, name)
VALUES (1, 'John'), (2, 'Mary'), (3, 'Alice'), (4, 'Jacob'), (5, 'Julie');

INSERT INTO Restaurant (ID, name, city)
VALUES (1, 'Taco Dell', 'Bellevue'), (2, 'Ginger and spice', 'Seattle'), (3, 'Noodle Land', 'Redmond');

INSERT INTO City (ID, name, stateName)
VALUES (1, 'Bellevue', 'WA'), (2, 'Seattle', 'WA'), (3, 'Redmond', 'WA')

-- INSERT INTO EDGE TABLES
INSERT INTO likes
VALUES ((SELECT $node_id FROM Person WHERE ID = 1), (SELECT $node_id FROM Restaurant WHERE ID = 1), 9),
	((SELECT $node_id FROM Person WHERE ID = 2), (SELECT $node_id FROM Restaurant WHERE ID = 2), 9),
	((SELECT $node_id FROM Person WHERE ID = 3), (SELECT $node_id FROM Restaurant WHERE ID = 3), 9),
	((SELECT $node_id FROM Person WHERE ID = 4), (SELECT $node_id FROM Restaurant WHERE ID = 3), 9),
    ((SELECT $node_id FROM Person WHERE ID = 5), (SELECT $node_id FROM Restaurant WHERE ID = 3), 9);

INSERT INTO livesIn
VALUES ((SELECT $node_id FROM Person WHERE ID = 1), (SELECT $node_id FROM City WHERE ID = 1)),
	((SELECT $node_id FROM Person WHERE ID = 2), (SELECT $node_id FROM City WHERE ID = 2)),
	((SELECT $node_id FROM Person WHERE ID = 3), (SELECT $node_id FROM City WHERE ID = 3)),
	((SELECT $node_id FROM Person WHERE ID = 4), (SELECT $node_id FROM City WHERE ID = 3)),
	((SELECT $node_id FROM Person WHERE ID = 5), (SELECT $node_id FROM City WHERE ID = 1));

INSERT INTO locatedIn
VALUES ((SELECT $node_id FROM Restaurant WHERE ID = 1), (SELECT $node_id FROM City WHERE ID = 1)),
	((SELECT $node_id FROM Restaurant WHERE ID = 2), (SELECT $node_id FROM City WHERE ID = 2)),
	((SELECT $node_id FROM Restaurant WHERE ID = 3), (SELECT $node_id FROM City WHERE ID = 3));

INSERT INTO friendOf
VALUES ((SELECT $node_id FROM Person WHERE ID = 1), (SELECT $node_id FROM Person WHERE ID = 2)),
	((SELECT $NODE_ID FROM Person WHERE ID = 2), (SELECT $NODE_ID FROM Person WHERE ID = 3)),
	((SELECT $NODE_ID FROM Person WHERE ID = 3), (SELECT $NODE_ID FROM Person WHERE ID = 1)),
	((SELECT $NODE_ID FROM Person WHERE ID = 4), (SELECT $NODE_ID FROM Person WHERE ID = 2)),
	((SELECT $NODE_ID FROM Person WHERE ID = 5), (SELECT $NODE_ID FROM Person WHERE ID = 4));



-- Find which restaurant that John likes
SELECT Restaurant.name
FROM Person, likes, Restaurant
WHERE MATCH(Person-(likes)->Restaurant)
	AND Person.name = 'John'

-- Find the restaurants that John's friends like
SELECT Person2.name, Restaurant.name
FROM Person Person1, friendOf fo, Person Person2, likes, Restaurant
WHERE MATCH(Person1-(fo)->Person2-(likes)->Restaurant)
	AND Person1.name = 'John'

-- Find people who like a restaurant in the same city they live in
SELECT Person.name, City.name, Restaurant.name
FROM Person, livesIn, City, locatedIn, Restaurant, likes
WHERE MATCH(Person-(livesIn)->City<-(locatedIn)-Restaurant<-(likes)-Person)

-- Find friends of friends of friends
SELECT CONCAT(Person.name, '->', Person2.name, '->', Person3.name, '->', Person4.name)
FROM Person, friendOf, Person AS Person2, friendOf AS friendOffriend, Person AS Person3, friendOf AS friendOffriendOffriend, Person AS Person4
WHERE MATCH(Person-(friendOf)->Person2-(friendOffriend)->Person3-(friendOffriendOffriend)->Person4)
	AND Person.name != Person2.name
	AND Person2.name != Person3.name
	AND Person3.name != Person4.name
	AND Person4.name != Person.name

-- Find all friends of John
SELECT Person2.name
FROM Person, friendOf, Person AS Person2
WHERE MATCH(Person-(friendOf)->Person2)
	AND Person.name = 'John'
UNION ALL
SELECT Person2.name
FROM Person, friendOf, Person Person2
WHERE MATCH(Person<-(friendOf)-Person2)
	AND Person.name = 'John'

-- Find shortest path between two people
SELECT PersonName, Friends
FROM (
	SELECT
		Person1.name AS PersonName,
		STRING_AGG(Person2.name, '->') WITHIN GROUP (GRAPH PATH) AS Friends,
		LAST_VALUE(Person2.name) WITHIN GROUP (GRAPH PATH) AS LastNode
	FROM 
		Person AS Person1,
		friendOf FOR PATH AS fo,
		Person FOR PATH AS Person2
	WHERE MATCH(SHORTEST_PATH(Person1(-(fo)->Person2)+))
	AND Person1.name = 'Jacob'
) AS Q
WHERE Q.LastNode = 'Alice'

-- Count the number of hops/levels traversed to go from one person to another in the graph
SELECT 
	PersonName,
	Friends,
	levels
FROM (
	SELECT 
		Person1.name AS PersonName,
		STRING_AGG(Person2.name, '->') WITHIN GROUP (GRAPH PATH) AS Friends,
		LAST_VALUE(Person2.name) WITHIN GROUP (GRAPH PATH) AS LastNode,
		COUNT(Person2.name) WITHIN GROUP (GRAPH PATH) AS levels
	FROM 
		Person AS Person1,
		friendOf FOR PATH AS fo, 
		Person FOR PATH AS Person2
	WHERE MATCH(SHORTEST_PATH(Person1(-(fo)->Person2)+))
	AND Person1.name = 'Jacob'
) AS Q
WHERE Q.LastNode = 'Alice'

-- Find people 1-3 hops away from a given person
SELECT 
	Person1.name AS PersonName,
	STRING_AGG(Person2.name, '->') WITHIN GROUP (GRAPH PATH) AS friends
FROM
	Person AS Person1,
	friendOf FOR PATH AS fo,
	Person FOR PATH AS Person2
WHERE MATCH(SHORTEST_PATH(Person1(-(fo)->Person2){1,3}))
AND Person1.name = 'Jacob'


-- Find people 1-3 hops away from a given person, who also like a specific restaurant
SELECT 
	Person.name AS PersonName,
	STRING_AGG(Person2.name, '->') WITHIN GROUP(GRAPH PATH) AS Friends,
	Restaurant.name
FROM 
	Person AS Person, 
	friendOf FOR PATH AS fo, 
	Person FOR PATH AS Person2, 
	likes AS likes, 
	Restaurant AS Restaurant
WHERE MATCH(SHORTEST_PATH(Person(-(fo)->Person2){1,3}) AND LAST_NODE(Person2)-(likes)->Restaurant)
	AND Person.name = 'Jacob'
	AND Restaurant.name = 'Ginger and Spice'