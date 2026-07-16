-- Inventory Transfer Phase Two — deterministic execution locking.
--
-- This corrective migration intentionally changes only issue and resolution
-- execution.  The existing projection writer keeps its advisory/row locking as
-- defence in depth; transfer commands acquire the complete transfer grain set
-- before they validate quantities or invoke the posting path.

create table public.inventory_physical_grain_locks (
  grain_key text primary key,
  created_at timestamptz not null default now(),
  check (length(grain_key)>0)
);

revoke all on table public.inventory_physical_grain_locks
  from public,anon,authenticated;

-- The JSON array is versioned and preserves a JSON null batch value.  It is
-- deliberately not a hash: the registry primary key is collision-free and
-- does not rely on truncating a composite physical dimension.
create or replace function public.inventory_physical_grain_key(
  p_tenant_id uuid,
  p_organization_id uuid,
  p_facility_id uuid,
  p_location_id uuid,
  p_inventory_item_profile_id uuid,
  p_batch_id uuid,
  p_recording_channel public.inventory_recording_channel,
  p_disposition public.inventory_stock_disposition
) returns text
language plpgsql
immutable
security definer
set search_path=public
as $$
begin
  if p_tenant_id is null
     or p_organization_id is null
     or p_facility_id is null
     or p_location_id is null
     or p_inventory_item_profile_id is null
     or p_recording_channel is null
     or p_disposition is null then
    raise exception 'Inventory physical grain lock request is invalid'
      using errcode='22023';
  end if;

  return jsonb_build_array(
    'inventory_physical_grain_v1',
    p_tenant_id,
    p_organization_id,
    p_facility_id,
    p_location_id,
    p_inventory_item_profile_id,
    p_batch_id,
    p_recording_channel::text,
    p_disposition::text,
    'physical'
  )::text;
end;
$$;

create or replace function public.inventory_lock_physical_grain_keys(
  p_grain_keys text[]
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  lock_row record;
begin
  if coalesce(cardinality(p_grain_keys),0)=0 then
    return;
  end if;

  if exists (
    select 1
    from unnest(p_grain_keys) as requested(grain_key)
    where requested.grain_key is null or requested.grain_key=''
  ) then
    raise exception 'Inventory physical grain lock request is invalid'
      using errcode='22023';
  end if;

  -- Insert one sorted key at a time.  Unlike a set-based INSERT source, this
  -- makes the uniqueness/speculative-insert acquisition sequence explicit for
  -- overlapping first-insert requests.
  for lock_row in
    select distinct requested.grain_key
    from unnest(p_grain_keys) as requested(grain_key)
    order by requested.grain_key
  loop
    insert into public.inventory_physical_grain_locks(grain_key)
    values(lock_row.grain_key)
    on conflict (grain_key) do nothing;
  end loop;

  for lock_row in
    select l.grain_key
    from public.inventory_physical_grain_locks l
    where l.grain_key=any(p_grain_keys)
    order by l.grain_key
    for update
  loop
    null;
  end loop;
end;
$$;

create or replace function public.inventory_lock_physical_grains(
  p_grains jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  grain_keys text[];
begin
  if coalesce(jsonb_typeof(p_grains),'')<>'array' then
    raise exception 'Inventory physical grain lock request is invalid'
      using errcode='22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_grains) g
    where jsonb_typeof(g.value)<>'object'
       or nullif(g.value->>'tenant_id','') is null
       or nullif(g.value->>'organization_id','') is null
       or nullif(g.value->>'facility_id','') is null
       or nullif(g.value->>'location_id','') is null
       or nullif(g.value->>'inventory_item_profile_id','') is null
       or nullif(g.value->>'recording_channel','') is null
       or nullif(g.value->>'disposition','') is null
  ) then
    raise exception 'Inventory physical grain lock request is invalid'
      using errcode='22023';
  end if;

  select array_agg(distinct public.inventory_physical_grain_key(
           (g.value->>'tenant_id')::uuid,
           (g.value->>'organization_id')::uuid,
           (g.value->>'facility_id')::uuid,
           (g.value->>'location_id')::uuid,
           (g.value->>'inventory_item_profile_id')::uuid,
           nullif(g.value->>'batch_id','')::uuid,
           (g.value->>'recording_channel')::public.inventory_recording_channel,
           (g.value->>'disposition')::public.inventory_stock_disposition
         ) order by public.inventory_physical_grain_key(
           (g.value->>'tenant_id')::uuid,
           (g.value->>'organization_id')::uuid,
           (g.value->>'facility_id')::uuid,
           (g.value->>'location_id')::uuid,
           (g.value->>'inventory_item_profile_id')::uuid,
           nullif(g.value->>'batch_id','')::uuid,
           (g.value->>'recording_channel')::public.inventory_recording_channel,
           (g.value->>'disposition')::public.inventory_stock_disposition
         ))
    into grain_keys
    from jsonb_array_elements(p_grains) g;

  perform public.inventory_lock_physical_grain_keys(grain_keys);
end;
$$;

-- The caller must already hold the transfer row.  This helper locks the
-- mutable execution graph in one invariant table order and native UUID order.
create or replace function public.inventory_lock_transfer_execution_graph(
  p_transfer_id uuid,
  p_allocation_ids uuid[]
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  line_ids uuid[];
  graph_allocation_ids uuid[];
  ignored record;
begin
  select array_agg(distinct a.transfer_line_id order by a.transfer_line_id)
    into line_ids
    from public.inventory_transfer_allocations a
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where l.transfer_id=p_transfer_id
      and a.id=any(coalesce(p_allocation_ids,array[]::uuid[]));

  if coalesce(cardinality(line_ids),0)=0 then
    return;
  end if;

  -- A line bound includes sibling allocations and line-unallocated closures.
  -- Locking the complete affected line graph keeps those derivations stable.
  select array_agg(a.id order by a.id)
    into graph_allocation_ids
    from public.inventory_transfer_allocations a
    where a.transfer_line_id=any(line_ids);

  for ignored in
    select l.id
    from public.inventory_transfer_lines l
    where l.id=any(line_ids)
    order by l.id
    for update
  loop null; end loop;

  for ignored in
    select a.id
    from public.inventory_transfer_allocations a
    where a.id=any(graph_allocation_ids)
    order by a.id
    for update
  loop null; end loop;

  for ignored in
    select r.id
    from public.inventory_reservations r
    where r.transfer_allocation_id=any(graph_allocation_ids)
    order by r.id
    for update
  loop null; end loop;

  for ignored in
    select o.id
    from public.inventory_transfer_operations o
    where o.transfer_id=p_transfer_id
      and o.transfer_allocation_id=any(graph_allocation_ids)
    order by o.id
    for update
  loop null; end loop;

  for ignored in
    select rd.id
    from public.inventory_transfer_receipt_destinations rd
    join public.inventory_transfer_operations o on o.id=rd.operation_id
    where o.transfer_id=p_transfer_id
      and o.transfer_allocation_id=any(graph_allocation_ids)
    order by rd.id
    for update of rd
  loop null; end loop;

  for ignored in
    select c.id
    from public.inventory_transfer_remainder_closures c
    where c.transfer_id=p_transfer_id
      and c.transfer_line_id=any(line_ids)
    order by c.id
    for update
  loop null; end loop;

  for ignored in
    select ra.id
    from public.inventory_reservation_adjustments ra
    where ra.transfer_id=p_transfer_id
      and ra.transfer_allocation_id=any(graph_allocation_ids)
    order by ra.id
    for update
  loop null; end loop;
end;
$$;

create or replace function public.issue_inventory_transfer(
  p_transfer uuid,
  p_issues jsonb,
  p_key text,
  p_hash text,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  transfer_row public.inventory_transfers%rowtype;
  command_id uuid;
  transaction_id uuid;
  item jsonb;
  allocation_row record;
  reservation_row public.inventory_reservations%rowtype;
  quantity numeric;
  reservation_requested_now numeric;
  allocation_requested_now numeric;
  line_existing_issued numeric;
  line_closed numeric;
  line_requested_now numeric;
  source_requested_now numeric;
  available_quantity numeric;
  allocation_ids uuid[];
  physical_grains jsonb;
  entries jsonb:='[]'::jsonb;
  operation_id uuid;
  base_unit_id uuid;
begin
  if jsonb_typeof(p_issues)<>'array'
     or jsonb_array_length(p_issues)=0
     or coalesce(trim(p_reason),'')=''
     or exists (
       select 1
       from jsonb_array_elements(p_issues) x
       where jsonb_typeof(x.value)<>'object'
         or nullif(x.value->>'transfer_allocation_id','') is null
         or nullif(x.value->>'quantity_base','') is null
     ) then
    raise exception 'Inventory transfer issue denied';
  end if;

  select array_agg(distinct (x.value->>'transfer_allocation_id')::uuid
                   order by (x.value->>'transfer_allocation_id')::uuid)
    into allocation_ids
    from jsonb_array_elements(p_issues) x;

  select * into transfer_row
  from public.inventory_transfers
  where id=p_transfer
  for update;

  if not found
     or transfer_row.status not in ('reserved','partially_issued','issued')
     or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.issue') then
    raise exception 'Inventory transfer issue denied';
  end if;

  command_id:=public.claim_inventory_transfer_command(
    p_transfer,'transfer_issue',p_key,p_hash,
    jsonb_build_object('issues',p_issues),p_reason
  );
  if (select payload ? 'result_transfer_id'
      from public.inventory_commands where id=command_id) then
    return p_transfer;
  end if;

  perform public.inventory_lock_transfer_execution_graph(
    p_transfer,allocation_ids
  );

  select coalesce(jsonb_agg(grain),'[]'::jsonb)
    into physical_grains
    from (
      select jsonb_build_object(
        'tenant_id',transfer_row.tenant_id,
        'organization_id',transfer_row.organization_id,
        'facility_id',transfer_row.facility_id,
        'location_id',a.source_location_id,
        'inventory_item_profile_id',l.inventory_item_profile_id,
        'batch_id',a.batch_id,
        'recording_channel',a.recording_channel,
        'disposition','available'
      ) as grain
      from public.inventory_transfer_allocations a
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where a.id=any(allocation_ids) and l.transfer_id=p_transfer
      union
      select jsonb_build_object(
        'tenant_id',transfer_row.tenant_id,
        'organization_id',transfer_row.organization_id,
        'facility_id',transfer_row.facility_id,
        'location_id',transfer_row.transit_location_id,
        'inventory_item_profile_id',l.inventory_item_profile_id,
        'batch_id',a.batch_id,
        'recording_channel',a.recording_channel,
        'disposition','transit'
      )
      from public.inventory_transfer_allocations a
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where a.id=any(allocation_ids) and l.transfer_id=p_transfer
    ) requested;
  perform public.inventory_lock_physical_grains(physical_grains);

  -- Revalidate all mutable business facts after the complete graph and grain
  -- lock set is held.  A failed revalidation rolls back the claimed command.
  select * into transfer_row
  from public.inventory_transfers
  where id=p_transfer
  for update;
  if not found
     or transfer_row.status not in ('reserved','partially_issued','issued')
     or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.issue') then
    raise exception 'Inventory transfer issue denied';
  end if;

  for item in select value from jsonb_array_elements(p_issues) loop
    select a.*,l.inventory_item_profile_id,l.requested_quantity_base
      into allocation_row
      from public.inventory_transfer_allocations a
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where a.id=(item->>'transfer_allocation_id')::uuid
        and l.transfer_id=p_transfer;
    quantity:=(item->>'quantity_base')::numeric;
    select * into reservation_row
      from public.inventory_reservations r
      where r.transfer_allocation_id=allocation_row.id;
    if not found or quantity<=0 or reservation_row.expires_at<=now() then
      raise exception 'Inventory transfer issue reservation denied';
    end if;

    select coalesce(sum((request_item.value->>'quantity_base')::numeric),0)
      into reservation_requested_now
      from jsonb_array_elements(p_issues) request_item
      join public.inventory_reservations request_reservation
        on request_reservation.transfer_allocation_id=
           (request_item.value->>'transfer_allocation_id')::uuid
      where request_reservation.id=reservation_row.id;
    if reservation_requested_now>
       public.inventory_transfer_reservation_remaining(reservation_row.id) then
      raise exception 'Inventory transfer issue exceeds reservation remaining quantity'
        using errcode='23514';
    end if;

    select coalesce(sum((request_item.value->>'quantity_base')::numeric),0)
      into allocation_requested_now
      from jsonb_array_elements(p_issues) request_item
      where (request_item.value->>'transfer_allocation_id')::uuid=
            allocation_row.id;
    if allocation_requested_now+
       coalesce((select sum(o.quantity_base)
                 from public.inventory_transfer_operations o
                 where o.transfer_allocation_id=allocation_row.id
                   and o.operation_type='issue'),0)+
       coalesce((select sum(c.quantity_base)
                 from public.inventory_transfer_remainder_closures c
                 where c.transfer_allocation_id=allocation_row.id),0)
       >allocation_row.planned_quantity_base then
      raise exception 'Inventory transfer issue exceeds allocation planned quantity'
        using errcode='23514';
    end if;

    select coalesce(sum(o.quantity_base),0)
      into line_existing_issued
      from public.inventory_transfer_operations o
      join public.inventory_transfer_allocations a on a.id=o.transfer_allocation_id
      where a.transfer_line_id=allocation_row.transfer_line_id
        and o.operation_type='issue';
    select coalesce(sum(c.quantity_base),0)
      into line_closed
      from public.inventory_transfer_remainder_closures c
      where c.transfer_line_id=allocation_row.transfer_line_id;
    select coalesce(sum((request_item.value->>'quantity_base')::numeric),0)
      into line_requested_now
      from jsonb_array_elements(p_issues) request_item
      join public.inventory_transfer_allocations request_allocation
        on request_allocation.id=
           (request_item.value->>'transfer_allocation_id')::uuid
      where request_allocation.transfer_line_id=allocation_row.transfer_line_id;
    if line_existing_issued+line_closed+line_requested_now>
       allocation_row.requested_quantity_base then
      raise exception 'Inventory transfer issue exceeds line requested quantity'
        using errcode='23514';
    end if;

    select iu.id into base_unit_id
      from public.inventory_item_units iu
      where iu.inventory_item_profile_id=allocation_row.inventory_item_profile_id
        and iu.active and iu.is_base_unit;
    if base_unit_id is null then
      raise exception 'Inventory transfer issue denied';
    end if;
    entries:=entries||jsonb_build_array(
      jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,
        'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,
        'channel',allocation_row.recording_channel,'account_type','physical',
        'location_id',allocation_row.source_location_id,
        'disposition','available','quantity_base',-quantity),
      jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,
        'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,
        'channel',allocation_row.recording_channel,'account_type','physical',
        'location_id',transfer_row.transit_location_id,
        'disposition','transit','quantity_base',quantity)
    );
  end loop;

  -- Preserve the established business-error precedence while still checking
  -- the aggregate physical source balance only after every grain is locked.
  for allocation_row in
    select a.source_location_id,l.inventory_item_profile_id,a.batch_id,
           a.recording_channel,sum((x.value->>'quantity_base')::numeric)
             as requested_quantity_base
    from jsonb_array_elements(p_issues) x
    join public.inventory_transfer_allocations a
      on a.id=(x.value->>'transfer_allocation_id')::uuid
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where l.transfer_id=p_transfer
    group by a.source_location_id,l.inventory_item_profile_id,a.batch_id,
             a.recording_channel
  loop
    select coalesce((
      select bp.quantity_base
      from public.inventory_balance_projections bp
      -- balance projections are physical-only by the Phase One schema; their
      -- scope dimensions must still match the locked transfer grain exactly.
      where bp.tenant_id=transfer_row.tenant_id
        and bp.organization_id=transfer_row.organization_id
        and bp.facility_id=transfer_row.facility_id
        and bp.location_id=allocation_row.source_location_id
        and bp.inventory_item_profile_id=allocation_row.inventory_item_profile_id
        and bp.batch_id is not distinct from allocation_row.batch_id
        and bp.recording_channel=allocation_row.recording_channel
        and bp.disposition='available'
      for update
    ),0) into available_quantity;
    if available_quantity<allocation_row.requested_quantity_base then
      raise exception 'Inventory transfer issue would create negative physical balance'
        using errcode='23514';
    end if;
  end loop;

  insert into public.inventory_transactions(
    tenant_id,organization_id,facility_id,command_id,transaction_type,posted_by,reason
  ) values (
    transfer_row.tenant_id,transfer_row.organization_id,transfer_row.facility_id,
    command_id,'transfer_issue',auth.uid(),trim(p_reason)
  ) returning id into transaction_id;
  perform public.inventory_post_entries(
    transaction_id,entries,'inventory.transfer_issued',
    jsonb_build_object('transfer_id',p_transfer)
  );

  for item in select value from jsonb_array_elements(p_issues) loop
    select a.*,l.inventory_item_profile_id,r.id as reservation_id
      into allocation_row
      from public.inventory_transfer_allocations a
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      join public.inventory_reservations r on r.transfer_allocation_id=a.id
      where a.id=(item->>'transfer_allocation_id')::uuid;
    quantity:=(item->>'quantity_base')::numeric;
    insert into public.inventory_transfer_operations(
      transfer_id,transfer_allocation_id,command_id,transaction_id,operation_type,
      inventory_item_profile_id,batch_id,recording_channel,source_location_id,
      destination_location_id,source_disposition,destination_disposition,
      quantity_base,reason,created_by
    ) values (
      p_transfer,allocation_row.id,command_id,transaction_id,'issue',
      allocation_row.inventory_item_profile_id,allocation_row.batch_id,
      allocation_row.recording_channel,allocation_row.source_location_id,
      transfer_row.transit_location_id,'available','transit',quantity,
      trim(p_reason),auth.uid()
    ) returning id into operation_id;
    perform public.append_inventory_reservation_adjustment(
      allocation_row.reservation_id,allocation_row.id,p_transfer,command_id,
      'issue_consumed',quantity,operation_id,null,trim(p_reason)
    );
    perform public.inventory_transfer_write_event(
      p_transfer,command_id,operation_id,'inventory.transfer_issued',
      jsonb_build_object('quantity_base',quantity)
    );
  end loop;

  update public.inventory_commands
    set status='posted',posted_at=now(),result_transaction_id=transaction_id,
        payload=payload||jsonb_build_object('result_transfer_id',p_transfer)
    where id=command_id;
  perform public.inventory_transfer_refresh_status(p_transfer);
  return p_transfer;
end;
$$;

create or replace function public.post_inventory_transfer_resolution(
  p_transfer uuid,
  p_type public.inventory_transfer_operation_type,
  p_moves jsonb,
  p_key text,
  p_hash text,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  transfer_row public.inventory_transfers%rowtype;
  command_id uuid;
  transaction_id uuid;
  item jsonb;
  allocation_row record;
  quantity numeric;
  issued numeric;
  received numeric;
  rejected_qty numeric;
  returned_qty numeric;
  disposed_qty numeric;
  requested_now numeric;
  source_requested_now numeric;
  available_quantity numeric;
  destination uuid;
  from_disposition public.inventory_stock_disposition;
  to_disposition public.inventory_stock_disposition;
  entries jsonb:='[]'::jsonb;
  base_unit_id uuid;
  operation_id uuid;
  permission_key text;
  transaction_type public.inventory_transaction_type;
  allocation_ids uuid[];
  physical_grains jsonb;
begin
  if p_type not in ('receive','reject','return','dispose_rejected')
     or jsonb_typeof(p_moves)<>'array'
     or jsonb_array_length(p_moves)=0
     or coalesce(trim(p_reason),'')=''
     or exists (
       select 1
       from jsonb_array_elements(p_moves) x
       where jsonb_typeof(x.value)<>'object'
         or nullif(x.value->>'transfer_allocation_id','') is null
         or nullif(x.value->>'quantity_base','') is null
     ) then
    raise exception 'Inventory transfer resolution denied';
  end if;

  permission_key:=case p_type
    when 'receive' then 'inventory.transfer.receive'
    when 'reject' then 'inventory.transfer.reject'
    when 'return' then 'inventory.transfer.return'
    else 'inventory.transfer.dispose'
  end;
  transaction_type:=case p_type
    when 'receive' then 'transfer_receive'
    when 'reject' then 'transfer_reject'
    when 'return' then 'transfer_return'
    else 'transfer_dispose_rejected'
  end;

  select array_agg(distinct (x.value->>'transfer_allocation_id')::uuid
                   order by (x.value->>'transfer_allocation_id')::uuid)
    into allocation_ids
    from jsonb_array_elements(p_moves) x;

  select * into transfer_row
  from public.inventory_transfers
  where id=p_transfer
  for update;
  if not found
     or not public.can_manage_inventory_transfer(p_transfer,permission_key) then
    raise exception 'Inventory transfer resolution denied';
  end if;

  command_id:=public.claim_inventory_transfer_command(
    p_transfer,transaction_type,p_key,p_hash,
    jsonb_build_object('moves',p_moves),p_reason
  );
  if (select payload ? 'result_transfer_id'
      from public.inventory_commands where id=command_id) then
    return p_transfer;
  end if;

  perform public.inventory_lock_transfer_execution_graph(
    p_transfer,allocation_ids
  );

  -- Validate allocation ownership and derive every physical source/destination
  -- before any projection mutation.  The second validation pass below runs
  -- only after the sorted registry locks have been acquired.
  for item in select value from jsonb_array_elements(p_moves) loop
    select a.*,l.inventory_item_profile_id
      into allocation_row
      from public.inventory_transfer_allocations a
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where a.id=(item->>'transfer_allocation_id')::uuid
        and l.transfer_id=p_transfer;
    if not found or (item->>'quantity_base')::numeric<=0 then
      raise exception 'Inventory transfer resolution denied';
    end if;
    if p_type='receive'
       and nullif(item->>'destination_location_id','') is null then
      raise exception 'Inventory transfer receipt destination denied';
    end if;
  end loop;

  select coalesce(jsonb_agg(grain),'[]'::jsonb)
    into physical_grains
    from (
      select jsonb_build_object(
        'tenant_id',transfer_row.tenant_id,
        'organization_id',transfer_row.organization_id,
        'facility_id',transfer_row.facility_id,
        'location_id',transfer_row.transit_location_id,
        'inventory_item_profile_id',l.inventory_item_profile_id,
        'batch_id',a.batch_id,
        'recording_channel',a.recording_channel,
        'disposition',case when p_type in ('receive','reject') then 'transit' else 'returns_hold' end
      ) as grain
      from jsonb_array_elements(p_moves) x
      join public.inventory_transfer_allocations a
        on a.id=(x.value->>'transfer_allocation_id')::uuid
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where l.transfer_id=p_transfer
      union
      select jsonb_build_object(
        'tenant_id',transfer_row.tenant_id,
        'organization_id',transfer_row.organization_id,
        'facility_id',transfer_row.facility_id,
        'location_id',case
          when p_type='receive' then (x.value->>'destination_location_id')::uuid
          when p_type='return' then a.source_location_id
          else transfer_row.transit_location_id
        end,
        'inventory_item_profile_id',l.inventory_item_profile_id,
        'batch_id',a.batch_id,
        'recording_channel',a.recording_channel,
        'disposition',case
          when p_type='receive' then coalesce((x.value->>'destination_disposition')::public.inventory_stock_disposition,'available')::text
          when p_type='reject' then 'returns_hold'
          when p_type='return' then 'available'
          else coalesce((x.value->>'destination_disposition')::public.inventory_stock_disposition,'quarantine')::text
        end
      )
      from jsonb_array_elements(p_moves) x
      join public.inventory_transfer_allocations a
        on a.id=(x.value->>'transfer_allocation_id')::uuid
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where l.transfer_id=p_transfer
    ) requested;
  perform public.inventory_lock_physical_grains(physical_grains);

  select * into transfer_row
  from public.inventory_transfers
  where id=p_transfer
  for update;
  if not found
     or not public.can_manage_inventory_transfer(p_transfer,permission_key) then
    raise exception 'Inventory transfer resolution denied';
  end if;

  for allocation_row in
    select a.id,sum((x.value->>'quantity_base')::numeric) as requested_quantity_base
    from jsonb_array_elements(p_moves) x
    join public.inventory_transfer_allocations a
      on a.id=(x.value->>'transfer_allocation_id')::uuid
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where l.transfer_id=p_transfer
    group by a.id
  loop
    select coalesce(sum(o.quantity_base) filter(where o.operation_type='issue'),0),
           coalesce(sum(o.quantity_base) filter(where o.operation_type='receive'),0),
           coalesce(sum(o.quantity_base) filter(where o.operation_type='reject'),0),
           coalesce(sum(o.quantity_base) filter(where o.operation_type='return'),0),
           coalesce(sum(o.quantity_base) filter(where o.operation_type='dispose_rejected'),0)
      into issued,received,rejected_qty,returned_qty,disposed_qty
      from public.inventory_transfer_operations o
      where o.transfer_allocation_id=allocation_row.id;
    if (p_type in ('receive','reject')
          and allocation_row.requested_quantity_base>issued-received-rejected_qty)
       or (p_type in ('return','dispose_rejected')
          and allocation_row.requested_quantity_base>rejected_qty-returned_qty-disposed_qty) then
      raise exception 'Inventory transfer resolution exceeds outstanding quantity'
        using errcode='23514';
    end if;
  end loop;

  for allocation_row in
    select a.id,a.source_location_id,l.inventory_item_profile_id,a.batch_id,
           a.recording_channel,sum((x.value->>'quantity_base')::numeric)
             as requested_quantity_base
    from jsonb_array_elements(p_moves) x
    join public.inventory_transfer_allocations a
      on a.id=(x.value->>'transfer_allocation_id')::uuid
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where l.transfer_id=p_transfer
    group by a.id,a.source_location_id,l.inventory_item_profile_id,a.batch_id,
             a.recording_channel
  loop
    select coalesce(sum((x.value->>'quantity_base')::numeric),0)
      into source_requested_now
      from jsonb_array_elements(p_moves) x
      join public.inventory_transfer_allocations a
        on a.id=(x.value->>'transfer_allocation_id')::uuid
      where a.id=allocation_row.id;

    select coalesce((
      select bp.quantity_base
      from public.inventory_balance_projections bp
      -- inventory_balance_projections contains physical balances only; match
      -- the complete scoped physical grain before revalidating its quantity.
      where bp.tenant_id=transfer_row.tenant_id
        and bp.organization_id=transfer_row.organization_id
        and bp.facility_id=transfer_row.facility_id
        and bp.location_id=transfer_row.transit_location_id
        and bp.inventory_item_profile_id=allocation_row.inventory_item_profile_id
        and bp.batch_id is not distinct from allocation_row.batch_id
        and bp.recording_channel=allocation_row.recording_channel
        and bp.disposition=(case when p_type in ('receive','reject') then 'transit'::public.inventory_stock_disposition else 'returns_hold'::public.inventory_stock_disposition end)
      for update
    ),0) into available_quantity;
    if available_quantity<source_requested_now then
      raise exception 'Inventory transfer resolution would create negative physical balance'
        using errcode='23514';
    end if;
  end loop;

  for item in select value from jsonb_array_elements(p_moves) loop
    select a.*,l.inventory_item_profile_id
      into allocation_row
      from public.inventory_transfer_allocations a
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where a.id=(item->>'transfer_allocation_id')::uuid
        and l.transfer_id=p_transfer;
    quantity:=(item->>'quantity_base')::numeric;
    destination:=case
      when p_type='receive' then (item->>'destination_location_id')::uuid
      when p_type='return' then allocation_row.source_location_id
      else transfer_row.transit_location_id
    end;
    if p_type='receive' and (
      not public.inventory_transfer_location_allowed(
        transfer_row.destination_root_location_id,destination
      )
      or not public.can_manage_inventory_location(
        transfer_row.destination_root_location_id
      )
      or not public.can_manage_inventory_location(destination)
    ) then
      raise exception 'Inventory transfer receipt destination denied';
    end if;
    if p_type='receive'
       and exists (
         select 1 from public.inventory_batches b
         where b.id=allocation_row.batch_id and b.expiry_status<>'known_valid'
       )
       and coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'available')='available' then
      raise exception 'Expired or incomplete batch cannot be received as available'
        using errcode='23514';
    end if;
    from_disposition:=case
      when p_type in ('receive','reject') then 'transit'
      else 'returns_hold'
    end;
    to_disposition:=case
      when p_type='receive' then coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'available')
      when p_type='reject' then 'returns_hold'
      when p_type='return' then 'available'
      else coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'quarantine')
    end;
    if p_type='dispose_rejected'
       and to_disposition not in ('quarantine','damaged','expired','wastage_hold') then
      raise exception 'Inventory transfer disposition denied';
    end if;
    select iu.id into base_unit_id
      from public.inventory_item_units iu
      where iu.inventory_item_profile_id=allocation_row.inventory_item_profile_id
        and iu.active and iu.is_base_unit;
    if base_unit_id is null then
      raise exception 'Inventory transfer resolution denied';
    end if;
    entries:=entries||jsonb_build_array(
      jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,
        'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,
        'channel',allocation_row.recording_channel,'account_type','physical',
        'location_id',transfer_row.transit_location_id,
        'disposition',from_disposition,'quantity_base',-quantity),
      jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,
        'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,
        'channel',allocation_row.recording_channel,'account_type','physical',
        'location_id',destination,'disposition',to_disposition,
        'quantity_base',quantity)
    );
  end loop;

  insert into public.inventory_transactions(
    tenant_id,organization_id,facility_id,command_id,transaction_type,posted_by,reason
  ) values (
    transfer_row.tenant_id,transfer_row.organization_id,transfer_row.facility_id,
    command_id,transaction_type,auth.uid(),trim(p_reason)
  ) returning id into transaction_id;
  perform public.inventory_post_entries(
    transaction_id,entries,'inventory.transfer_'||p_type::text,
    jsonb_build_object('transfer_id',p_transfer)
  );

  for item in select value from jsonb_array_elements(p_moves) loop
    select a.*,l.inventory_item_profile_id
      into allocation_row
      from public.inventory_transfer_allocations a
      join public.inventory_transfer_lines l on l.id=a.transfer_line_id
      where a.id=(item->>'transfer_allocation_id')::uuid;
    quantity:=(item->>'quantity_base')::numeric;
    destination:=case
      when p_type='receive' then (item->>'destination_location_id')::uuid
      when p_type='return' then allocation_row.source_location_id
      else transfer_row.transit_location_id
    end;
    from_disposition:=case when p_type in ('receive','reject') then 'transit' else 'returns_hold' end;
    to_disposition:=case
      when p_type='receive' then coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'available')
      when p_type='reject' then 'returns_hold'
      when p_type='return' then 'available'
      else coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'quarantine')
    end;
    insert into public.inventory_transfer_operations(
      transfer_id,transfer_allocation_id,command_id,transaction_id,operation_type,
      inventory_item_profile_id,batch_id,recording_channel,source_location_id,
      destination_location_id,source_disposition,destination_disposition,
      quantity_base,reason,created_by
    ) values (
      p_transfer,allocation_row.id,command_id,transaction_id,p_type,
      allocation_row.inventory_item_profile_id,allocation_row.batch_id,
      allocation_row.recording_channel,transfer_row.transit_location_id,
      destination,from_disposition,to_disposition,quantity,trim(p_reason),auth.uid()
    ) returning id into operation_id;
    if p_type='receive' then
      insert into public.inventory_transfer_receipt_destinations(
        operation_id,destination_location_id,inventory_item_profile_id,batch_id,
        recording_channel,quantity_base
      ) values (
        operation_id,destination,allocation_row.inventory_item_profile_id,
        allocation_row.batch_id,allocation_row.recording_channel,quantity
      );
    end if;
    perform public.inventory_transfer_write_event(
      p_transfer,command_id,operation_id,'inventory.transfer_'||p_type::text,
      jsonb_build_object('quantity_base',quantity)
    );
  end loop;

  update public.inventory_commands
    set status='posted',posted_at=now(),result_transaction_id=transaction_id,
        payload=payload||jsonb_build_object('result_transfer_id',p_transfer)
    where id=command_id;
  perform public.inventory_transfer_refresh_status(p_transfer);
  return p_transfer;
end;
$$;

revoke all on function public.inventory_physical_grain_key(
  uuid,uuid,uuid,uuid,uuid,uuid,
  public.inventory_recording_channel,public.inventory_stock_disposition
) from public,anon,authenticated,service_role;
revoke all on function public.inventory_lock_physical_grain_keys(text[])
  from public,anon,authenticated,service_role;
revoke all on function public.inventory_lock_physical_grains(jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.inventory_lock_transfer_execution_graph(uuid,uuid[])
  from public,anon,authenticated,service_role;
