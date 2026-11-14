-- Every table in public as one "table|rows|md5" line, sorted: the row count
-- and a checksum of every row's values, so the backup workflow proves the
-- restored database holds the same data as the live one, not just as many
-- rows. Run with PGTZ=UTC on both sides so timestamps print the same.
select format('%s|%s|%s', c.relname,
  (xpath('/row/n/text()', query_to_xml(format(
    'select count(*) as n from public.%I', c.relname), false, true, '')))[1]::text,
  (xpath('/row/h/text()', query_to_xml(format(
    'select coalesce(md5(string_agg(t::text, E''\n'' order by t::text)), ''-'') as h from public.%I t',
    c.relname), false, true, '')))[1]::text)
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;
