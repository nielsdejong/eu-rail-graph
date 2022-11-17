// Shortest path by distance (Rotterdam --> Den Bosch)
MATCH (n:Station), (m:Station)
WHERE n.name = "Rotterdam Centraal" and m.name = "'s Hertogenbosch"
WITH n,m
CALL apoc.algo.dijkstra(n, m, 'ROUTE', 'distance') YIELD path, weight
RETURN path, weight;

// Shortest path by travel time (Rotterdam --> Den Bosch)
MATCH (n:Station), (m:Station)
WHERE n.name = "Rotterdam Centraal" and m.name = "'s Hertogenbosch"
WITH n,m
CALL apoc.algo.dijkstra(n, m, 'ROUTE', 'travel_time_seconds') YIELD path, weight
RETURN path, weight;
