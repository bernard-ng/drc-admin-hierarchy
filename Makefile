SHELL := /bin/bash
COMPOSE := docker compose
ENV_FILE := .env

.PHONY: help up down logs import rebuild graph check psql

help:
	@echo "Targets:"
	@echo "  make up       - start Postgres + Neo4j in background"
	@echo "  make down     - stop all compose services"
	@echo "  make logs     - tail db + neo4j logs"
	@echo "  make import   - run OSM import into Postgres"
	@echo "  make rebuild  - build admin/road tables and views"
	@echo "  make graph    - export to Neo4j graph"
	@echo "  make check    - run assumption checks"
	@echo "  make psql     - open psql in the db container"

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100 db neo4j

import:
	./src/scripts/import.sh

rebuild:
	./src/scripts/hierarchy.sh

graph:
	./src/scripts/graph.sh

check:
	./src/scripts/check.sh

copy:
	./src/scripts/copy.sh

psql:
	@set -a; source $(ENV_FILE); set +a; \
	$(COMPOSE) exec db psql -U $$POSTGRES_USER -d $$POSTGRES_DB
