# DRC OSM Admin Hierarchy

Pipeline to build DR Congo’s administrative hierarchy (and roads) from an OSM
`.osm.pbf`, store it in Postgres/PostGIS, and mirror it into Neo4j.

## Requirements

- Docker + docker compose
- `osm2pgsql` installed on the host
- OSM extract in `data/` (default: `data/congo-democratic-republic-251204.osm.pbf`)

## Setup

```bash
git clone <this-project> drc-osm-admin
cd drc-osm-admin
# Place your .osm.pbf in data/ or set OSM_FILE when running the import
cp /path/to/your.osm.pbf data/congo-democratic-republic-251204.osm.pbf
```

Credentials are in `.env` (Postgres + Neo4j). Neo4j password must not be `neo4j`.

## Common commands (Make shortcuts)

- `make up` — start Postgres + Neo4j
- `make down` — stop all compose services
- `make import` — import OSM into Postgres (runs osm2pgsql; starts db if needed)
- `make rebuild` — build domain tables (`country/province/city/municipality/neighborhood/locality/bloc/road`) and views
- `make graph` — export from Postgres and load the Neo4j graph
- `make check` — run assumption checks
- `make logs` — tail db + Neo4j logs
- `make psql` — open psql inside the db container

## Typical flow

1. `make import` — load OSM into Postgres.
2. `make rebuild` — build hierarchy + roads with admin links.
3. `make graph` — create Neo4j nodes/edges. (Neo4j: `http://localhost:7474`, Bolt: `bolt://localhost:7687`.)
4. Optional: `docker compose up -d adminer` to browse the DB at `http://localhost:8082/`.

Notes:

- Domain table values are trimmed and lowercased. Kinshasa is treated as both province and city (province mirrored as city when needed).
- `.env` is read by scripts and compose; adjust for custom ports/credentials.
