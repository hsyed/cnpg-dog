package render

import (
	"strings"
	"github.com/hsyed/cnpg-dog/lib"
)

// assertSchema renders to rendered/assert_schema.sql: a query that fails if any
// table's sharding column drifts from the type PgDog was told
// (lib.fabric.shardedColumns).
assertSchema: {
	_lines: [for c in lib.fabric.shardedColumns {
		"""
		DO $$ BEGIN
		  IF EXISTS (
		    SELECT 1 FROM information_schema.columns
		    WHERE column_name = '\(c.column)'
		      AND data_type <> '\(c.dataType)'
		  ) THEN
		    RAISE EXCEPTION 'sharding column \(c.column) is not \(c.dataType)';
		  END IF;
		END $$;
		"""
	}]
	out: strings.Join(_lines, "\n")
}
