CREATE TABLE IF NOT EXISTS device(id SERIAL PRIMARY KEY, google_id VARCHAR(200) NOT NULL, name VARCHAR(30) NOT NULL);
CREATE TABLE IF NOT EXISTS point(id SERIAL PRIMARY KEY, latitude DOUBLE PRECISION NOT NULL, longitude DOUBLE PRECISION NOT NULL, geom GEOMETRY(POINT,4326) NOT NULL, textual VARCHAR(500) NOT NULL);
CREATE TABLE IF NOT EXISTS taxitwin(id SERIAL PRIMARY KEY, device_id INTEGER REFERENCES device(id), start_point_id INTEGER REFERENCES point(id), end_point_id INTEGER REFERENCES point(id), radius DOUBLE PRECISION NOT NULL, passengers INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS share(id SERIAL PRIMARY KEY, owner_taxitwin_id INTEGER REFERENCES taxitwin(id));
CREATE TABLE IF NOT EXISTS participants(share_id INTEGER REFERENCES share(id), device_id INTEGER REFERENCES device(id), PRIMARY KEY(share_id, device_id));
CREATE TABLE IF NOT EXISTS pending_offer(for_device_id INTEGER REFERENCES device(id), offer_taxitwin_id INTEGER REFERENCES taxitwin(id), PRIMARY KEY(for_device_id, offer_taxitwin_id));
CREATE TABLE IF NOT EXISTS pending_response(from_device_id INTEGER REFERENCES device(id), to_device_id INTEGER REFERENCES device(id), PRIMARY KEY(from_device_id, to_device_id));

