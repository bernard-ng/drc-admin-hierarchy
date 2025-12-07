SET search_path TO public;

DROP VIEW IF EXISTS address_units_flat CASCADE;
DROP VIEW IF EXISTS address_units CASCADE;

CREATE VIEW address_units AS
SELECT
  l.id  AS locality_id,
  l.name AS locality_name,
  g.id  AS neighborhood_id,
  g.name AS neighborhood_name,
  c.id  AS municipality_id,
  c.name AS municipality_name,
  t.id  AS city_id,
  t.name AS city_name,
  p.id  AS province_id,
  p.name AS province_name,
  co.id AS country_id,
  co.name AS country_name
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
  ON co.id = l.country_id;

CREATE VIEW address_units_flat AS
SELECT
  locality_id,
  concat_ws(
    ', ',
    locality_name,
    neighborhood_name,
    city_name,
    province_name
  ) AS label
FROM address_units;
