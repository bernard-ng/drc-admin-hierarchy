#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

set -a
source "$PROJECT_ROOT/.env"
set +a

echo "Running admin hierarchy SQL..."
docker cp src/sql/02_hierarchy.sql drc_osm_db:/tmp/02_hierarchy.sql
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f /tmp/02_hierarchy.sql

echo "Creating address views..."
docker cp src/sql/03_views.sql drc_osm_db:/tmp/03_views.sql
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f /tmp/03_views.sql

echo "Admin hierarchy + views built."
