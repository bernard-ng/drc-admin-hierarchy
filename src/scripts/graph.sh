#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

set -a
source "$PROJECT_ROOT/.env"
set +a

EXPORT_DIR="$PROJECT_ROOT/data/neo4j"
mkdir -p "$EXPORT_DIR"
NODES_CSV="$EXPORT_DIR/admin_nodes.csv"
EDGES_CSV="$EXPORT_DIR/admin_edges.csv"
ROADS_CSV="$EXPORT_DIR/roads.csv"
ROAD_EDGES_CSV="$EXPORT_DIR/road_admin_edges.csv"
rm -f "$NODES_CSV" "$EDGES_CSV" "$ROADS_CSV" "$ROAD_EDGES_CSV"

echo "Starting Postgres + Neo4j containers..."
docker compose up -d db neo4j

echo "Waiting for Postgres to be healthy..."
until docker compose exec -T db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
  echo "  ... still waiting for Postgres"
  sleep 2
done

PSQL_CMD=(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F',' -A -v "ON_ERROR_STOP=1")

echo "Exporting admin nodes..."
"${PSQL_CMD[@]}" -c "COPY (
  SELECT id, COALESCE(name, '') AS name, hierarchy_level, 'country' AS type FROM country
  UNION ALL
  SELECT id, COALESCE(name, '') AS name, hierarchy_level, 'province' AS type FROM province
  UNION ALL
  SELECT id, COALESCE(name, '') AS name, hierarchy_level, 'city' AS type FROM city
  UNION ALL
  SELECT id, COALESCE(name, '') AS name, hierarchy_level, 'municipality' AS type FROM municipality
  UNION ALL
  SELECT id, COALESCE(name, '') AS name, hierarchy_level, 'neighborhood' AS type FROM neighborhood
  UNION ALL
  SELECT id, COALESCE(name, '') AS name, hierarchy_level, 'locality' AS type FROM locality
  UNION ALL
  SELECT id, COALESCE(name, '') AS name, hierarchy_level, 'bloc' AS type FROM bloc
) TO STDOUT WITH CSV HEADER" > "$NODES_CSV"

echo "Exporting admin edges..."
"${PSQL_CMD[@]}" -c "COPY (
  SELECT country_id AS parent_id, id AS child_id, 'HAS_PROVINCE' AS rel_type
  FROM province
  WHERE country_id IS NOT NULL
  UNION ALL
  SELECT province_id AS parent_id, id AS child_id, 'HAS_CITY' AS rel_type
  FROM city
  WHERE province_id IS NOT NULL
  UNION ALL
  SELECT city_id AS parent_id, id AS child_id, 'HAS_MUNICIPALITY' AS rel_type
  FROM municipality
  WHERE city_id IS NOT NULL
  UNION ALL
  SELECT municipality_id AS parent_id, id AS child_id, 'HAS_NEIGHBORHOOD' AS rel_type
  FROM neighborhood
  WHERE municipality_id IS NOT NULL
  UNION ALL
  SELECT neighborhood_id AS parent_id, id AS child_id, 'HAS_LOCALITY' AS rel_type
  FROM locality
  WHERE neighborhood_id IS NOT NULL
  UNION ALL
  SELECT locality_id AS parent_id, id AS child_id, 'HAS_BLOC' AS rel_type
  FROM bloc
  WHERE locality_id IS NOT NULL
) TO STDOUT WITH CSV HEADER" > "$EDGES_CSV"

echo "Exporting roads..."
"${PSQL_CMD[@]}" -c "COPY (
  SELECT id,
         COALESCE(name, '') AS name,
         COALESCE(ref, '') AS ref,
         COALESCE(highway, '') AS highway
  FROM road
) TO STDOUT WITH CSV HEADER" > "$ROADS_CSV"

echo "Exporting road-to-admin edges..."
"${PSQL_CMD[@]}" -c "COPY (
  SELECT id AS road_id,
         COALESCE(
           bloc_id,
           locality_id,
           neighborhood_id,
           municipality_id,
           city_id,
           province_id,
           country_id
         ) AS admin_osm_id
  FROM road
  WHERE COALESCE(
    bloc_id,
    locality_id,
    neighborhood_id,
    municipality_id,
    city_id,
    province_id,
    country_id
  ) IS NOT NULL
) TO STDOUT WITH CSV HEADER" > "$ROAD_EDGES_CSV"

echo "Copying CSVs into Neo4j import directory..."
docker compose exec -T neo4j bash -c "rm -f /import/nodes.csv /import/edges.csv /import/roads.csv /import/road_admin_edges.csv"
docker cp "$NODES_CSV" drc_osm_graph:/import/nodes.csv
docker cp "$EDGES_CSV" drc_osm_graph:/import/edges.csv
docker cp "$ROADS_CSV" drc_osm_graph:/import/roads.csv
docker cp "$ROAD_EDGES_CSV" drc_osm_graph:/import/road_admin_edges.csv

echo "Waiting for Neo4j to be available..."
until docker compose exec -T neo4j cypher-shell -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" "RETURN 1;" >/dev/null 2>&1; do
  echo "  ... still waiting for Neo4j"
  sleep 2
done

echo "Clearing Neo4j graph (all nodes and relationships)..."
docker compose exec -T neo4j cypher-shell -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" "MATCH (n) DETACH DELETE n;"

echo "Loading graph into Neo4j..."
docker compose exec -T neo4j cypher-shell -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" <<'CYPHER'
CREATE CONSTRAINT IF NOT EXISTS FOR (n:Admin) REQUIRE n.osm_id IS UNIQUE;
CREATE CONSTRAINT IF NOT EXISTS FOR (r:Road) REQUIRE r.osm_id IS UNIQUE;
MATCH (n) DETACH DELETE n;

LOAD CSV WITH HEADERS FROM 'file:///nodes.csv' AS row
WITH row WHERE row.id <> ''
WITH row,
     toInteger(row.id) AS osm_id,
     toInteger(row.hierarchy_level) AS hierarchy_level
MERGE (n:Admin {osm_id: osm_id})
SET n.name = CASE WHEN row.name = '' THEN null ELSE row.name END,
    n.hierarchy_level = hierarchy_level,
    n.type = row.type
FOREACH (_ IN CASE WHEN hierarchy_level = 2 THEN [1] ELSE [] END | SET n:Country)
FOREACH (_ IN CASE WHEN hierarchy_level = 4 THEN [1] ELSE [] END | SET n:Province)
FOREACH (_ IN CASE WHEN hierarchy_level = 6 THEN [1] ELSE [] END | SET n:City)
FOREACH (_ IN CASE WHEN hierarchy_level = 7 THEN [1] ELSE [] END | SET n:Municipality)
FOREACH (_ IN CASE WHEN hierarchy_level = 8 THEN [1] ELSE [] END | SET n:Neighborhood)
FOREACH (_ IN CASE WHEN hierarchy_level = 9 THEN [1] ELSE [] END | SET n:Locality)
FOREACH (_ IN CASE WHEN hierarchy_level = 10 THEN [1] ELSE [] END | SET n:Bloc);

LOAD CSV WITH HEADERS FROM 'file:///edges.csv' AS row
MATCH (parent:Admin {osm_id: toInteger(row.parent_id)})
MATCH (child:Admin {osm_id: toInteger(row.child_id)})
MERGE (parent)-[r:HAS_CHILD {type: row.rel_type}]->(child);

LOAD CSV WITH HEADERS FROM 'file:///roads.csv' AS row
WITH row WHERE row.id <> ''
WITH row, toInteger(row.id) AS osm_id
MERGE (r:Road {osm_id: osm_id})
SET r.name = CASE WHEN row.name = '' THEN null ELSE row.name END,
    r.ref = CASE WHEN row.ref = '' THEN null ELSE row.ref END,
    r.highway = CASE WHEN row.highway = '' THEN null ELSE row.highway END;

LOAD CSV WITH HEADERS FROM 'file:///road_admin_edges.csv' AS row
MATCH (r:Road {osm_id: toInteger(row.road_id)})
MATCH (a:Admin {osm_id: toInteger(row.admin_osm_id)})
MERGE (r)-[:IN_ADMIN]->(a);
CYPHER

echo "Neo4j graph updated. Open http://localhost:7474/ and connect with bolt://localhost:7687 using the credentials from .env."
