-- 0042_search_everything: fn_search_records (used by # in chat and, now,
-- the search box on every tab; issue #36) also finds documents, inventory
-- items, projects, material requests and purchases, each only for people
-- who may see it. An exact code match comes first.

create or replace function public.fn_search_records(p_query text)
returns table (link text, code text, title text, status text, site_code text)
language sql
stable
security definer
set search_path = ''
as $$
  with q as (select trim(coalesce(p_query, '')) as q)
  select link, code, title, status, site_code from (
    select 'jobcard:' || j.id as link, j.number as code, j.title, replace(j.status, '_', ' ') as status,
      s.code as site_code, j.updated_at as at, 1 as rank
    from public.job_cards j join public.sites s on s.id = j.site_id, q
    where not j.is_archived and public._can('jc.view', j.site_id)
      and (q.q = '' or j.number ilike '%' || q.q || '%' or j.title ilike '%' || q.q || '%')
    union all
    select 'asset:' || a.id, a.tag, a.name, 'equipment', s.code, a.updated_at, 2
    from public.assets a join public.sites s on s.id = a.site_id, q
    where not a.is_archived and public._can('assets.view', a.site_id)
      and (q.q = '' or a.tag ilike '%' || q.q || '%' or a.name ilike '%' || q.q || '%')
    union all
    select 'tool:' || t.id, t.code, t.name, 'tool', s.code, t.updated_at, 3
    from public.tools t join public.sites s on s.id = t.site_id, q
    where not t.is_archived and public._can('tools.view', t.site_id)
      and (q.q = '' or t.code ilike '%' || q.q || '%' or t.name ilike '%' || q.q || '%')
    union all
    select 'doc:' || d.id, d.code, d.title, 'document', s.code, d.updated_at, 4
    from public.documents d join public.sites s on s.id = d.site_id, q
    where not d.is_archived and public._can('docs.view', d.site_id)
      and (q.q = '' or d.code ilike '%' || q.q || '%' or d.title ilike '%' || q.q || '%')
    union all
    select 'item:' || i.id, i.code, i.name, 'inventory', s.code, i.updated_at, 5
    from public.store_items i join public.sites s on s.id = i.site_id, q
    where not i.is_archived and public._can('store.view', i.site_id)
      and (q.q = '' or i.code ilike '%' || q.q || '%' or i.name ilike '%' || q.q || '%')
    union all
    select 'project:' || p.id, p.code, p.name, 'project', s.code, p.updated_at, 6
    from public.projects p join public.sites s on s.id = p.site_id, q
    where not p.is_archived and public._can('jc.view', p.site_id)
      and (q.q = '' or p.code ilike '%' || q.q || '%' or p.name ilike '%' || q.q || '%')
    union all
    select 'mr:' || r.id, r.code, coalesce(nullif(r.note, ''), 'Material request'), replace(r.status, '_', ' '),
      s.code, r.created_at, 7
    from public.material_requests r join public.sites s on s.id = r.site_id, q
    where public._can('store.view', r.site_id)
      and q.q <> '' and (r.code ilike '%' || q.q || '%' or r.note ilike '%' || q.q || '%')
    union all
    select 'po:' || o.id, o.code, coalesce('PO ' || nullif(o.po_number, ''), 'Purchase'), replace(o.status, '_', ' '),
      s.code, o.created_at, 8
    from public.purchase_orders o join public.sites s on s.id = o.site_id, q
    where (public._can('po.manage', o.site_id) or public._can('mr.approve', o.site_id)
        or public._can('store.receive', o.site_id))
      and q.q <> '' and (o.code ilike '%' || q.q || '%' or o.po_number ilike '%' || q.q || '%')
  ) r, q
  order by (lower(r.code) = lower(q.q)) desc, rank, at desc
  limit 30;
$$;

insert into public.schema_migrations (filename) values ('0042_search_everything.sql')
on conflict do nothing;
