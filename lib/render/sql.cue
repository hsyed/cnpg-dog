package render

import "strings"

#Output: {
	topology: _

	_pgTypes: {
		"bigint": ["bigint", "integer", "smallint"]
		"uuid": ["uuid"]
		"varchar": ["character varying", "text"]
	}
	assertSchema: {
		_lines: [for c in topology.dog.shardedColumns {
			_table: strings.Join([if c.name != _|_ {" AND table_name = '\(c.name)'"}], "")
			_types: strings.Join([for t in _pgTypes[c.dataType] {"'\(t)'"}], ", ")
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
}
