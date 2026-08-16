package render

import (
	"strings"
	"github.com/hsyed/cnpg-dog/lib"
)

// Postgres information_schema.data_type names accepted for each PgDog
// sharding type. PgDog's "bigint" covers integer/smallint; "varchar" covers
// character varying/text.
_pgTypes: {
	"bigint":  ["bigint", "integer", "smallint"]
	"uuid":    ["uuid"]
	"varchar": ["character varying", "text"]
}

// assertSchema renders to rendered/assert_schema.sql: a query per sharded
// column that fails if the column's type drifts from what PgDog was told. A
// table-scoped column (name set) is checked only on that table; a column-scoped
// one is checked across all tables.
assertSchema: {
	_lines: [for c in lib.fabric.shardedColumns {
		_table: strings.Join([if c.name != _|_ { " AND table_name = '\(c.name)'" }], "")
		_types: strings.Join([for t in _pgTypes[c.dataType] { "'\(t)'" }], ", ")
		"""
		DO $$ BEGIN
		  IF EXISTS (
		    SELECT 1 FROM information_schema.columns
		    WHERE column_name = '\(c.column)'
		      AND data_type NOT IN (\(_types))\(_table)
		  ) THEN
		    RAISE EXCEPTION 'sharding key \(c.column) is not \(c.dataType)';
		  END IF;
		END $$;
		"""
	}]
	out: strings.Join(_lines, "\n")
}
