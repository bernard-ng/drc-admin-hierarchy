SET search_path TO public;

-- Safety: drop old tables if re-running.
DROP TABLE IF EXISTS road CASCADE;                -- Routes nommées/référencées
DROP TABLE IF EXISTS bloc CASCADE;                -- Blocs / Subdivisions internes
DROP TABLE IF EXISTS locality CASCADE;            -- Localités / Villages / Cellules
DROP TABLE IF EXISTS neighborhood CASCADE;        -- Groupements / Quartiers
DROP TABLE IF EXISTS municipality CASCADE;        -- Collectivités / Communes
DROP TABLE IF EXISTS city CASCADE;                -- Villes / Territoires
DROP TABLE IF EXISTS province CASCADE;            -- Provinces
DROP TABLE IF EXISTS country CASCADE;             -- Pays

-- 1. Country (level 2)
CREATE TABLE country AS
  SELECT id, lower(btrim(name)) AS name, hierarchy_level, geom
  FROM osm_boundaries
  WHERE hierarchy_level = 2;

ALTER TABLE country ADD PRIMARY KEY (id);
CREATE INDEX country_geom_idx ON country USING GIST (geom);

-- 2. Provinces (level 4)
CREATE TABLE province AS
SELECT
  b.id,
  lower(btrim(b.name)) AS name,
  4 AS hierarchy_level,
  b.geom,
  c.id AS country_id
FROM osm_boundaries b
JOIN country c
  ON ST_Contains(c.geom, ST_PointOnSurface(b.geom))
WHERE b.hierarchy_level = 4;

ALTER TABLE province ADD PRIMARY KEY (id);
CREATE INDEX province_geom_idx ON province USING GIST (geom);

-- 4. Territoire / Ville (level 6)
CREATE TABLE city AS
WITH city_sources AS (
  SELECT
    b.id,
    lower(btrim(b.name)) AS name,
    6 AS hierarchy_level,
    b.geom,
    p.id AS province_id,
    c.id AS country_id
  FROM osm_boundaries b
  JOIN province p
    ON ST_Contains(p.geom, ST_PointOnSurface(b.geom))
  JOIN country c
    ON c.id = p.country_id
  WHERE b.hierarchy_level = 6

  UNION ALL
  -- Special case: Kinshasa is both province and city; 
  -- if a city boundary is missing, mirror the province.
  SELECT
    p.id,
    lower(btrim(p.name)) AS name,
    6 AS hierarchy_level,
    p.geom,
    p.id AS province_id,
    p.country_id AS country_id
  FROM province p
  WHERE lower(btrim(p.name)) = 'kinshasa'
)
SELECT DISTINCT ON (id)
  id,
  name,
  hierarchy_level,
  geom,
  province_id,
  country_id
FROM city_sources
ORDER BY id;

ALTER TABLE city ADD PRIMARY KEY (id);
CREATE INDEX city_geom_idx ON city USING GIST (geom);

-- 5. Collectivité / Commune (level 7)
CREATE TABLE municipality AS
SELECT
  b.id,
  lower(btrim(b.name)) AS name,
  7 AS hierarchy_level,
  b.geom,
  t.id AS city_id,
  p.id AS province_id,
  c.id AS country_id
FROM osm_boundaries b
JOIN city t 
  ON ST_Contains(t.geom, ST_PointOnSurface(b.geom))
JOIN province p 
  ON p.id = t.province_id
JOIN country c 
  ON c.id = p.country_id
WHERE b.hierarchy_level = 7;

ALTER TABLE municipality ADD PRIMARY KEY (id);
CREATE INDEX municipality_geom_idx ON municipality USING GIST (geom);

-- 6. Groupement / Quartier (level 8)
CREATE TABLE neighborhood AS
SELECT
  b.id,
  lower(btrim(b.name)) AS name,
  8 AS hierarchy_level,
  b.geom,
  c.id AS municipality_id,
  t.id AS city_id,
  p.id AS province_id,
  co.id AS country_id
FROM osm_boundaries b
JOIN municipality c 
  ON ST_Contains(c.geom, ST_PointOnSurface(b.geom))
JOIN city t 
  ON t.id = c.city_id
JOIN province p 
  ON p.id = t.province_id
JOIN country co 
  ON co.id = p.country_id
WHERE b.hierarchy_level = 8;

ALTER TABLE neighborhood ADD PRIMARY KEY (id);
CREATE INDEX neighborhood_geom_idx ON neighborhood USING GIST (geom);

-- 7. Localité / village / cellule (level 9)
CREATE TABLE locality AS
SELECT
  b.id,
  lower(btrim(b.name)) AS name,
  9 AS hierarchy_level,
  b.geom,
  g.id AS neighborhood_id,
  c.id AS municipality_id,
  t.id AS city_id,
  p.id AS province_id,
  co.id AS country_id
FROM osm_boundaries b
JOIN neighborhood g
  ON ST_Contains(g.geom, ST_PointOnSurface(b.geom))
JOIN municipality c
  ON c.id = g.municipality_id
JOIN city t
  ON t.id = g.city_id
JOIN province p
  ON p.id = g.province_id
JOIN country co
  ON co.id = g.country_id
WHERE b.hierarchy_level = 9;

ALTER TABLE locality ADD PRIMARY KEY (id);
CREATE INDEX locality_geom_idx ON locality USING GIST (geom);

-- 8. Bloc / subdivision interne (level 10)
CREATE TABLE bloc AS
SELECT
  b.id,
  lower(btrim(b.name)) AS name,
  10 AS hierarchy_level,
  b.geom,
  l.id AS locality_id,
  g.id AS neighborhood_id,
  t.id AS city_id,
  p.id AS province_id,
  co.id AS country_id
FROM osm_boundaries b
JOIN locality l
  ON ST_Contains(l.geom, ST_PointOnSurface(b.geom))
JOIN neighborhood g
  ON g.id = l.neighborhood_id
JOIN city t
  ON t.id = l.city_id
JOIN province p
  ON p.id = l.province_id
JOIN country co
  ON co.id = l.country_id
WHERE b.hierarchy_level = 10;

ALTER TABLE bloc ADD PRIMARY KEY (id);
CREATE INDEX bloc_geom_idx ON bloc USING GIST (geom);

-- 9. Routes (nommées/référencées) avec rattachement administratif
CREATE TABLE road AS
WITH base AS (
  SELECT
    id,
    lower(btrim(name)) AS name,
    lower(btrim(ref)) AS ref,
    lower(btrim(highway)) AS highway,
    geom,
    ST_LineInterpolatePoint(geom, 0.5) AS anchor
  FROM osm_roads
  WHERE highway IS NOT NULL
    AND (name IS NOT NULL OR ref IS NOT NULL)
)
SELECT
  b.id,
  b.name,
  b.ref,
  b.highway,
  b.geom,
  bl.id AS bloc_id,
  l.id AS locality_id,
  n.id AS neighborhood_id,
  m.id AS municipality_id,
  ci.id AS city_id,
  p.id AS province_id,
  co.id AS country_id
FROM base b
LEFT JOIN bloc bl ON ST_Contains(bl.geom, b.anchor)
LEFT JOIN locality l ON ST_Contains(l.geom, b.anchor)
LEFT JOIN neighborhood n ON ST_Contains(n.geom, b.anchor)
LEFT JOIN municipality m ON ST_Contains(m.geom, b.anchor)
LEFT JOIN city ci ON ST_Contains(ci.geom, b.anchor)
LEFT JOIN province p ON ST_Contains(p.geom, b.anchor)
LEFT JOIN country co ON ST_Contains(co.geom, b.anchor);

ALTER TABLE road ADD PRIMARY KEY (id);
CREATE INDEX road_geom_idx ON road USING GIST (geom);
CREATE INDEX road_highway_idx ON road (highway);
