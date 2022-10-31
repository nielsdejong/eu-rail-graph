#  European Rail Network Graph
This repository contains data, queries and visualizations for mapping the European Rail Network inside Neo4j (As prepared for NODES 2022).

## 1. Data Loading
As source data, this graph uses two public datasets provided by opendatasoft.com.

| Dataset               | URL                                                                                 |
|-----------------------|-------------------------------------------------------------------------------------|
| EU Railway Stations   | https://public.opendatasoft.com/explore/dataset/europe-railway-station/information/ |
| EU Rail Road Segments | https://public.opendatasoft.com/explore/dataset/europe-rail-road/information/       |

To get started, create a Neo4j database, install `apoc`, and move the contents of the `data` directory in this repository into your `import` folder in Neo4j.

### Create Constraints
```
CREATE CONSTRAINT station_id FOR (s:Station) REQUIRE s.id IS UNIQUE;
CREATE CONSTRAINT junction_id FOR (j:Junction) REQUIRE j.id IS UNIQUE;
CREATE CONSTRAINT multisegment_id FOR (m:MultiSegment) REQUIRE j.id IS UNIQUE;
CREATE CONSTRAINT station_point FOR (s:Station) REQUIRE s.point IS UNIQUE;
CREATE CONSTRAINT junction_point FOR (j:Junction) REQUIRE j.point IS UNIQUE;

```


### Loading Multi-segments
A multi-segment is a piece of train track that consists of multiple (smaller) segments. Keep in mind, multi-segments are not the same as routes between stations, we establish these later.


For our purpose, we want to split up the multi-segment, and store the individual track segments in the graph.

The graph will then have the shape:
```
(:Junction)-[:TRACK]->(:Junction)
```

First, load the multi-segements.
```
LOAD CSV WITH HEADERS from "file:///europe-rail-road.csv" AS row
    FIELDTERMINATOR ';'
CREATE (s:MultiSegment)
SET s = row
SET s.id = split(row['inspireId'],":")[1]
```

Extract junctions from multi-segments (in batches).
```
CALL apoc.periodic.commit('
    MATCH (s:MultiSegment)
    WHERE NOT EXISTS ((s)-[:HAS_JUNCTION]->())
    WITH s LIMIT $limit
    WITH s, apoc.convert.fromJsonMap(s.`Geo Shape`).coordinates as coords_list
    UNWIND coords_list as coords
    MERGE (j:Junction{id: coords[0]+","+coords[1]})
    SET j.point = point({latitude: coords[1], longitude: coords[0]})
    CREATE (s)-[:HAS_JUNCTION{index: apoc.coll.indexOf(coords_list, coords)}]->(j)
    RETURN COUNT(*)
', {limit:500})
```

Re-assign junction ids based on their multisegment id + index.
```
CALL apoc.periodic.commit('
    MATCH (s:MultiSegment)
    WITH s LIMIT $limit
    WITH s, apoc.convert.fromJsonMap(s.`Geo Shape`).coordinates as coords_list
    UNWIND coords_list as coords
    MERGE (j:Junction{id: coords[0]+","+coords[1]})
    SET j.point = point({latitude: coords[1], longitude: coords[0]})
    CREATE (s)-[:HAS_JUNCTION{index: apoc.coll.indexOf(coords_list, coords)}]->(j)
    RETURN COUNT(*)
', {limit:500})
```


Create tracks between adjacent junctions:
```
CALL apoc.periodic.commit('
    MATCH (m:MultiSegment)
    WHERE m.processed IS NULL
    WITH m LIMIT $limit
    MATCH (m:MultiSegment)-[h:HAS_JUNCTION]->(j:Junction) 
    WITH m, j, h.index as index 
    ORDER BY m.id, index
    WITH m, collect(j) as junctions
    WITH m, apoc.coll.pairsMin(junctions) as pairs 
    UNWIND pairs as pair
    WITH m, pair[0] as j1, pair[1] as j2
    CREATE (j1)-[:TRACK]->(j2)
    SET m.processed = true
    RETURN COUNT(*)
', {limit:500});
```


### Loading Stations
Load the stations dataset, and overlay it onto the junctions.

> Note - we are matching on 8127 out of 8128 stations here, with the exception of Nagyatad station in Hungary. For now, we can ignore this one.

```
LOAD CSV WITH HEADERS from "file:///europe-railway-station.csv" AS row FIELDTERMINATOR ';'
WITH row, split(row.`Geo Point`,",") as coords
WITH row, point({latitude: toFloat(coords[0]), longitude: toFloat(coords[1])}) as point
MATCH (j:Junction)
WHERE j.point = point
SET j:Station
SET j = row
SET j.id = split(row['inspireId'],":")[1];
```

Post query cleanup...
```
MATCH (n:Station)
WITH n, split(n.`Geo Point`,",") as coords
WITH n, point({latitude: toFloat(coords[0]), longitude: toFloat(coords[1])})  as point
SET n.point = point;
```

```
MATCH (s:Station)
SET s.name = s.NAMA1;
```

```
MATCH (s:Station)
WHERE s.NAMA2 <> "N_A"
SET s.name = s.NAMA1 + "/" + s.NAMA2;
```
