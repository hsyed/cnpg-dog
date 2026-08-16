DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'events'
      AND column_name = 'tenant_id'
      AND data_type = 'bigint'
  ) THEN
    RAISE EXCEPTION 'sharding key events.tenant_id is not bigint';
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders'
      AND column_name = 'tenant_id'
      AND data_type = 'bigint'
  ) THEN
    RAISE EXCEPTION 'sharding key orders.tenant_id is not bigint';
  END IF;
END $$;
