-- 0033_store_returns_counts: the electrical store, second half (API.md
-- section 13b, issue #12 part 2). Returns into the store, adjustments with a
-- reason, and stock counts that correct stock on hand item by item.

alter table public.stock_moves drop constraint stock_moves_kind_check;
alter table public.stock_moves add constraint stock_moves_kind_check
  check (kind in ('receive', 'issue', 'return', 'adjust', 'count'));
alter table public.stock_moves add column count_id uuid;

-- A stock count: what was on the shelf, item by item.
create table public.stock_counts (
  id uuid primary key,
  site_id uuid not null references public.sites (id),
  note text check (length(note) <= 500),
  items integer not null default 0,
  differences integer not null default 0,
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.stock_count_lines (
  count_id uuid not null references public.stock_counts (id),
  item_id uuid not null references public.store_items (id),
  expected numeric(12, 2) not null,
  counted numeric(12, 2) not null check (counted >= 0),
  primary key (count_id, item_id)
);

alter table public.stock_moves add constraint stock_moves_count_fk
  foreign key (count_id) references public.stock_counts (id);

-- The move itself, as in 0032, with the new kinds and their permissions.
create or replace function public._stock_move(
  p_id uuid,
  p_item uuid,
  p_kind text,
  p_qty numeric,
  p_job_card uuid,
  p_to uuid,
  p_to_name text,
  p_note text
)
returns public.stock_moves
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.store_items;
  m public.stock_moves;
  v_new numeric;
begin
  select * into i from public.store_items where id = p_item and not is_archived for update;
  if not found or not public._can('store.view', i.site_id) then
    raise exception 'NOT_FOUND: Item not found';
  end if;
  if p_kind in ('receive', 'return') and not public._can('store.receive', i.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can take stock in';
  end if;
  if p_kind = 'issue' and not public._can('store.issue', i.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can issue stock';
  end if;
  if p_kind in ('adjust', 'count') and not public._can('store.adjust', i.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can correct stock';
  end if;
  v_new := i.on_hand + p_qty;
  if v_new < 0 then
    raise exception 'INVALID: Only % % of % in stock', trim(to_char(i.on_hand, 'FM999999990.##')), i.unit, i.name;
  end if;

  update public.store_items set on_hand = v_new where id = i.id;
  insert into public.stock_moves (id, item_id, site_id, kind, qty, balance_after, job_card_id, to_user, to_name, note)
  values (p_id, i.id, i.site_id, p_kind, p_qty, v_new, p_job_card, p_to,
    nullif(trim(coalesce(p_to_name, '')), ''), nullif(trim(coalesce(p_note, '')), ''))
  returning * into m;

  if i.min_level > 0 and v_new < i.min_level and i.on_hand >= i.min_level then
    perform public.fn_notify_permission(i.site_id, 'store.issue', 'low_stock',
      'Low stock: ' || i.code || ' ' || i.name,
      trim(to_char(v_new, 'FM999999990.##')) || ' ' || i.unit || ' left (minimum '
        || trim(to_char(i.min_level, 'FM999999990.##')) || ')', 'item:' || i.id);
    perform public.fn_notify_permission(i.site_id, 'mr.approve', 'low_stock',
      'Low stock: ' || i.code || ' ' || i.name,
      trim(to_char(v_new, 'FM999999990.##')) || ' ' || i.unit || ' left (minimum '
        || trim(to_char(i.min_level, 'FM999999990.##')) || ')', 'item:' || i.id);
  end if;
  return m;
end;
$$;

-- Stock coming back unused (store.receive), from a job card at the item's
-- site, an app user or someone named. to_user / to_name hold who returned it.
create function public.fn_return_stock(
  p_client_ref uuid,
  p_item uuid,
  p_qty numeric,
  p_job_card uuid,
  p_from uuid,
  p_from_name text,
  p_note text
)
returns public.stock_moves
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.stock_moves;
  v_site uuid;
begin
  select * into m from public.stock_moves where id = p_client_ref;
  if found then
    return m;
  end if;
  if coalesce(p_qty, 0) <= 0 then
    raise exception 'INVALID: Return more than zero';
  end if;
  select site_id into v_site from public.store_items where id = p_item;
  if p_job_card is not null and not exists (
    select 1 from public.job_cards where id = p_job_card and site_id = v_site and not is_archived
  ) then
    raise exception 'INVALID: That job card is not at this site';
  end if;
  return public._stock_move(p_client_ref, p_item, 'return', p_qty, p_job_card, p_from, p_from_name, p_note);
end;
$$;

-- Corrects stock by p_delta (store.adjust), with the reason: damaged,
-- found, written off and so on.
create function public.fn_adjust_stock(p_client_ref uuid, p_item uuid, p_delta numeric, p_reason text)
returns public.stock_moves
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.stock_moves;
begin
  select * into m from public.stock_moves where id = p_client_ref;
  if found then
    return m;
  end if;
  if coalesce(p_delta, 0) = 0 then
    raise exception 'INVALID: Adjust by more or less than zero';
  end if;
  if length(trim(coalesce(p_reason, ''))) not between 3 and 300 then
    raise exception 'INVALID: Say why stock changes';
  end if;
  return public._stock_move(p_client_ref, p_item, 'adjust', p_delta, null, null, null, p_reason);
end;
$$;

-- Records a count (store.adjust): p_lines is [{item_id, counted}] for items
-- at p_site. Each item whose count differs from stock on hand gets a count
-- move to the counted amount.
create function public.fn_submit_count(p_client_ref uuid, p_site uuid, p_lines jsonb, p_note text)
returns public.stock_counts
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.stock_counts;
  l record;
  i public.store_items;
  m public.stock_moves;
  v_items integer := 0;
  v_diff integer := 0;
begin
  select * into c from public.stock_counts where id = p_client_ref;
  if found then
    return c;
  end if;
  if not public._can('store.adjust', p_site) then
    raise exception 'NOT_ALLOWED: Only the store can count stock';
  end if;
  if jsonb_typeof(coalesce(p_lines, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 then
    raise exception 'INVALID: Count at least one item';
  end if;

  insert into public.stock_counts (id, site_id, note)
  values (p_client_ref, p_site, nullif(trim(coalesce(p_note, '')), ''))
  returning * into c;

  for l in
    select (x ->> 'item_id')::uuid as item_id, (x ->> 'counted')::numeric as counted
    from jsonb_array_elements(p_lines) x
  loop
    select * into i from public.store_items where id = l.item_id and not is_archived for update;
    if not found or i.site_id <> p_site then
      raise exception 'INVALID: An item is not in this site''s store';
    end if;
    if l.counted is null or l.counted < 0 then
      raise exception 'INVALID: Counts are 0 or more';
    end if;
    insert into public.stock_count_lines (count_id, item_id, expected, counted)
    values (c.id, i.id, i.on_hand, l.counted);
    v_items := v_items + 1;
    if l.counted <> i.on_hand then
      m := public._stock_move(gen_random_uuid(), i.id, 'count', l.counted - i.on_hand, null, null, null,
        'Count: ' || trim(to_char(i.on_hand, 'FM999999990.##')) || ' expected, '
          || trim(to_char(l.counted, 'FM999999990.##')) || ' counted');
      update public.stock_moves set count_id = c.id where id = m.id;
      v_diff := v_diff + 1;
    end if;
  end loop;

  update public.stock_counts set items = v_items, differences = v_diff where id = c.id
  returning * into c;
  return c;
end;
$$;

alter table public.stock_counts enable row level security;
alter table public.stock_count_lines enable row level security;
create policy stock_counts_select on public.stock_counts for select to authenticated
  using (public._can('store.view', site_id));
create policy stock_count_lines_select on public.stock_count_lines for select to authenticated
  using (exists (select 1 from public.stock_counts c
    where c.id = stock_count_lines.count_id and public._can('store.view', c.site_id)));
revoke all on public.stock_counts, public.stock_count_lines from anon;
revoke insert, update, delete on public.stock_counts, public.stock_count_lines from authenticated;

revoke execute on function
  public.fn_return_stock(uuid, uuid, numeric, uuid, uuid, text, text),
  public.fn_adjust_stock(uuid, uuid, numeric, text),
  public.fn_submit_count(uuid, uuid, jsonb, text)
from public, anon;
grant execute on function
  public.fn_return_stock(uuid, uuid, numeric, uuid, uuid, text, text),
  public.fn_adjust_stock(uuid, uuid, numeric, text),
  public.fn_submit_count(uuid, uuid, jsonb, text)
to authenticated;

insert into public.schema_migrations (filename) values ('0033_store_returns_counts.sql')
on conflict do nothing;
