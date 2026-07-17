-- Run with psql against both source and target and diff the captured output.
-- Counts and deterministic per-table hashes cover the current application data.
\pset tuples_only on
\pset format unaligned

SELECT 'schema=' || current_schema();
SELECT 'tables=' || count(*)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';

SELECT format(
  'SELECT %L AS table_name, count(*) AS row_count, md5(coalesce(string_agg(md5(t::text), '''' ORDER BY md5(t::text)), '''')) AS digest FROM %I.%I t;',
  table_schema || '.' || table_name,
  table_schema,
  table_name
)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name
\gexec

SELECT sequence_schema || '.' || sequence_name || '=' || coalesce(p.last_value::text, 'null')
FROM information_schema.sequences s
JOIN pg_sequences p
  ON p.schemaname = s.sequence_schema AND p.sequencename = s.sequence_name
WHERE sequence_schema = 'public'
ORDER BY sequence_name;
