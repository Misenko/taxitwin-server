SELECT taxitwin.id, p1.latitude AS start_lat, p1.longitude AS start_long, p1.textual AS start_text, p2.latitude AS end_lat, p2.longitude AS end_long, p2.textual AS end_text, taxitwin.passengers AS passengers_total, COALESCE(partics.passengers, 0) AS passengers, device.name, device.google_id, taxitwin.radius FROM taxitwin INNER JOIN point AS p1 ON taxitwin.start_point_id = p1.id INNER JOIN point AS p2 ON taxitwin.end_point_id = p2.id INNER JOIN device ON taxitwin.device_id = device.id LEFT OUTER JOIN (SELECT share.id, COUNT(share_id) AS passengers, share.owner_taxitwin_id FROM share INNER JOIN participants ON share.id = participants.share_id GROUP BY share.id) AS partics ON taxitwin.id = partics.owner_taxitwin_id WHERE device.google_id = $1
