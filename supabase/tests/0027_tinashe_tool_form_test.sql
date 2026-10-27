-- Behaviour checks for 0027_tinashe_tool_form. Runs in a transaction and rolls back.
begin;

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.as_owner() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok - %', p_label;
end $$;

create function pg_temp.fails(p_sql text, p_code text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAILED: % (no error)', p_label;
exception when others then
  if sqlerrm like 'FAILED:%' then raise; end if;
  if p_code <> '' and sqlerrm not like p_code || ':%' then
    raise exception 'FAILED: % (got: %)', p_label, sqlerrm;
  end if;
  raise notice 'ok - %', p_label;
end $$;

-- A Harare site (renamed if one exists already) gets the form once.
update public.sites set name = name || ' (kept)' where lower(trim(name)) = 'harare';
insert into public.sites (id, code, name) values ('f7000000-0000-0000-0000-0000000000a1', 'TNF', 'Harare');
select pg_temp.check(public._record_tinashe_form() = 1, 'the form is recorded at Harare');
select pg_temp.check(public._record_tinashe_form() = 0, 'and only once');
select pg_temp.check((select count(*) = 1 from public.tool_issue_forms
  where site_id = 'f7000000-0000-0000-0000-0000000000a1' and recipient_name = 'Tinashe Mademe'
    and company = 'Manhattan' and team_lead = 'Elia Manjawu' and code = 'TI-0001' and status = 'out'),
  'one TI form for Tinashe Mademe of Manhattan');
select pg_temp.check((select count(*) = 15 and count(*) filter (where holder_name = 'Tinashe Mademe') = 15
    and count(*) filter (where serial_no = '67510984WS') = 1
  from public.tools where site_id = 'f7000000-0000-0000-0000-0000000000a1'),
  'the 15 tools are in the register, out with him');
select pg_temp.check((select count(*) = 15 from public.tool_issues i
  join public.tool_issue_forms f on f.id = i.form_id
  where f.site_id = 'f7000000-0000-0000-0000-0000000000a1' and i.returned_at is null),
  'each tool has an open issue on the form');

rollback;
