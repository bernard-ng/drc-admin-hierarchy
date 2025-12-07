#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

set -a
source "$PROJECT_ROOT/.env"
set +a

SOURCE_DB="$POSTGRES_DB"
TARGET_DB="${ADMIN_DB:-drc_admin}"
TABLES=(country province city municipality neighborhood locality bloc road)
TABLE_FLAGS="$(printf ' -t %s' "${TABLES[@]}")"

echo "Starting Postgres container..."
docker compose up -d db

echo "Waiting for Postgres to be healthy..."
until docker compose exec -T db pg_isready -U "$POSTGRES_USER" -d "$SOURCE_DB" >/dev/null 2>&1; do
  echo "  ... still waiting"
  sleep 2
done

echo "Ensuring target database '$TARGET_DB' exists..."
EXISTS=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${TARGET_DB}'" | tr -d '[:space:]')
if [ "$EXISTS" != "1" ]; then
  docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${TARGET_DB}\" OWNER \"${POSTGRES_USER}\";"
fi

echo "Ensuring required extensions in '$TARGET_DB'..."
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$TARGET_DB" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS hstore;"

echo "Copying domain tables (${TABLES[*]}) from '$SOURCE_DB' to '$TARGET_DB'..."
docker compose exec -T db bash -c "set -euo pipefail; pg_dump -U \"$POSTGRES_USER\" -d \"$SOURCE_DB\" --no-owner --clean --if-exists${TABLE_FLAGS} | psql -U \"$POSTGRES_USER\" -d \"$TARGET_DB\""

echo "Domain tables copied into '$TARGET_DB'."
