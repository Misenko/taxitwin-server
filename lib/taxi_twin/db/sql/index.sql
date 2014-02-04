point_geom$CREATE INDEX point_geom ON point USING GIST(geom);
device_name$CREATE INDEX device_name ON device USING HASH(name);
