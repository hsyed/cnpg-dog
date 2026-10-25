DROP TABLE IF EXISTS events;
CREATE TABLE events (
    id        BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    payload   TEXT   NOT NULL,
    PRIMARY KEY (id, tenant_id)
);

DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id         BIGSERIAL PRIMARY KEY,
    company_id UUID NOT NULL
);

DROP TABLE IF EXISTS regions;
CREATE TABLE regions (
    id     BIGSERIAL PRIMARY KEY,
    region VARCHAR NOT NULL
);

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id       BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL
);

-- Schema-sharded tenants: DDL routes to the schema's shard only.
DROP SCHEMA IF EXISTS customer_a CASCADE;
CREATE SCHEMA customer_a;
CREATE TABLE customer_a.notes (id BIGINT PRIMARY KEY, body TEXT NOT NULL);

DROP SCHEMA IF EXISTS customer_b CASCADE;
CREATE SCHEMA customer_b;
CREATE TABLE customer_b.notes (id BIGINT PRIMARY KEY, body TEXT NOT NULL);
