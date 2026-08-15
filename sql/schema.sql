CREATE TABLE IF NOT EXISTS events (
    id        BIGSERIAL,
    tenant_id BIGINT NOT NULL,
    payload   TEXT   NOT NULL,
    PRIMARY KEY (id, tenant_id)
);
