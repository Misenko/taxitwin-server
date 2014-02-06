point_geom$CREATE INDEX point_geom ON point USING GIST(geom);
device_google_id$CREATE INDEX device_google_id ON device USING HASH(google_id);
