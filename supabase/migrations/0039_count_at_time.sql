-- 0039_count_at_time: a stock count corrects stock as it was when each item
-- was counted, not when the count reached the server.
--
-- A count typed offline in the morning and sent in the evening used to set
-- stock on hand to the counted amount, wiping out anything issued or
-- received in between. Now each line may carry counted_at (when it was
-- typed, from the phone). The server works out what stock on hand was then
-- (stock on hand now less the moves since), and applies only the
-- difference, so later moves stay. counted_at is kept within the last 14
-- days and never later than now; without it, now is used (as before).
--
-- If more was issued since the count than was counted (the count was
-- wrong), stock goes to 0 rather than below, and the move's note says so.

alter table public.stock_count_lines add column counted_at timestamptz;

create or replace function public.fn_submit_count(p_client_ref uuid, p_site uuid, p_lines jsonb, p_note text)
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
  v_at timestamptz;
  v_then numeric;
  v_delta numeric;
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
    select (x ->> 'item_id')::uuid as item_id, (x ->> 'counted')::numeric as counted,
      x ->> 'counted_at' as counted_at
    from jsonb_array_elements(p_lines) x
  loop
    select * into i from public.store_items where id = l.item_id and not is_archived for update;
    if not found or i.site_id <> p_site then
      raise exception 'INVALID: An item is not in this site''s store';
    end if;
    if l.counted is null or l.counted < 0 then
      raise exception 'INVALID: Counts are 0 or more';
    end if;
    begin
      v_at := l.counted_at::timestamptz;
    exception when others then
      v_at := null;
    end;
    v_at := least(greatest(coalesce(v_at, now()), now() - interval '14 days'), now());

    -- Stock on hand when the item was counted.
    select i.on_hand - coalesce(sum(sm.qty), 0) into v_then
    from public.stock_moves sm
    where sm.item_id = i.id and sm.created_at > v_at;

    insert into public.stock_count_lines (count_id, item_id, expected, counted, counted_at)
    values (c.id, i.id, v_then, l.counted, v_at);
    v_items := v_items + 1;
    if l.counted <> v_then then
      v_delta := greatest(l.counted - v_then, -i.on_hand);
      if v_delta <> 0 then
        m := public._stock_move(gen_random_uuid(), i.id, 'count', v_delta, null, null, null,
          'Count: ' || trim(to_char(v_then, 'FM999999990.##')) || ' expected, '
            || trim(to_char(l.counted, 'FM999999990.##')) || ' counted'
            || case when v_then <> i.on_hand
                 then ' (stock moved since; ' || trim(to_char(i.on_hand, 'FM999999990.##')) || ' before this correction)'
                 else '' end
            || case when v_delta <> l.counted - v_then
                 then '; more was issued since than counted, so stock goes to 0'
                 else '' end);
        update public.stock_moves set count_id = c.id where id = m.id;
      end if;
      v_diff := v_diff + 1;
    end if;
  end loop;

  update public.stock_counts set items = v_items, differences = v_diff where id = c.id
  returning * into c;
  return c;
end;
$$;

insert into public.schema_migrations (filename) values ('0039_count_at_time.sql')
on conflict do nothing;
