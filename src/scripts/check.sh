#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

set -a
source "$PROJECT_ROOT/.env"
set +a
 
echo "Running assumption checks..."
docker cp src/sql/04_check.sql drc_osm_db:/tmp/04_check.sql
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f /tmp/04_check.sql
