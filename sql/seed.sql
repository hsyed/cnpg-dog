INSERT INTO events (tenant_id, payload)
SELECT (g % 40) + 1, 'payload-' || g
FROM generate_series(1, 400) g;
