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
CREATE CONSTRAINT IF NOT EXISTS station_id FOR (s:Station) REQUIRE s.id IS UNIQUE;
CREATE CONSTRAINT IF NOT EXISTS track_id FOR (m:Track) REQUIRE j.id IS UNIQUE;
CREATE CONSTRAINT IF NOT EXISTS point FOR (s:Point) REQUIRE s.point IS UNIQUE;

// Clean up old graph (optional)
CALL apoc.periodic.commit('
    MATCH (n)
    WITH n LIMIT $limit
    DETACH DELETE n
    RETURN COUNT(*)
', {limit:1000});

```

> TODO UPDATE ALL QUERIES BASED on load-queries.cypher!!


### About the source data
A multi-segment is a piece of train track that consists of multiple (smaller) segments. Keep in mind, multi-segments are not the same as routes between stations, we establish these later.


For our purpose, we want to split up the multi-segment, and store the individual track segments in the graph.

The graph will then have the shape:

**(:Point)-[:TRACK]->(:Point)**


**(:Point)-[:TRACK_SEGMENT]->(:Point)-[:TRACK_SEGMENT]->(:Point)**

Meanings of properties in the source data are documented here:
https://eurogeographics.org/wp-content/uploads/2018/04/EGM_Specification_v10.pdf

### Loading Multi-segments

First, load the multi-segments.
```
:auto LOAD CSV WITH HEADERS from "file:///europe-rail-road.csv" AS row FIELDTERMINATOR ';'
CALL {
    WITH row
    CREATE (s:Track)
   
   // inspireId = unique identifier of the track.
    SET s.id = split(row['inspireId'],":")[1]

    // row.RRA (Power Source)
    // 0 Unknown
    // 1 Electrified track
    // 3 Overhead electrified
    // 4 Non-electrified
     SET s.power_source = CASE
        WHEN row.RRA = "0" THEN "Unknown"
        WHEN row.RRA = "1" THEN "Electrified track"
        WHEN row.RRA = "3" THEN "Overhead electrified"
        WHEN row.RRA = "4" THEN "Non-electrified"
        ELSE "Unknown"
    END 

    // row.RSD = Railroad speed class
    // 0 Unknown
    // 1 Conventional Railway Line (~150 kmh)
    // 2 Upgraded high-speed railway line (order of 200km/h)
    // 3 Dedicated high-speed railway line (≥250km/h)
    // 997 Unpopulated
    SET s.train_speed_kmh = CASE
        WHEN row.RSD = "0" THEN 100
        WHEN row.RSD = "1" THEN 150
        WHEN row.RSD = "2" THEN 200
        WHEN row.RSD = "3" THEN 250
        ELSE 100
    END 

    // row.RSU =  Seasonal availablility
    // 0 Unknown
    // 1 All year
    // 2 Seasonal
    // 997 Unpopulated
    SET s.availability = CASE
        WHEN row.RSU = "0" THEN "Unknown"
        WHEN row.RSU = "1" THEN "All year"
        WHEN row.RSU = "2" THEN "Seasonal"
        WHEN row.RSU = "997" THEN "Unknown"
        ELSE "Unknown"
    END 

    // row.EXS = status
    // 0 Unknown
    // 5 Under construction
    // 6 Abandoned
    // 28 Operational
    SET s.status = CASE
        WHEN row.EXS = "0" THEN "Unknown"
        WHEN row.EXS = "5" THEN "Under Construction"
        WHEN row.EXS = "6" THEN "Abandoned"
        WHEN row.EXS = "28" THEN "Operational"
        ELSE "Unknown"
    END 

    // row.TEN = part of TransEuropean network
    // 0 Unknown
    // 1 part of TEN-T network
    // 2 not part of TEN-T network
    SET s.transeuropean_network = CASE
        WHEN row.TEN = "1" THEN true
        WHEN row.TEN = "2" THEN false
        ELSE null
    END 

    // row.FCO = feature configuration (how many rails?)
    // 0 Unknown
    // 2 Multiple
    // 3 Single
    SET s.rail_configuration = CASE
        WHEN row.FCO = "0" THEN 'unknown'
        WHEN row.FCO = "2" THEN 'multiple'
        WHEN row.FCO = "3" THEN 'single'
        ELSE 'Unknown'
    END 

    // row.F_CODE --> type of track
    SET s.type = CASE
        WHEN row.F_CODE = "AN010" THEN 'Railway'
        WHEN row.F_CODE = "AN500" THEN 'Railway Network Link'
        ELSE 'Unknown'
    END 

    // Operational since
    SET s.since = row.beginLifes

    // UUID
    SET s.uuid = row.inspireId

    // row.RGC = gauge category
    // 0 Unknown
    // 1 Broad
    // 2 Narrow
    // 3 Normal (Country Specific)
    // 998 Not applicable (for monorails)
    SET s.gauge_category = CASE
        WHEN row.RGC = "0" THEN 'Unknown'
        WHEN row.RGC = "1" THEN 'Broad'
        WHEN row.RGC = "2" THEN 'Narrow'
        WHEN row.RGC = "3" THEN 'Normal'
        WHEN row.RGC = "998" THEN 'NA'
        ELSE 'Unknown'
    END 

    // row.GAW = Gauge Width (cm)
    SET s.gauge_width_cm = toFloat(row.GAW)

    // row.LLE = Location Level
    //-9 Underground (unknown level)
    //-2 Underground (second level)
    //-1 Underground (first level)
    //0 Unknown
    //1 On ground surface
    //2 Suspended or elevated (first level)
    //3 Suspended or elevated (second level)
    //9 Suspended or elevated (unknown level)
    SET s.location = CASE
        WHEN row.LLE = "-9" THEN 'Underground (unknown level)'
        WHEN row.LLE = "-2" THEN 'Underground (second level)'
        WHEN row.LLE = "-1" THEN 'Underground (first level)'
        WHEN row.LLE = "0" THEN 'Unknown'
        WHEN row.LLE = "1" THEN 'On ground surface'
        WHEN row.LLE = "2" THEN 'Suspended or elevated (first level)'
        WHEN row.LLE = "3" THEN 'Suspended or elevated (second level)'
        WHEN row.LLE = "9" THEN 'Suspended or elevated (unknown level)'
        ELSE 'Unknown'
    END 

    // row.RCO = Railroad code
    SET s.railroad_code = row.RCO

    // row.TUC = usage category
    // 0 Unknown
    // 25 Cargo/Freight
    // 26 Passenger
    // 45 General
    SET s.usage_category = CASE
        WHEN row.TUC = "0" THEN 'Unknown'
        WHEN row.TUC = "25" THEN 'Cargo/Freight'
        WHEN row.TUC = "26" THEN 'Passenger'
        WHEN row.TUC = "45" THEN 'General'
        ELSE 'Unknown'
    END 

    // Countries
    SET s.country_code_3 = row.NLN1
    SET s.country_code_2 = row.ICC

    // Names
    SET s.name = row.NAMA1
    SET s.name_alt = row.NAMA1 + "/" + row.NAMA2
    SET s.all_names = row.NAMA1 + " / " + row.NAMA2  + " / " +  row.NAMN1  + " / " + row.NAMN2

    // Shape
    SET s.shape = row.`Geo Shape`

} IN TRANSACTIONS OF 1000 ROWS;
```

Extract junctions from multi-track-segments (in batches).
```
CALL apoc.periodic.commit('
    MATCH (s:Track)
    WHERE NOT EXISTS ((s)-[:HAS_POINT]->())
    WITH s LIMIT $limit
    WITH s, apoc.convert.fromJsonMap(s.shape).coordinates as coords_list
    SET s.segments = size(coords_list)

    WITH s, coords_list
    UNWIND coords_list as coords
    MERGE (j:Point{point({latitude: coords[1], longitude: coords[0]})})
    CREATE (s)-[:HAS_POINT{index: apoc.coll.indexOf(coords_list, coords)}]->(j)
    WITH s, collect(j) as junctions
    
    WITH s, junctions, apoc.coll.pairsMin([j in junctions | j.point]) as point_pairs
    SET s.distance = apoc.coll.sum([p in point_pairs | point.distance(p[0], p[1])]) 
    REMOVE s.shape
    WITH s, junctions[0] as start, junctions[-1] as end
    CREATE (start)-[t:TRACK]->(end)
    SET t = s
    RETURN COUNT(*)
', {limit:500});
```



For each track, create the track segments between adjacent junctions:
```
CALL apoc.periodic.commit('
    MATCH (m:Track)
    WITH m LIMIT $limit
    MATCH (m:Track)-[h:HAS_POINT]->(j:Point) 
    WITH m, j, h.index as index 
    ORDER BY m.id, index
    WITH m, collect(j) as junctions
    WITH m, apoc.coll.pairsMin(junctions) as pairs 
    UNWIND pairs as pair
    WITH m, pairs, pair, pair[0] as j1, pair[1] as j2
    CREATE (j1)-[t:TRACK_SEGMENT]->(j2)
    SET t = m
    SET t.distance = point.distance(j1.point, j2.point)
    SET t.id =  m.id + "-" + apoc.coll.indexOf(pairs, pair)
    SET t.parent_id =  m.id 
    DETACH DELETE m
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
MATCH (n:Point)
WHERE n.point = point
SET n:Station
SET n.since = row.beginLifes
SET n.id = row.RStationID + "=" + id(n)
SET n.uuid = row.inspireId

// TUC codes
// 0 Unknown
// 25 Cargo/Freight
// 26 Passenger
// 45 General
// 998 Military
SET n.usage_category = CASE
    WHEN row.TUC = "0" THEN 'Unknown'
    WHEN row.TUC = "25" THEN 'Cargo/Freight'
    WHEN row.TUC = "26" THEN 'Passenger'
    WHEN row.TUC = "45" THEN 'General'
    WHEN row.TUC = "998" THEN 'Military'
    ELSE 'Unknown'
END 

// Countries
SET n.country_code_3 = row.NLN1
SET n.country_code_2 = row.ICC

// TFC is the type of station:
// 0 Unknown
// 15 Railway Station
// 31 Joint Railway Station
// 32 Halt
// 33 Marshalling Yard
// 34 Intermodal Rail Transport Terminal
SET n.type = CASE
    WHEN row.TFC = "0" THEN 'Unknown'
    WHEN row.TFC = "15" THEN 'Railway Station'
    WHEN row.TFC = "31" THEN 'Joint Railway Station'
    WHEN row.TFC = "32" THEN 'Halt'
    WHEN row.TFC = "33" THEN 'Marshalling Yard'
    WHEN row.TFC = "34" THEN 'Intermodal Rail Transport Terminal'
    ELSE 'Unknown'
END 

WITH n, row, split(row.`Geo Point`,",") as coords
SET n.point = point({latitude: toFloat(coords[0]), longitude: toFloat(coords[1])}) 

SET n.name = row.NAMA1
SET n.name_alt = row.NAMA1 + " / " + row.NAMA2
SET n.all_names = row.NAMA1 + " / " + row.NAMA2  + " / " +  row.NAMN1  + " / " + row.NAMN2;
```

### Set up intersections and routes between them.

Establish intersections. We define intersections as junctions where:
- More than two tracks meet.
- Only one track is present (e.g. the end of the track).
- A junction where a station is present.

Intersections can then be used to create a routing graph
```
MATCH (j:Point)-[t:TRACK_SEGMENT]-()
WITH j, COUNT(t) as count
WHERE count > 2 OR count = 1
SET j:Intersection;
```

```
MATCH (j:Station)
SET j:Intersection;
```

Create routes between intersections using a subgraph detection algorithm.
```
CALL apoc.periodic.commit('
    MATCH (p:Intersection) 
    WHERE NOT EXISTS ((p)-[:ROUTE]->())
    WITH p LIMIT $limit
    WITH p
    CALL apoc.path.subgraphNodes(p, {
        relationshipFilter: "TRACK_SEGMENT",
        labelFilter: "/Intersection",
        minLevel: 1,
        maxLevel: 500000
    })
    YIELD node
    WITH p, node as p2
    CREATE (p)-[:ROUTE]->(p2)
    RETURN COUNT(*)
', {limit:50});
```

Calculate distances between intersection points.
```
CALL apoc.periodic.commit("
    MATCH (p:Intersection)-[r:ROUTE]->(p2:Intersection)
    WHERE r.distance IS NULL
    WITH r, p, p2 LIMIT 500
    CALL apoc.algo.dijkstra(p, p2, 'TRACK_SEGMENT', 'distance') YIELD path, weight
    SET r.distance = weight
    RETURN COUNT(*)
", {limit:500});
```