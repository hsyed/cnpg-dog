package render

import (
	"strings"
	"github.com/hsyed/cnpg-dog/lib"
)

// assertSchema renders to rendered/assert_schema.sql: a query that fails if the
// real column type drifts from what PgDog was told (lib.fabric.tables).
assertSchema: {
	_lines: [for t in lib.fabric.tables {
		"""
		DO $$ BEGIN
		  IF NOT EXISTS (
		    SELECT 1 FROM information_schema.columns
		    WHERE table_name = '\(t.table)'
		      AND column_name = '\(t.column)'
		      AND data_type = '\(t.dataType)'
		  ) THEN
		    RAISE EXCEPTION 'sharding key \(t.table).\(t.column) is not \(t.dataType)';
		  END IF;
		END $$;
		"""
	}]
	out: strings.Join(_lines, "\n")
}
