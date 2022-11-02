MATCH (n:Station), (m:Station)
WHERE n.name = "Rotterdam Centraal" and m.name = "Prestonpans Station"
WITH n,m
CALL apoc.algo.dijkstra(n, m, 'ROUTE', 'distance') YIELD path, weight
RETURN *

