WITH table_contracts AS (
  SELECT
    namespace.nspname AS schema_name,
    relation.relname AS table_name,
    relation.relreplident AS replica_identity,
    EXISTS (
      SELECT 1
      FROM pg_index
      WHERE pg_index.indrelid = relation.oid
        AND pg_index.indisprimary
    ) AS has_primary_key,
    md5(string_agg(
      attribute.attname
      || ':' || pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
      || ':' || attribute.attnotnull::text
      || ':' || coalesce(pg_get_expr(attribute_default.adbin, attribute_default.adrelid), ''),
      '|' ORDER BY attribute.attnum
    )) AS column_contract_hash,
    pg_total_relation_size(relation.oid) AS total_bytes
  FROM pg_class AS relation
  JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
  JOIN pg_attribute AS attribute ON attribute.attrelid = relation.oid
  LEFT JOIN pg_attrdef AS attribute_default
    ON attribute_default.adrelid = relation.oid
    AND attribute_default.adnum = attribute.attnum
  WHERE namespace.nspname IN ('public', 'auth', 'storage')
    AND relation.relkind IN ('r', 'p')
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
  GROUP BY namespace.nspname, relation.relname, relation.relreplident, relation.oid
)
SELECT
  schema_name
  || '|' || table_name
  || '|' || replica_identity::text
  || '|' || has_primary_key
  || '|' || column_contract_hash
  || '|' || total_bytes
FROM table_contracts
ORDER BY schema_name, table_name;
