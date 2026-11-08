-- Empties every table in public before a test restore, so the throwaway
-- database holds only what the backup brings (the migrations seed some
-- reference rows).
do $$
declare
  t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  loop
    execute format('truncate table public.%I cascade', t);
  end loop;
end;
$$;
