-- 0035_procurement: from "we need cable" to stock on the shelf (API.md
-- section 19, issue #13). Material requests (MR-) from a job card or a
-- project, approved by a supervisor, then issued from the store or bought;
-- purchase tracking (PO-, not accounting) received into the store; and a
-- bill of quantities (BOQ) per project compared with what was issued, is on
-- order and is in stock, whose shortfall becomes a material request.

-- ---------------------------------------------------------------------------
-- Suppliers (shared by all sites)
-- ---------------------------------------------------------------------------
create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  contact text check (length(contact) <= 120),
  phone text check (length(phone) <= 40),
  email text check (length(email) <= 120),
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index suppliers_name on public.suppliers (lower(name)) where not is_archived;

-- ---------------------------------------------------------------------------
-- Material requests
-- ---------------------------------------------------------------------------
create table public.material_requests (
  id uuid primary key,
  site_id uuid not null references public.sites (id),
  code text not null,
  job_card_id uuid references public.job_cards (id),
  project_id uuid references public.projects (id),
  requested_by uuid references public.profiles (id) default auth.uid(),
  needed_by date,
  note text check (length(note) <= 1000),
  status text not null default 'pending' check (status in (
    'pending', 'approved', 'rejected', 'part_issued', 'issued', 'cancelled'
  )),
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  decision_note text check (length(decision_note) <= 500),
  created_at timestamptz not null default now(),
  unique (site_id, code)
);

-- A line is a store item, or something not stocked (description and unit).
create table public.mr_lines (
  id uuid primary key default gen_random_uuid(),
  mr_id uuid not null references public.material_requests (id),
  item_id uuid references public.store_items (id),
  description text check (length(description) <= 200),
  unit text not null default 'pcs',
  qty numeric(12, 2) not null check (qty > 0),
  issued_qty numeric(12, 2) not null default 0 check (issued_qty >= 0),
  check (item_id is not null or length(trim(coalesce(description, ''))) >= 2)
);
create index mr_lines_mr on public.mr_lines (mr_id);

-- ---------------------------------------------------------------------------
-- Purchases
-- ---------------------------------------------------------------------------
create table public.purchase_orders (
  id uuid primary key,
  site_id uuid not null references public.sites (id),
  code text not null,
  supplier_id uuid references public.suppliers (id),
  po_number text check (length(po_number) <= 60),
  status text not null default 'requested' check (status in ('requested', 'ordered', 'delivered', 'cancelled')),
  expected_date date,
  note text check (length(note) <= 1000),
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now(),
  ordered_at timestamptz,
  delivered_at timestamptz,
  unique (site_id, code)
);

create table public.po_lines (
  id uuid primary key default gen_random_uuid(),
  po_id uuid not null references public.purchase_orders (id),
  item_id uuid references public.store_items (id),
  description text check (length(description) <= 200),
  unit text not null default 'pcs',
  qty numeric(12, 2) not null check (qty > 0),
  unit_price numeric(14, 2) check (unit_price >= 0),
  received_qty numeric(12, 2) not null default 0 check (received_qty >= 0),
  mr_line_id uuid references public.mr_lines (id),
  check (item_id is not null or length(trim(coalesce(description, ''))) >= 2)
);
create index po_lines_po on public.po_lines (po_id);
create index po_lines_mr_line on public.po_lines (mr_line_id) where mr_line_id is not null;

-- Each delivery received, so a repeat (outbox retry) changes nothing.
create table public.po_deliveries (
  id uuid primary key,
  po_id uuid not null references public.purchase_orders (id),
  note text,
  received_by uuid references public.profiles (id) default auth.uid(),
  received_at timestamptz not null default now()
);

alter table public.stock_moves add column mr_id uuid references public.material_requests (id);
alter table public.stock_moves add column po_id uuid references public.purchase_orders (id);

-- ---------------------------------------------------------------------------
-- Bill of quantities per project
-- ---------------------------------------------------------------------------
create table public.boq_lines (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  item_id uuid references public.store_items (id),
  description text not null check (length(trim(description)) between 2 and 200),
  unit text not null default 'pcs',
  qty numeric(12, 2) not null check (qty > 0),
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index boq_lines_project on public.boq_lines (project_id) where not is_archived;

-- Checks a list of lines and returns them cleaned: [{item_id, description,
-- unit, qty, ...}] with items at p_site; the unit comes from the item.
create function public._clean_lines(p_site uuid, p_lines jsonb)
returns table (item_id uuid, description text, unit text, qty numeric, extra jsonb)
language plpgsql
security definer
set search_path = ''
as $$
declare
  x jsonb;
  i public.store_items;
begin
  if jsonb_typeof(coalesce(p_lines, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 then
    raise exception 'INVALID: Add at least one line';
  end if;
  for x in select * from jsonb_array_elements(p_lines) loop
    qty := (x ->> 'qty')::numeric;
    if qty is null or qty <= 0 then
      raise exception 'INVALID: Quantities are more than zero';
    end if;
    item_id := nullif(x ->> 'item_id', '')::uuid;
    if item_id is not null then
      select * into i from public.store_items s where s.id = item_id and not s.is_archived;
      if not found or i.site_id <> p_site then
        raise exception 'INVALID: An item is not in this site''s store';
      end if;
      description := coalesce(nullif(trim(coalesce(x ->> 'description', '')), ''), i.name);
      unit := i.unit;
    else
      description := trim(coalesce(x ->> 'description', ''));
      if length(description) < 2 then
        raise exception 'INVALID: Describe what is needed';
      end if;
      unit := coalesce(nullif(trim(coalesce(x ->> 'unit', '')), ''), 'pcs');
    end if;
    extra := x;
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Material request functions
-- ---------------------------------------------------------------------------

-- Raises a request (mr.create) for a job card or project at p_site, or for
-- the site in general; supervisors (mr.approve) are asked to approve it.
create function public.fn_create_mr(
  p_client_ref uuid,
  p_site uuid,
  p_job_card uuid,
  p_project uuid,
  p_needed_by date,
  p_note text,
  p_lines jsonb
)
returns public.material_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.material_requests;
  l record;
begin
  select * into r from public.material_requests where id = p_client_ref;
  if found then
    return r;
  end if;
  if not public._can('mr.create', p_site) then
    raise exception 'NOT_ALLOWED: You cannot request materials at this site';
  end if;
  if p_job_card is not null and not exists (
    select 1 from public.job_cards where id = p_job_card and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That job card is not at this site';
  end if;
  if p_project is not null and not exists (
    select 1 from public.projects where id = p_project and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That project is not at this site';
  end if;

  insert into public.material_requests (id, site_id, code, job_card_id, project_id, needed_by, note)
  values (p_client_ref, p_site, public.next_code(p_site, 'MR'), p_job_card, p_project, p_needed_by,
    nullif(trim(coalesce(p_note, '')), ''))
  returning * into r;
  for l in select * from public._clean_lines(p_site, p_lines) loop
    insert into public.mr_lines (mr_id, item_id, description, unit, qty)
    values (r.id, l.item_id, l.description, l.unit, l.qty);
  end loop;

  perform public.fn_notify_permission(p_site, 'mr.approve', 'approval', r.code || ' to approve',
    (select count(*) from public.mr_lines where mr_id = r.id) || ' line(s)'
      || coalesce(' · needed by ' || to_char(p_needed_by, 'FMDD Mon'), ''), 'mr:' || r.id);
  return r;
end;
$$;

-- Approves or rejects a pending request (mr.approve); the requester is told.
create function public.fn_decide_mr(p_mr uuid, p_approve boolean, p_note text)
returns public.material_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.material_requests;
begin
  select * into r from public.material_requests where id = p_mr for update;
  if not found or not public._can('store.view', r.site_id) then
    raise exception 'NOT_FOUND: Material request not found';
  end if;
  if not public._can('mr.approve', r.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can approve material requests';
  end if;
  if r.status <> 'pending' then
    raise exception 'CONFLICT: % is already %', r.code, replace(r.status, '_', ' ');
  end if;
  if not coalesce(p_approve, false) and length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'INVALID: Say why it is rejected';
  end if;
  update public.material_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      decided_by = auth.uid(), decided_at = now(), decision_note = nullif(trim(coalesce(p_note, '')), '')
  where id = r.id
  returning * into r;
  if r.requested_by is distinct from auth.uid() then
    perform public.fn_notify(r.requested_by, r.site_id, 'approval',
      r.code || case when p_approve then ' approved' else ' rejected' end,
      coalesce(r.decision_note, case when p_approve then 'The store will issue it or order it.' end), 'mr:' || r.id);
  end if;
  if p_approve then
    perform public.fn_notify_permission(r.site_id, 'store.issue', 'approval', r.code || ' approved: issue or order',
      null, 'mr:' || r.id);
  end if;
  return r;
end;
$$;

-- Issues approved lines from the store (store.issue): p_lines is
-- [{line_id, qty}]. Stock goes to the request's job card (and project).
create function public.fn_issue_mr(p_client_ref uuid, p_mr uuid, p_lines jsonb)
returns public.material_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.material_requests;
  x jsonb;
  l public.mr_lines;
  m public.stock_moves;
  v_qty numeric;
  v_n integer := 0;
begin
  select * into r from public.material_requests where id = p_mr for update;
  if not found or not public._can('store.view', r.site_id) then
    raise exception 'NOT_FOUND: Material request not found';
  end if;
  -- A repeat of the same issue (outbox retry) changes nothing: its moves
  -- have ids made from the client ref and the line.
  if exists (select 1 from public.stock_moves sm join public.mr_lines ml on ml.mr_id = r.id
    where sm.id = md5(p_client_ref::text || ml.id::text)::uuid) then
    return r;
  end if;
  if not public._can('store.issue', r.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can issue materials';
  end if;
  if r.status not in ('approved', 'part_issued') then
    raise exception 'CONFLICT: % is %, not approved', r.code, replace(r.status, '_', ' ');
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    select * into l from public.mr_lines where id = (x ->> 'line_id')::uuid and mr_id = r.id for update;
    if not found then
      raise exception 'INVALID: That line is not on %', r.code;
    end if;
    if l.item_id is null then
      raise exception 'INVALID: % is not a store item; order it instead', l.description;
    end if;
    v_qty := (x ->> 'qty')::numeric;
    if v_qty is null or v_qty <= 0 then
      continue;
    end if;
    if l.issued_qty + v_qty > l.qty then
      raise exception 'INVALID: Only % % of % left to issue on %',
        trim(to_char(l.qty - l.issued_qty, 'FM999999990.##')), l.unit, l.description, r.code;
    end if;
    m := public._stock_move(md5(p_client_ref::text || l.id::text)::uuid, l.item_id, 'issue', -v_qty,
      r.job_card_id, r.requested_by, null, r.code);
    update public.stock_moves set mr_id = r.id, project_id = r.project_id where id = m.id;
    update public.mr_lines set issued_qty = issued_qty + v_qty where id = l.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'INVALID: Issue at least one line';
  end if;
  update public.material_requests
  set status = case when not exists (
      select 1 from public.mr_lines where mr_id = r.id and issued_qty < qty
    ) then 'issued' else 'part_issued' end
  where id = r.id
  returning * into r;
  if r.requested_by is distinct from auth.uid() then
    perform public.fn_notify(r.requested_by, r.site_id, 'general',
      r.code || case when r.status = 'issued' then ' issued' else ' partly issued' end,
      'Collect it from the store.', 'mr:' || r.id);
  end if;
  return r;
end;
$$;

-- The requester (or a supervisor) withdraws a request that is not issued.
create function public.fn_cancel_mr(p_mr uuid)
returns public.material_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.material_requests;
begin
  select * into r from public.material_requests where id = p_mr for update;
  if not found or not public._can('store.view', r.site_id) then
    raise exception 'NOT_FOUND: Material request not found';
  end if;
  if not (r.requested_by = auth.uid() or public._can('mr.approve', r.site_id)) then
    raise exception 'NOT_ALLOWED: Only the requester or a supervisor can cancel it';
  end if;
  if r.status not in ('pending', 'approved') then
    raise exception 'CONFLICT: % is already %', r.code, replace(r.status, '_', ' ');
  end if;
  update public.material_requests set status = 'cancelled' where id = r.id returning * into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- Supplier and purchase functions
-- ---------------------------------------------------------------------------

create function public.fn_save_supplier(
  p_client_ref uuid,
  p_site uuid,
  p_name text,
  p_contact text,
  p_phone text,
  p_email text,
  p_archived boolean
)
returns public.suppliers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.suppliers;
begin
  if not public._can('po.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only the store can manage suppliers';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 120 then
    raise exception 'INVALID: The supplier needs a name';
  end if;
  if not coalesce(p_archived, false) and exists (
    select 1 from public.suppliers where lower(name) = lower(trim(p_name)) and not is_archived and id <> p_client_ref
  ) then
    raise exception 'CONFLICT: % is already a supplier', trim(p_name);
  end if;
  insert into public.suppliers (id, name, contact, phone, email, is_archived)
  values (p_client_ref, trim(p_name), nullif(trim(coalesce(p_contact, '')), ''),
    nullif(trim(coalesce(p_phone, '')), ''), nullif(trim(coalesce(p_email, '')), ''), coalesce(p_archived, false))
  on conflict (id) do update
  set name = excluded.name, contact = excluded.contact, phone = excluded.phone, email = excluded.email,
      is_archived = excluded.is_archived
  returning * into v;
  return v;
end;
$$;

-- Starts a purchase (po.manage), status requested. p_lines is [{item_id or
-- description and unit, qty, unit_price, mr_line_id}]; a line can come from
-- an approved material request at the site.
create function public.fn_create_po(
  p_client_ref uuid,
  p_site uuid,
  p_supplier uuid,
  p_po_number text,
  p_expected date,
  p_note text,
  p_lines jsonb
)
returns public.purchase_orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.purchase_orders;
  l record;
  v_mr_line uuid;
begin
  select * into o from public.purchase_orders where id = p_client_ref;
  if found then
    return o;
  end if;
  if not public._can('po.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only the store can make purchases';
  end if;
  if p_supplier is not null and not exists (select 1 from public.suppliers where id = p_supplier and not is_archived) then
    raise exception 'NOT_FOUND: Supplier not found';
  end if;
  insert into public.purchase_orders (id, site_id, code, supplier_id, po_number, expected_date, note)
  values (p_client_ref, p_site, public.next_code(p_site, 'PO'), p_supplier,
    nullif(trim(coalesce(p_po_number, '')), ''), p_expected, nullif(trim(coalesce(p_note, '')), ''))
  returning * into o;
  for l in select * from public._clean_lines(p_site, p_lines) loop
    v_mr_line := nullif(l.extra ->> 'mr_line_id', '')::uuid;
    if v_mr_line is not null and not exists (
      select 1 from public.mr_lines ml join public.material_requests r on r.id = ml.mr_id
      where ml.id = v_mr_line and r.site_id = p_site and r.status in ('approved', 'part_issued')
    ) then
      raise exception 'INVALID: A line is not from an approved material request at this site';
    end if;
    insert into public.po_lines (po_id, item_id, description, unit, qty, unit_price, mr_line_id)
    values (o.id, l.item_id, l.description, l.unit, l.qty, (l.extra ->> 'unit_price')::numeric, v_mr_line);
  end loop;
  return o;
end;
$$;

-- Marks a purchase ordered (with the PO number and expected date) or
-- cancelled (po.manage).
create function public.fn_set_po_status(p_po uuid, p_status text, p_po_number text, p_expected date)
returns public.purchase_orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.purchase_orders;
begin
  select * into o from public.purchase_orders where id = p_po for update;
  if not found or not (public._can('po.manage', o.site_id) or public._can('mr.approve', o.site_id)
    or public._can('store.receive', o.site_id)) then
    raise exception 'NOT_FOUND: Purchase not found';
  end if;
  if not public._can('po.manage', o.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can update purchases';
  end if;
  if p_status not in ('ordered', 'cancelled') then
    raise exception 'INVALID: A purchase can be marked ordered or cancelled';
  end if;
  if o.status in ('delivered', 'cancelled') then
    raise exception 'CONFLICT: % is already %', o.code, o.status;
  end if;
  update public.purchase_orders
  set status = p_status,
      po_number = coalesce(nullif(trim(coalesce(p_po_number, '')), ''), po_number),
      expected_date = coalesce(p_expected, expected_date),
      ordered_at = case when p_status = 'ordered' then coalesce(ordered_at, now()) else ordered_at end
  where id = o.id
  returning * into o;
  return o;
end;
$$;

-- Receives a delivery (store.receive): p_lines is [{line_id, qty}]. Store
-- items go into stock; when everything has come the purchase is delivered.
-- Whoever asked for the materials (through a request) is told.
create function public.fn_receive_po(p_client_ref uuid, p_po uuid, p_lines jsonb, p_note text)
returns public.purchase_orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.purchase_orders;
  x jsonb;
  l public.po_lines;
  m public.stock_moves;
  v_qty numeric;
  v_n integer := 0;
  u uuid;
begin
  select * into o from public.purchase_orders where id = p_po for update;
  if not found or not (public._can('po.manage', o.site_id) or public._can('mr.approve', o.site_id)
    or public._can('store.receive', o.site_id)) then
    raise exception 'NOT_FOUND: Purchase not found';
  end if;
  if exists (select 1 from public.stock_moves sm join public.po_lines pl on pl.po_id = o.id
    where sm.id = md5(p_client_ref::text || pl.id::text)::uuid)
    or exists (select 1 from public.po_deliveries where id = p_client_ref) then
    return o;
  end if;
  if not public._can('store.receive', o.site_id) then
    raise exception 'NOT_ALLOWED: Only the store can receive deliveries';
  end if;
  if o.status not in ('requested', 'ordered') then
    raise exception 'CONFLICT: % is %', o.code, o.status;
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    select * into l from public.po_lines where id = (x ->> 'line_id')::uuid and po_id = o.id for update;
    if not found then
      raise exception 'INVALID: That line is not on %', o.code;
    end if;
    v_qty := (x ->> 'qty')::numeric;
    if v_qty is null or v_qty <= 0 then
      continue;
    end if;
    if l.received_qty + v_qty > l.qty then
      raise exception 'INVALID: Only % % of % still to come on %',
        trim(to_char(l.qty - l.received_qty, 'FM999999990.##')), l.unit, l.description, o.code;
    end if;
    if l.item_id is not null then
      m := public._stock_move(md5(p_client_ref::text || l.id::text)::uuid, l.item_id, 'receive', v_qty,
        null, null, null, o.code || coalesce(' · ' || nullif(trim(coalesce(p_note, '')), ''), ''));
      update public.stock_moves set po_id = o.id where id = m.id;
    elsif l.mr_line_id is not null then
      -- Not a store item: it goes straight to whoever asked for it.
      update public.mr_lines set issued_qty = least(qty, issued_qty + v_qty) where id = l.mr_line_id;
      update public.material_requests r
      set status = case when not exists (
          select 1 from public.mr_lines where mr_id = r.id and issued_qty < qty
        ) then 'issued' else 'part_issued' end
      where r.id = (select mr_id from public.mr_lines where id = l.mr_line_id)
        and r.status in ('approved', 'part_issued');
    end if;
    update public.po_lines set received_qty = received_qty + v_qty where id = l.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'INVALID: Receive at least one line';
  end if;
  insert into public.po_deliveries (id, po_id, note) values (p_client_ref, o.id, nullif(trim(coalesce(p_note, '')), ''));
  update public.purchase_orders
  set status = case when not exists (select 1 from public.po_lines where po_id = o.id and received_qty < qty)
        then 'delivered' else 'ordered' end,
      ordered_at = coalesce(ordered_at, now()),
      delivered_at = case when not exists (select 1 from public.po_lines where po_id = o.id and received_qty < qty)
        then now() end
  where id = o.id
  returning * into o;

  for u in
    select distinct r.requested_by from public.po_lines pl
    join public.mr_lines ml on ml.id = pl.mr_line_id
    join public.material_requests r on r.id = ml.mr_id
    where pl.po_id = o.id and r.requested_by is not null and r.requested_by is distinct from auth.uid()
  loop
    perform public.fn_notify(u, o.site_id, 'general', 'Delivery arrived for your materials',
      o.code || case when o.status = 'delivered' then ' delivered in full' else ' partly delivered' end,
      'po:' || o.id);
  end loop;
  return o;
end;
$$;

-- ---------------------------------------------------------------------------
-- BOQ functions
-- ---------------------------------------------------------------------------

-- Loads a project's BOQ (projects.manage): p_lines is [{item_id or
-- description, unit, qty}] as read from the spreadsheet. A description that
-- names a store item at the site (same name and unit) is linked to it.
-- p_replace archives the lines already there first.
create function public.fn_import_boq(p_project uuid, p_lines jsonb, p_replace boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.projects;
  l record;
  v_item uuid;
  v_n integer := 0;
begin
  select * into p from public.projects where id = p_project and not is_archived;
  if not found or not public._can('jc.view', p.site_id) then
    raise exception 'NOT_FOUND: Project not found';
  end if;
  if not public._can('projects.manage', p.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can load a BOQ';
  end if;
  if coalesce(p_replace, false) then
    update public.boq_lines set is_archived = true where project_id = p.id and not is_archived;
  end if;
  for l in select * from public._clean_lines(p.site_id, p_lines) loop
    v_item := l.item_id;
    if v_item is null then
      select s.id into v_item from public.store_items s
      where s.site_id = p.site_id and not s.is_archived
        and lower(s.name) = lower(l.description) and lower(s.unit) = lower(l.unit)
      limit 1;
    end if;
    insert into public.boq_lines (project_id, item_id, description, unit, qty)
    values (p.id, v_item, l.description, l.unit, l.qty);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Each BOQ line against what was issued to the project, what is asked for
-- in open requests, on order and in stock; to_request is what nobody has
-- asked for yet.
create view public.boq_status with (security_invoker = true) as
with lines as (
  select b.*, p.site_id from public.boq_lines b join public.projects p on p.id = b.project_id
  where not b.is_archived
)
select l.id, l.project_id, l.site_id, l.item_id, l.description, l.unit, l.qty,
  coalesce(iss.qty, 0)::numeric(12, 2) as issued,
  coalesce(req.qty, 0)::numeric(12, 2) as requested,
  coalesce(ord.qty, 0)::numeric(12, 2) as on_order,
  coalesce(si.on_hand, 0)::numeric(12, 2) as in_stock,
  greatest(l.qty - coalesce(iss.qty, 0), 0)::numeric(12, 2) as still_needed,
  greatest(l.qty - coalesce(iss.qty, 0) - coalesce(req.qty, 0) - coalesce(ord.qty, 0), 0)::numeric(12, 2) as to_request
from lines l
left join public.store_items si on si.id = l.item_id
left join lateral (
  select -sum(m.qty) as qty from public.stock_moves m
  where m.project_id = l.project_id and m.item_id = l.item_id and m.kind = 'issue'
) iss on l.item_id is not null
left join lateral (
  select sum(ml.qty - ml.issued_qty) as qty from public.mr_lines ml
  join public.material_requests r on r.id = ml.mr_id
  where r.project_id = l.project_id and r.status in ('pending', 'approved', 'part_issued')
    and (ml.item_id = l.item_id or (l.item_id is null and lower(ml.description) = lower(l.description)))
) req on true
left join lateral (
  select sum(pl.qty - pl.received_qty) as qty from public.po_lines pl
  join public.purchase_orders o on o.id = pl.po_id
  left join public.mr_lines ml on ml.id = pl.mr_line_id
  left join public.material_requests r on r.id = ml.mr_id
  where o.status in ('requested', 'ordered') and r.project_id = l.project_id
    and (pl.item_id = l.item_id or (l.item_id is null and lower(pl.description) = lower(l.description)))
) ord on true;

-- Turns everything still to request on a project's BOQ into one material
-- request (mr.create). Returns null when nothing is short.
create function public.fn_boq_shortfall_to_mr(p_client_ref uuid, p_project uuid, p_needed_by date)
returns public.material_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.projects;
  r public.material_requests;
  v_lines jsonb;
begin
  select * into r from public.material_requests where id = p_client_ref;
  if found then
    return r;
  end if;
  select * into p from public.projects where id = p_project and not is_archived;
  if not found or not public._can('jc.view', p.site_id) then
    raise exception 'NOT_FOUND: Project not found';
  end if;
  select jsonb_agg(jsonb_build_object('item_id', b.item_id, 'description', b.description, 'unit', b.unit,
    'qty', b.to_request) order by b.description)
  into v_lines
  from public.boq_status b
  where b.project_id = p.id and b.to_request > 0;
  if v_lines is null then
    return null;
  end if;
  return public.fn_create_mr(p_client_ref, p.site_id, null, p.id, p_needed_by,
    'Shortfall on the BOQ of ' || p.code, v_lines);
end;
$$;

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
alter table public.suppliers enable row level security;
alter table public.material_requests enable row level security;
alter table public.mr_lines enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.po_lines enable row level security;
alter table public.boq_lines enable row level security;
alter table public.po_deliveries enable row level security;

create policy suppliers_select on public.suppliers for select to authenticated using (public._active());
create policy material_requests_select on public.material_requests for select to authenticated
  using (public._can('store.view', site_id));
create policy mr_lines_select on public.mr_lines for select to authenticated
  using (exists (select 1 from public.material_requests r
    where r.id = mr_lines.mr_id and public._can('store.view', r.site_id)));
-- Prices are for the store and supervisors.
create policy purchase_orders_select on public.purchase_orders for select to authenticated
  using (public._can('po.manage', site_id) or public._can('mr.approve', site_id) or public._can('store.receive', site_id));
create policy po_lines_select on public.po_lines for select to authenticated
  using (exists (select 1 from public.purchase_orders o where o.id = po_lines.po_id and (
    public._can('po.manage', o.site_id) or public._can('mr.approve', o.site_id) or public._can('store.receive', o.site_id))));
create policy po_deliveries_select on public.po_deliveries for select to authenticated
  using (exists (select 1 from public.purchase_orders o where o.id = po_deliveries.po_id and (
    public._can('po.manage', o.site_id) or public._can('mr.approve', o.site_id) or public._can('store.receive', o.site_id))));
create policy boq_lines_select on public.boq_lines for select to authenticated
  using (exists (select 1 from public.projects p where p.id = boq_lines.project_id and public._can('jc.view', p.site_id)));

revoke all on public.suppliers, public.material_requests, public.mr_lines, public.purchase_orders,
  public.po_lines, public.boq_lines, public.boq_status, public.po_deliveries from anon;
revoke insert, update, delete on public.suppliers, public.material_requests, public.mr_lines,
  public.purchase_orders, public.po_lines, public.boq_lines, public.po_deliveries from authenticated;
grant select on public.boq_status to authenticated;

revoke execute on function public._clean_lines(uuid, jsonb) from public, anon, authenticated;
revoke execute on function
  public.fn_create_mr(uuid, uuid, uuid, uuid, date, text, jsonb),
  public.fn_decide_mr(uuid, boolean, text),
  public.fn_issue_mr(uuid, uuid, jsonb),
  public.fn_cancel_mr(uuid),
  public.fn_save_supplier(uuid, uuid, text, text, text, text, boolean),
  public.fn_create_po(uuid, uuid, uuid, text, date, text, jsonb),
  public.fn_set_po_status(uuid, text, text, date),
  public.fn_receive_po(uuid, uuid, jsonb, text),
  public.fn_import_boq(uuid, jsonb, boolean),
  public.fn_boq_shortfall_to_mr(uuid, uuid, date)
from public, anon;
grant execute on function
  public.fn_create_mr(uuid, uuid, uuid, uuid, date, text, jsonb),
  public.fn_decide_mr(uuid, boolean, text),
  public.fn_issue_mr(uuid, uuid, jsonb),
  public.fn_cancel_mr(uuid),
  public.fn_save_supplier(uuid, uuid, text, text, text, text, boolean),
  public.fn_create_po(uuid, uuid, uuid, text, date, text, jsonb),
  public.fn_set_po_status(uuid, text, text, date),
  public.fn_receive_po(uuid, uuid, jsonb, text),
  public.fn_import_boq(uuid, jsonb, boolean),
  public.fn_boq_shortfall_to_mr(uuid, uuid, date)
to authenticated;

insert into public.schema_migrations (filename) values ('0035_procurement.sql')
on conflict do nothing;
