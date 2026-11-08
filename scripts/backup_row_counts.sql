-- Row counts of every table in public, one "table|rows" line each, sorted;
-- the backup workflow compares the live database with the restored one.
select format('%s|%s', c.relname,
  (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from public.%I', c.relname), false, true, '')))[1]::text)
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;
