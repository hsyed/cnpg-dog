DROP TABLE IF EXISTS events;
CREATE TABLE events (
    id        BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    payload   TEXT   NOT NULL,
    PRIMARY KEY (id, tenant_id)
);

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id        BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    amount    BIGINT NOT NULL,
    PRIMARY KEY (id, tenant_id)
);
