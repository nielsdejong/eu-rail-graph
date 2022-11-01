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

// Clean up old graph (optional)
CALL apoc.periodic.commit('
    MATCH (n)
    WITH n LIMIT $limit
    DETACH DELETE n
    RETURN COUNT(*)
', {limit:500});

```


### About the source data
A multi-segment is a piece of train track that consists of multiple (smaller) segments. Keep in mind, multi-segments are not the same as routes between stations, we establish these later.


For our purpose, we want to split up the multi-segment, and store the individual track segments in the graph.

The graph will then have the shape:

**(:Junction)-[:TRACK]->(:Junction)**

Meanings of properties in the source data are documented here:
https://eurogeographics.org/wp-content/uploads/2018/04/EGM_Specification_v10.pdf

### Loading Multi-segments

First, load the multi-segments.
```
:auto LOAD CSV WITH HEADERS from "file:///europe-rail-road.csv" AS row FIELDTERMINATOR ';'
CALL {
    WITH row
    CREATE (s:MultiSegment)
   
    SET s.id = split(row['inspireId'],":")[1]

    // row.RRA (Power Source)
    // 0 Unknown
    // 1 Electrified track
    // 3 Overhead electrified
    // 4 Non-electrified
    SET s.power_source = row.RRA

    // row.RSD = Railroad speed class
    // 0 Unknown
    // 1 Conventional Railway Line (~150 kmh)
    // 2 Upgraded high-speed railway line (order of 200km/h)
    // 3 Dedicated high-speed railway line (≥250km/h)
    // 997 Unpopulated
    SET r.train_speed_kmh = row.RSD

    // row.RSU =  Seasonal availablility
    // 0 Unknown
    // 1 All year
    // 2 Seasonal
    // 997 Unpopulated
    ET r.availability = row.RSU

    // row.EXS = status
    // 0 Unknown
    // 5 Under construction
    // 6 Abandoned
    // 28 Operational
    SET s.status = row.EXS

    // row.TEN = part of TransEuropean network
    // 0 Unknown
    // 1 part of TEN-T network
    // 2 not part of TEN-T network
    SET n.transeuropean_network = row.TEN

    // row.FCO = feature configuration (how many rails?)
    // 0 Unknown
    // 2 Multiple
    //  3 Single
    SET s.rail_configuration = row.FCO

    // row.F_CODE 
    // AN010 = Railway
    // AN500 = Railway Network Link
    set f.type = row.F_CODE

    SET n.since = row.beginLifes
    SET n.uuid = row.inspireId

    // row.RGC = gauge category
    // 0 Unknown
    // 1 Broad
    // 2 Narrow
    // 3 Normal (Country Specific)
    // 998 Not applicable (for monorails)
    SET n.gauge_category = row.RGC
    // row.GAW = Gauge Width (cm)
    SET n.gauge_width_cm = row.GAW

    // row.LLE = Location Level
    //-9 Underground (unknown level)
    //-2 Underground (second level)
    //-1 Underground (first level)
    //0 Unknown
    //1 On ground surface
    //2 Suspended or elevated (first level)
    //3 Suspended or elevated (second level)
    //9 Suspended or elevated (unknown level)
    SET n.location = row.LLE
 
    // row.RCO = Railroad code
    SET n.railroad_code = row.RCO

    // row.TUC = usage category
    // 0 Unknown
    // 25 Cargo/Freight
    // 26 Passenger
    // 45 General
    SET n.usage_category = row.TUC

    SET 

    // Countries
    SET n.country_code_3 = row.NLN1
    SET n.country_code_2 = row.ICC

    // Names
    SET n.name = row.NAMA1
    SET n.name_alt = row.NAMA1 + "/" + row.NAMA2
    SET n.all_names = row.NAMA1 + "/" + row.NAMN2  + "/" +  row.NAMA1  + "/" + row.NAMA2;


} IN TRANSACTIONS OF 1000 ROWS
```

Extract junctions from multi-segments (in batches).
```
CALL apoc.periodic.commit('
    MATCH (s:MultiSegment)
    WHERE NOT EXISTS ((s)-[:HAS_JUNCTION]->())
    WITH s LIMIT $limit
    WITH s, apoc.convert.fromJsonMap(s.`Geo Shape`).coordinates as coords_list
    SET s.tracks = size(coords_list)
    WITH s, coords_list
    UNWIND coords_list as coords
    MERGE (j:Junction{id: coords[0]+","+coords[1]})
    SET j.point = point({latitude: coords[1], longitude: coords[0]})
    CREATE (s)-[:HAS_JUNCTION{index: apoc.coll.indexOf(coords_list, coords)}]->(j)
    RETURN COUNT(*)
', {limit:500});
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
    CREATE (j1)-[:TRACK{distance: point.distance(j1.point, j2.point)}]->(j2)
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

SET n.since = row.beginLifes
SET n.id = row.RStationID
SET n.uuid = row.inspireId

// TUC codes
// 0 Unknown
// 25 Cargo/Freight
// 26 Passenger
// 45 General
// 998 Military
SET n.usage_category = row.TUC

// Countries
SET n.country_code_3 = row.NLN1
SET n.country_code_2 = row.ICC

// TFC is the type of station:
// 0 Unknown
// 15 Railway Station
// 31 Joint Railway Station
// 32 Halt
// 33 Marshalling Yard
// 34 Intermodal Rail Transport
// Terminal
SET n.type = row.TFC

WITH n, row, split(row.`Geo Point`,",") as coords
SET n.point = point({latitude: toFloat(coords[0]), longitude: toFloat(coords[1])}) 

SET n.name = row.NAMA1
SET n.name_alt = row.NAMA1 + "/" + row.NAMA2
SET n.all_names = row.NAMA1 + "/" + row.NAMN2  + "/" +  row.NAMA1  + "/" + row.NAMA2;
```

Create station to station routes
```
CALL apoc.periodic.commit('
    MATCH (p:Station) 
    WHERE NOT EXISTS ((p)-[:ROUTE]->())
    WITH p LIMIT $limit
    WITH p
    CALL apoc.path.subgraphNodes(p, {
        relationshipFilter: "TRACK",
        labelFilter: "/Station",
        minLevel: 1,
        maxLevel: 500000
    })
    YIELD node
    WITH p, node as p2
    CREATE (p)-[:ROUTE]->(p2)
    RETURN COUNT(*)
', {limit:50});
```
