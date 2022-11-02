// Create constraints
CREATE CONSTRAINT station_id IF NOT EXISTS FOR (s:Station) REQUIRE s.id IS UNIQUE;
CREATE CONSTRAINT track_id IF NOT EXISTS FOR (m:Track) REQUIRE m.id IS UNIQUE;
CREATE TEXT INDEX track_rel_id_name IF NOT EXISTS FOR ()-[r:TRACK]-() ON (r.id);
CREATE TEXT INDEX track_segment_rel_id_name IF NOT EXISTS FOR ()-[r:TRACK_SEGMENT]-() ON (r.id);
CREATE CONSTRAINT point IF NOT EXISTS FOR (s:Point) REQUIRE s.point IS UNIQUE;

// Clean up old graph (optional)
CALL apoc.periodic.commit('
    MATCH (n)
    WITH n LIMIT $limit
    DETACH DELETE n
    RETURN COUNT(*)
', {limit:1000});

:auto LOAD CSV WITH HEADERS from "https://raw.githubusercontent.com/nielsdejong/eu-rail-graph/main/data/europe-rail-road.csv" AS row FIELDTERMINATOR ';'
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
    SET s.name_alt = row.NAMA1 + " / " + row.NAMA2
    SET s.all_names = row.NAMA1 + " / " + row.NAMA2  + " / " +  row.NAMN1  + " / " + row.NAMN2

    // Shape
    SET s.shape = row.`Geo Shape`

} IN TRANSACTIONS OF 1000 ROWS;


CALL apoc.periodic.commit('
    MATCH (s:Track)
    WHERE NOT EXISTS ((s)-[:HAS_POINT]->())
    WITH s LIMIT $limit
    WITH s, apoc.convert.fromJsonMap(s.shape).coordinates as coords_list
    SET s.segments = size(coords_list) - 1
 
    WITH s, coords_list
    UNWIND coords_list as coords
    MERGE (j:Point{point: point({latitude: coords[1], longitude: coords[0]})})
    CREATE (s)-[:HAS_POINT{index: apoc.coll.indexOf(coords_list, coords)}]->(j)
    WITH s, collect(j) as points
    
    WITH s, points, apoc.coll.pairsMin([j in points | j.point]) as point_pairs
    SET s.distance = apoc.coll.sum([p in point_pairs | point.distance(p[0], p[1])]) 
    REMOVE s.shape
    WITH s, points[0] as start, points[-1] as end
    CREATE (start)-[t:TRACK]->(end)
    SET t = s
    SET t.children = [s in range(1,t.segments) | t.id + "_segment_" + s]
    RETURN COUNT(*)
', {limit:500});


CALL apoc.periodic.commit('
    MATCH (m:Track)
    WHERE m.processed IS NULL
    WITH m LIMIT $limit
    MATCH (m:Track)-[h:HAS_POINT]->(j:Point) 
    WITH m, j, h.index as index 
    ORDER BY m.id, index
    WITH m, collect(j) as points
    WITH m, apoc.coll.pairsMin(points) as pairs 
    UNWIND pairs as pair
    WITH m, pairs, pair, pair[0] as j1, pair[1] as j2
    CREATE (j1)-[t:TRACK_SEGMENT]->(j2)
    SET t = m
    SET t.distance = point.distance(j1.point, j2.point)
    SET t.id =  m.id + "_segment_" + apoc.coll.indexOf(pairs, pair)
    SET t.index = apoc.coll.indexOf(pairs, pair)
    SET t.parent_track_id =  m.id
    SET m.processed = true
    RETURN COUNT(*)
', {limit:500});

CALL apoc.periodic.commit('
    MATCH (m:Track)
    WITH m LIMIT $limit
    DETACH DELETE m
    RETURN COUNT(*)
', {limit:500});


LOAD CSV WITH HEADERS from "https://raw.githubusercontent.com/nielsdejong/eu-rail-graph/main/data/europe-railway-station.csv" AS row FIELDTERMINATOR ';'
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




MATCH (j:Point)-[t:TRACK_SEGMENT]-()
WITH j, COUNT(t) as count
WHERE count > 2 OR count = 1
SET j:Junction;

MATCH (j:Station)
SET j:Junction;

CALL apoc.periodic.commit('
    MATCH (p:Junction) 
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

CALL apoc.periodic.commit("
    MATCH (p:Junction)-[r:ROUTE]->(p2:Junction)
    WHERE r.distance IS NULL
    WITH r, p, p2 LIMIT $limit
    CALL apoc.algo.dijkstra(p, p2, 'TRACK_SEGMENT', 'distance') YIELD path, weight
    SET r.distance = weight
    RETURN COUNT(*)
", {limit:500});