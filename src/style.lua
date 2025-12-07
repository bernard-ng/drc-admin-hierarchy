local tables = {}

tables.boundaries = osm2pgsql.define_table{
  name   = 'osm_boundaries',
  schema = 'public',
  ids    = { type = 'any', id_column = 'id' },
  columns = {
    { column = 'hierarchy_level', type = 'int' },
    { column = 'name',            type = 'text' },
    { column = 'tags',            type = 'hstore' },
    { column = 'geom',            type = 'geometry', not_null = true },
  }
}

tables.places = osm2pgsql.define_table{
  name   = 'osm_places',
  schema = 'public',
  ids    = { type = 'any', id_column = 'id' },
  columns = {
    { column = 'place', type = 'text' },
    { column = 'name',  type = 'text' },
    { column = 'tags',  type = 'hstore' },
    { column = 'geom',  type = 'geometry', not_null = true },
  }
}

tables.roads = osm2pgsql.define_table{
  name   = 'osm_roads',
  schema = 'public',
  ids    = { type = 'way', id_column = 'id' },
  columns = {
    { column = 'highway', type = 'text' },
    { column = 'name',    type = 'text' },
    { column = 'ref',     type = 'text' },
    { column = 'tags',    type = 'hstore' },
    { column = 'geom',    type = 'geometry', not_null = true },
  }
}

-- Relations: administrative boundaries
function osm2pgsql.process_relation(object)
  local tags = object.tags
  if tags.boundary == 'administrative' and tags.admin_level then
    local admin_level = tonumber(tags.admin_level)
    if admin_level ~= nil then
      local geom = object:as_multipolygon()
      if geom then
        tables.boundaries:insert{
          id               = object.id,
          hierarchy_level  = admin_level,
          name             = tags.name,
          tags             = tags,
          geom             = geom,
        }
      end
    end
  end
end

-- Ways: highways and polygonal places
function osm2pgsql.process_way(object)
  local tags = object.tags

  if tags.highway then
    local geom = object:as_linestring()
    if geom then
      tables.roads:insert{
        id      = object.id,
        highway = tags.highway,
        name    = tags.name,
        ref     = tags.ref,
        tags    = tags,
        geom    = geom,
      }
    end
  end

  if tags.place then
    local geom = object:as_multipolygon() or object:as_linestring()
    if geom then
      tables.places:insert{
        id    = object.id,
        place = tags.place,
        name  = tags.name,
        tags  = tags,
        geom  = geom,
      }
    end
  end
end

-- Nodes: point places
function osm2pgsql.process_node(object)
  local tags = object.tags
  if tags.place then
    local geom = object:as_point()
    if geom then
      tables.places:insert{
        id    = object.id,
        place = tags.place,
        name  = tags.name,
        tags  = tags,
        geom  = geom,
      }
    end
  end
end
