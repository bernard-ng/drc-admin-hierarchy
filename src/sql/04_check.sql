SET search_path TO public;

-- 1. Distribution of hierarchy_level in raw boundaries
SELECT hierarchy_level, COUNT(*) AS cnt
FROM osm_boundaries
GROUP BY hierarchy_level
ORDER BY hierarchy_level;

-- 2. Basic sizes of derived tables
SELECT 'country' AS table, COUNT(*) AS cnt FROM country
UNION ALL
SELECT 'province', COUNT(*) FROM province
UNION ALL
SELECT 'city', COUNT(*) FROM city
UNION ALL
SELECT 'municipality', COUNT(*) FROM municipality
UNION ALL
SELECT 'neighborhood', COUNT(*) FROM neighborhood
UNION ALL
SELECT 'locality', COUNT(*) FROM locality
UNION ALL
SELECT 'bloc', COUNT(*) FROM bloc
UNION ALL
SELECT 'road', COUNT(*) FROM road;

-- 3. Check some hierarchy examples (random)
SELECT
  l.name AS locality,
  g.name AS neighborhood,
  c.name AS municipality,
  t.name AS city,
  p.name AS province,
  co.name AS country
FROM locality l
LEFT JOIN neighborhood g
  ON g.id = l.neighborhood_id
LEFT JOIN municipality c
  ON c.id = l.municipality_id
LEFT JOIN city t
  ON t.id = l.city_id
LEFT JOIN province p
  ON p.id = l.province_id
LEFT JOIN country co
  ON co.id = l.country_id
LIMIT 20;

-- 4. Check that each level is contained in the parent
SELECT 'province->country' AS check, COUNT(*) AS bad_count
FROM province p
LEFT JOIN country c
  ON ST_Contains(c.geom, ST_PointOnSurface(p.geom))
WHERE c.id IS NULL

UNION ALL
SELECT 'city->province', COUNT(*)
FROM city t
LEFT JOIN province p
  ON ST_Contains(p.geom, ST_PointOnSurface(t.geom))
WHERE p.id IS NULL

UNION ALL
SELECT 'municipality->city', COUNT(*)
FROM municipality c
LEFT JOIN city t
  ON ST_Contains(t.geom, ST_PointOnSurface(c.geom))
WHERE t.id IS NULL

UNION ALL
SELECT 'neighborhood->municipality', COUNT(*)
FROM neighborhood g
LEFT JOIN municipality c
  ON ST_Contains(c.geom, ST_PointOnSurface(g.geom))
WHERE c.id IS NULL

UNION ALL
SELECT 'locality->neighborhood', COUNT(*)
FROM locality l
LEFT JOIN neighborhood g
  ON ST_Contains(g.geom, ST_PointOnSurface(l.geom))
WHERE g.id IS NULL
;
