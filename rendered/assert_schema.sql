DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE column_name = 'tenant_id'
      AND data_type <> 'bigint'
  ) THEN
    RAISE EXCEPTION 'sharding column tenant_id is not bigint';
  END IF;
END $$;
