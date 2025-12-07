#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

OSM_FILE="$PROJECT_ROOT/data/congo-democratic-republic-251204.osm.pbf"
LUA_STYLE="src/style.lua"

set -a
source "$PROJECT_ROOT/.env"
set +a

if [ ! -f "$OSM_FILE" ]; then
  echo "ERROR: OSM file not found at $OSM_FILE"
  exit 1
fi

echo "Starting Postgres container..."
docker compose up -d db

echo "Waiting for Postgres to be healthy..."
until docker compose exec -T db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
  echo "  ... still waiting"
  sleep 3
done

echo "Initializing extensions..."
docker cp src/sql/01_init.sql drc_osm_db:/tmp/01_init.sql
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f /tmp/01_init.sql

echo "Running osm2pgsql (flex)..."
export PGPASSWORD="$POSTGRES_PASSWORD"

osm2pgsql \
  -d "$POSTGRES_DB" \
  -H 127.0.0.1 \
  -P 5432 \
  -U "$POSTGRES_USER" \
  -O flex \
  -S "$LUA_STYLE" \
  --latlong \
  "$OSM_FILE"

echo "OSM import finished."
