DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE column_name = 'tenant_id'
      AND data_type NOT IN ('bigint', 'integer', 'smallint')
  ) THEN
    RAISE EXCEPTION 'sharding key tenant_id is not bigint';
  END IF;
END $$;
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE column_name = 'company_id'
      AND data_type NOT IN ('uuid') AND table_name = 'users'
  ) THEN
    RAISE EXCEPTION 'sharding key company_id is not uuid';
  END IF;
END $$;
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE column_name = 'region'
      AND data_type NOT IN ('character varying', 'text')
  ) THEN
    RAISE EXCEPTION 'sharding key region is not varchar';
  END IF;
END $$;
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE column_name = 'order_id'
      AND data_type NOT IN ('bigint', 'integer', 'smallint')
  ) THEN
    RAISE EXCEPTION 'sharding key order_id is not bigint';
  END IF;
END $$;
