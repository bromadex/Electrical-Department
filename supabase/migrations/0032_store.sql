-- 0032_store: the electrical store, stock basics (API.md section 13b,
-- first half of issue #12). Items with I- codes and stock on hand per site;
-- stock moves only through functions: receive, and issue to a job card or a
-- person. Stock never goes below zero; falling under an item's minimum
-- alerts the store and supervisors. Returns, adjustments and stock counts
-- come with the second half.

create table public.store_items (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  code text not null,
  name text not null check (length(trim(name)) between 2 and 120),
  unit text not null default 'pcs' check (length(trim(unit)) between 1 and 12),
  category text not null default 'other' check (category in (
    'cable', 'breakers', 'lugs', 'glands', 'lamps', 'fittings', 'consumables', 'other'
  )),
  bin text check (length(bin) <= 40),
  min_level numeric(12, 2) not null default 0 check (min_level >= 0),
  on_hand numeric(12, 2) not null default 0 check (on_hand >= 0),
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create unique index store_items_name on public.store_items (site_id, lower(name), lower(unit))
  where not is_archived;
create trigger store_items_touch before update on public.store_items
  for each row execute function public.fn_touch_updated_at();

-- Every change to stock on hand; qty is signed (+ in, - out).
create table public.stock_moves (
  id uuid primary key,
  item_id uuid not null references public.store_items (id),
  site_id uuid not null references public.sites (id),
  kind text not null check (kind in ('receive', 'issue')),
  qty numeric(12, 2) not null check (qty <> 0),
  balance_after numeric(12, 2) not null check (balance_after >= 0),
  job_card_id uuid references public.job_cards (id),
  to_user uuid references public.profiles (id),
  to_name text check (length(to_name) <= 120),
  note text check (length(note) <= 500),
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index stock_moves_item on public.stock_moves (item_id, created_at desc);
create index stock_moves_job on public.stock_moves (job_card_id) where job_card_id is not null;

-- Creates or edits an item (store.adjust). Stock on hand is never set here.
create function public.fn_save_item(
  p_client_ref uuid,
  p_site uuid,
  p_name text,
  p_unit text,
  p_category text,
  p_bin text,
  p_min_level numeric,
  p_archived boolean
)
returns public.store_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.store_items;
begin
  if not public._can('store.adjust', p_site) then
    raise exception 'NOT_ALLOWED: Only the store can add or edit items';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 120 then
    raise exception 'INVALID: The item name needs 2 to 120 characters';
  end if;
  if coalesce(p_min_level, 0) < 0 then
    raise exception 'INVALID: The minimum level cannot be negative';
  end if;
  if not coalesce(p_archived, false) and exists (
    select 1 from public.store_items
    where site_id = p_site and lower(name) = lower(trim(p_name))
      and lower(unit) = lower(trim(coalesce(p_unit, 'pcs'))) and not is_archived and id <> p_client_ref
  ) then
    raise exception 'CONFLICT: % is already in the store', trim(p_name);
  end if;

  select * into v from public.store_items where id = p_client_ref for update;
  if found then
    if v.site_id <> p_site then
      raise exception 'INVALID: Item belongs to another site';
    end if;
    update public.store_items
    set name = trim(p_name), unit = trim(coalesce(p_unit, 'pcs')), category = coalesce(p_category, 'other'),
        bin = nullif(trim(coalesce(p_bin, '')), ''), min_level = coalesce(p_min_level, 0),
        is_archived = coalesce(p_archived, false)
    where id = v.id
    returning * into v;
    return v;
  end if;

  insert into public.store_items (id, site_id, code, name, unit, category, bin, min_level)
  values (p_client_ref, p_site, public.next_code(p_site, 'I'), trim(p_name), trim(coalesce(p_unit, 'pcs')),
    coalesce(p_category, 'other'), nullif(trim(coalesce(p_bin, '')), ''), coalesce(p_min_level, 0))
  returning * into v;
  return v;
end;
$$;

-- Moves stock: locks the item, refuses to go below zero, records the move
-- and alerts the store and supervisors when it falls under the minimum.
create function public._stock_move(
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
  if p_kind = 'receive' and not public._can('store.receive', i.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can receive stock';
  end if;
  if p_kind = 'issue' and not public._can('store.issue', i.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can issue stock';
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

-- Stock coming in (store.receive).
create function public.fn_receive_stock(p_client_ref uuid, p_item uuid, p_qty numeric, p_note text)
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
  if coalesce(p_qty, 0) <= 0 then
    raise exception 'INVALID: Receive more than zero';
  end if;
  return public._stock_move(p_client_ref, p_item, 'receive', p_qty, null, null, null, p_note);
end;
$$;

-- Stock going out (store.issue) to a job card at the same site, an app
-- user, or someone named.
create function public.fn_issue_stock(
  p_client_ref uuid,
  p_item uuid,
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
  m public.stock_moves;
  v_site uuid;
begin
  select * into m from public.stock_moves where id = p_client_ref;
  if found then
    return m;
  end if;
  if coalesce(p_qty, 0) <= 0 then
    raise exception 'INVALID: Issue more than zero';
  end if;
  if p_job_card is null and p_to is null and length(trim(coalesce(p_to_name, ''))) = 0 then
    raise exception 'INVALID: Say which job card or who it is for';
  end if;
  select site_id into v_site from public.store_items where id = p_item;
  if p_job_card is not null and not exists (
    select 1 from public.job_cards where id = p_job_card and site_id = v_site and not is_archived
  ) then
    raise exception 'INVALID: That job card is not at this site';
  end if;
  return public._stock_move(p_client_ref, p_item, 'issue', -p_qty, p_job_card, p_to, p_to_name, p_note);
end;
$$;

alter table public.store_items enable row level security;
alter table public.stock_moves enable row level security;
create policy store_items_select on public.store_items for select to authenticated
  using (public._can('store.view', site_id));
create policy stock_moves_select on public.stock_moves for select to authenticated
  using (public._can('store.view', site_id));
revoke all on public.store_items, public.stock_moves from anon;
revoke insert, update, delete on public.store_items, public.stock_moves from authenticated;

revoke execute on function
  public.fn_save_item(uuid, uuid, text, text, text, text, numeric, boolean),
  public._stock_move(uuid, uuid, text, numeric, uuid, uuid, text, text),
  public.fn_receive_stock(uuid, uuid, numeric, text),
  public.fn_issue_stock(uuid, uuid, numeric, uuid, uuid, text, text)
from public, anon, authenticated;
grant execute on function
  public.fn_save_item(uuid, uuid, text, text, text, text, numeric, boolean),
  public.fn_receive_stock(uuid, uuid, numeric, text),
  public.fn_issue_stock(uuid, uuid, numeric, uuid, uuid, text, text)
to authenticated;

insert into public.schema_migrations (filename) values ('0032_store.sql')
on conflict do nothing;
