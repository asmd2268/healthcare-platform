-- Inventory transfers: deterministic locking, phase two.
-- This migration extends the phase-one execution graph protocol to the
-- remaining transfer writers without changing their public contracts.

-- Lock a complete execution graph when the caller already knows the affected
-- lines.  This also covers line-unallocated remainder closures, which have no
-- allocation ID from which the original helper can derive a line.
create or replace function public.inventory_lock_transfer_execution_lines(
  p_transfer_id uuid,
  p_line_ids uuid[]
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
  select array_agg(distinct l.id order by l.id)
    into line_ids
    from public.inventory_transfer_lines l
    where l.transfer_id=p_transfer_id
      and l.id=any(coalesce(p_line_ids,array[]::uuid[]));

  if coalesce(cardinality(line_ids),0)=0 then
    return;
  end if;

  select array_agg(a.id order by a.id)
    into graph_allocation_ids
    from public.inventory_transfer_allocations a
    where a.transfer_line_id=any(line_ids);

  for ignored in
    select l.id from public.inventory_transfer_lines l
    where l.id=any(line_ids) order by l.id for update
  loop null; end loop;

  for ignored in
    select a.id from public.inventory_transfer_allocations a
    where a.id=any(coalesce(graph_allocation_ids,array[]::uuid[]))
    order by a.id for update
  loop null; end loop;

  for ignored in
    select r.id from public.inventory_reservations r
    where r.transfer_allocation_id=any(coalesce(graph_allocation_ids,array[]::uuid[]))
    order by r.id for update
  loop null; end loop;

  for ignored in
    select o.id from public.inventory_transfer_operations o
    where o.transfer_id=p_transfer_id
      and o.transfer_allocation_id=any(coalesce(graph_allocation_ids,array[]::uuid[]))
    order by o.id for update
  loop null; end loop;

  for ignored in
    select rd.id from public.inventory_transfer_receipt_destinations rd
    join public.inventory_transfer_operations o on o.id=rd.operation_id
    where o.transfer_id=p_transfer_id
      and o.transfer_allocation_id=any(coalesce(graph_allocation_ids,array[]::uuid[]))
    order by rd.id for update of rd
  loop null; end loop;

  for ignored in
    select c.id from public.inventory_transfer_remainder_closures c
    where c.transfer_id=p_transfer_id and c.transfer_line_id=any(line_ids)
    order by c.id for update
  loop null; end loop;

  for ignored in
    select ra.id from public.inventory_reservation_adjustments ra
    where ra.transfer_id=p_transfer_id
      and ra.transfer_allocation_id=any(coalesce(graph_allocation_ids,array[]::uuid[]))
    order by ra.id for update
  loop null; end loop;
end;
$$;

-- Preserve the phase-one helper signature used by issue and resolution while
-- delegating the actual ordering to the line-aware implementation above.
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
begin
  select array_agg(distinct a.transfer_line_id order by a.transfer_line_id)
    into line_ids
    from public.inventory_transfer_allocations a
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where l.transfer_id=p_transfer_id
      and a.id=any(coalesce(p_allocation_ids,array[]::uuid[]));

  perform public.inventory_lock_transfer_execution_lines(p_transfer_id,line_ids);
end;
$$;

create or replace function public.reserve_inventory_transfer(
  p_transfer uuid,
  p_expires_at timestamptz,
  p_key text,
  p_hash text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  transfer_row public.inventory_transfers%rowtype;
  command_id uuid;
  allocation_ids uuid[];
  physical_grains jsonb;
  allocation_row record;
  available_qty numeric;
  reserved_qty numeric;
begin
  select * into transfer_row from public.inventory_transfers
  where id=p_transfer for update;
  if not found or p_expires_at is null or p_expires_at<=now()
     or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.reserve') then
    raise exception 'Inventory transfer reservation denied';
  end if;

  command_id:=public.claim_inventory_transfer_command(
    p_transfer,'transfer_reserve',p_key,p_hash,
    jsonb_build_object('transfer_id',p_transfer,'expires_at',p_expires_at),null
  );
  if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then
    return p_transfer;
  end if;
  if transfer_row.status<>'draft' then
    raise exception 'Inventory transfer reservation denied';
  end if;

  select array_agg(a.id order by a.id) into allocation_ids
  from public.inventory_transfer_allocations a
  join public.inventory_transfer_lines l on l.id=a.transfer_line_id
  where l.transfer_id=p_transfer;
  perform public.inventory_lock_transfer_execution_graph(p_transfer,allocation_ids);

  select jsonb_agg(jsonb_build_object(
    'tenant_id',transfer_row.tenant_id,'organization_id',transfer_row.organization_id,
    'facility_id',transfer_row.facility_id,'location_id',a.source_location_id,
    'inventory_item_profile_id',l.inventory_item_profile_id,'batch_id',a.batch_id,
    'recording_channel',a.recording_channel,'disposition','available'
  ) order by a.id) into physical_grains
  from public.inventory_transfer_allocations a
  join public.inventory_transfer_lines l on l.id=a.transfer_line_id
  where l.transfer_id=p_transfer;
  perform public.inventory_lock_physical_grains(coalesce(physical_grains,'[]'::jsonb));

  -- All mutable graph and physical-grain state is locked before these checks.
  select * into transfer_row from public.inventory_transfers
  where id=p_transfer for update;
  if not found or transfer_row.status<>'draft' or p_expires_at is null or p_expires_at<=now()
     or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.reserve') then
    raise exception 'Inventory transfer reservation denied';
  end if;

  for allocation_row in
    select a.*,l.inventory_item_profile_id
    from public.inventory_transfer_allocations a
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where l.transfer_id=p_transfer
    order by public.inventory_physical_grain_key(
      transfer_row.tenant_id,transfer_row.organization_id,transfer_row.facility_id,
      a.source_location_id,l.inventory_item_profile_id,a.batch_id,
      a.recording_channel,'available'::public.inventory_stock_disposition
    ),a.id
  loop
    select coalesce((
      select bp.quantity_base
      from public.inventory_balance_projections bp
      where bp.tenant_id=transfer_row.tenant_id
        and bp.organization_id=transfer_row.organization_id
        and bp.facility_id=transfer_row.facility_id
        and bp.location_id=allocation_row.source_location_id
        and bp.inventory_item_profile_id=allocation_row.inventory_item_profile_id
        and bp.batch_id is not distinct from allocation_row.batch_id
        and bp.recording_channel=allocation_row.recording_channel
        and bp.disposition='available'
      for update
    ),0) into available_qty;

    select coalesce(sum(public.inventory_transfer_reservation_remaining(r.id)),0)
      into reserved_qty
    from public.inventory_reservations r
    join public.inventory_transfer_allocations existing_allocation
      on existing_allocation.id=r.transfer_allocation_id
    join public.inventory_transfer_lines existing_line
      on existing_line.id=existing_allocation.transfer_line_id
    join public.inventory_transfers existing_transfer
      on existing_transfer.id=existing_line.transfer_id
    where existing_transfer.tenant_id=transfer_row.tenant_id
      and existing_transfer.organization_id=transfer_row.organization_id
      and existing_transfer.facility_id=transfer_row.facility_id
      and existing_allocation.source_location_id=allocation_row.source_location_id
      and existing_line.inventory_item_profile_id=allocation_row.inventory_item_profile_id
      and existing_allocation.batch_id is not distinct from allocation_row.batch_id
      and existing_allocation.recording_channel=allocation_row.recording_channel
      and r.expires_at>now();

    if available_qty-reserved_qty<allocation_row.planned_quantity_base then
      raise exception 'Inventory transfer reservation exceeds available-to-promise'
        using errcode='23514';
    end if;
    insert into public.inventory_reservations(
      transfer_allocation_id,quantity_base,expires_at,created_by
    ) values (
      allocation_row.id,allocation_row.planned_quantity_base,p_expires_at,auth.uid()
    );
  end loop;

  update public.inventory_commands set status='posted',posted_at=now(),
    payload=payload||jsonb_build_object('result_transfer_id',p_transfer)
  where id=command_id;
  perform public.inventory_transfer_refresh_status(p_transfer);
  perform public.inventory_transfer_write_event(
    p_transfer,command_id,null,'inventory.transfer_reserved',
    jsonb_build_object('expires_at',p_expires_at)
  );
  return p_transfer;
end;
$$;

create or replace function public.cancel_inventory_transfer(
  p_transfer uuid,
  p_key text,
  p_hash text,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  t public.inventory_transfers%rowtype;
  cmd uuid;
  allocation_ids uuid[];
  r record;
begin
  select * into t from public.inventory_transfers where id=p_transfer for update;
  if not found or coalesce(trim(p_reason),'')=''
     or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.cancel') then
    raise exception 'Inventory transfer cancellation denied';
  end if;

  cmd:=public.claim_inventory_transfer_command(
    p_transfer,'transfer_cancel',p_key,p_hash,
    jsonb_build_object('transfer_id',p_transfer),p_reason
  );
  if (select payload ? 'result_transfer_id' from public.inventory_commands where id=cmd) then
    return p_transfer;
  end if;
  if t.status not in ('draft','reserved')
     or exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue') then
    raise exception 'Inventory transfer cancellation denied';
  end if;

  select array_agg(a.id order by a.id) into allocation_ids
  from public.inventory_transfer_allocations a
  join public.inventory_transfer_lines l on l.id=a.transfer_line_id
  where l.transfer_id=p_transfer;
  perform public.inventory_lock_transfer_execution_graph(p_transfer,allocation_ids);

  select * into t from public.inventory_transfers where id=p_transfer for update;
  if not found or t.status not in ('draft','reserved')
     or exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue')
     or coalesce(trim(p_reason),'')=''
     or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.cancel') then
    raise exception 'Inventory transfer cancellation denied';
  end if;

  for r in
    select rr.id reservation_id,a.id allocation_id,
           public.inventory_transfer_reservation_remaining(rr.id) q
    from public.inventory_reservations rr
    join public.inventory_transfer_allocations a on a.id=rr.transfer_allocation_id
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where l.transfer_id=p_transfer
    order by rr.id
  loop
    if r.q>0 then
      perform public.append_inventory_reservation_adjustment(
        r.reservation_id,r.allocation_id,p_transfer,cmd,'manually_released',
        r.q,null,null,trim(p_reason)
      );
    end if;
  end loop;
  insert into public.inventory_transfer_operations(
    transfer_id,command_id,operation_type,reason,created_by
  ) values (p_transfer,cmd,'cancel',trim(p_reason),auth.uid());
  update public.inventory_commands set status='posted',posted_at=now(),
    payload=payload||jsonb_build_object('result_transfer_id',p_transfer)
  where id=cmd;
  perform public.inventory_transfer_refresh_status(p_transfer);
  perform public.inventory_transfer_write_event(
    p_transfer,cmd,null,'inventory.transfer_cancelled',
    jsonb_build_object('reason',trim(p_reason))
  );
  return p_transfer;
end;
$$;

create or replace function public.close_inventory_transfer_remainder(
  p_transfer uuid,
  p_closures jsonb,
  p_key text,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  transfer_row public.inventory_transfers%rowtype;
  command_id uuid;
  closure_item jsonb;
  canonical jsonb;
  request_hash text;
  line_ids uuid[];
  line_row public.inventory_transfer_lines%rowtype;
  allocation_row public.inventory_transfer_allocations%rowtype;
  reservation_row public.inventory_reservations%rowtype;
  quantity numeric;
  issued_qty numeric;
  closed_qty numeric;
  planned_qty numeric;
  line_new_qty numeric;
  line_new_unallocated_qty numeric;
  allocation_new_qty numeric;
  closure_id uuid;
begin
  if jsonb_typeof(p_closures)<>'array' or jsonb_array_length(p_closures)=0
     or coalesce(trim(p_reason),'')='' then
    raise exception 'Inventory transfer remainder closure denied';
  end if;
  select jsonb_agg(value order by coalesce(value->>'transfer_allocation_id',''),
                   value->>'transfer_line_id',value->>'quantity_base')
    into canonical from jsonb_array_elements(p_closures);
  request_hash:=encode(extensions.digest(convert_to(
    jsonb_build_object('version',1,'action','transfer_close_remainder',
      'transfer_id',p_transfer,'closures',canonical,'reason',trim(p_reason))::text,
    'utf8'),'sha256'),'hex');

  select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
  if not found then raise exception 'Inventory transfer remainder closure denied'; end if;
  if not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.close_remainder') then
    raise exception 'Inventory transfer remainder closure authorization denied';
  end if;

  command_id:=public.claim_inventory_transfer_command(
    p_transfer,'transfer_close_remainder',p_key,request_hash,
    jsonb_build_object('version',1,'closures',canonical),trim(p_reason)
  );
  if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then
    return p_transfer;
  end if;
  if transfer_row.status in ('draft','reserved','cancelled','completed')
     or not exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue') then
    raise exception 'Inventory transfer remainder closure lifecycle denied';
  end if;

  select array_agg(distinct (x.value->>'transfer_line_id')::uuid
                   order by (x.value->>'transfer_line_id')::uuid)
    into line_ids from jsonb_array_elements(canonical) x;
  perform public.inventory_lock_transfer_execution_lines(p_transfer,line_ids);

  select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
  if not found then raise exception 'Inventory transfer remainder closure denied'; end if;
  if transfer_row.status in ('draft','reserved','cancelled','completed')
     or not exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue') then
    raise exception 'Inventory transfer remainder closure lifecycle denied';
  end if;
  if not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.close_remainder') then
    raise exception 'Inventory transfer remainder closure authorization denied';
  end if;

  for closure_item in select value from jsonb_array_elements(canonical) loop
    select * into line_row from public.inventory_transfer_lines l
    where l.id=(closure_item->>'transfer_line_id')::uuid and l.transfer_id=p_transfer;
    quantity:=(closure_item->>'quantity_base')::numeric;
    if not found or quantity<=0
       or (closure_item->>'inventory_item_profile_id')::uuid is distinct from line_row.inventory_item_profile_id then
      raise exception 'Inventory transfer remainder closure denied';
    end if;
    select coalesce(sum(o.quantity_base),0) into issued_qty
    from public.inventory_transfer_operations o
    join public.inventory_transfer_allocations a on a.id=o.transfer_allocation_id
    where a.transfer_line_id=line_row.id and o.operation_type='issue';
    select coalesce(sum(c.quantity_base),0) into closed_qty
    from public.inventory_transfer_remainder_closures c where c.transfer_line_id=line_row.id;
    select coalesce(sum((x.value->>'quantity_base')::numeric),0) into line_new_qty
    from jsonb_array_elements(canonical) x
    where (x.value->>'transfer_line_id')::uuid=line_row.id;
    if issued_qty+closed_qty+line_new_qty>line_row.requested_quantity_base then
      raise exception 'Inventory transfer remainder closure exceeds line requested quantity' using errcode='23514';
    end if;
    if closure_item ? 'transfer_allocation_id'
       and nullif(closure_item->>'transfer_allocation_id','') is not null then
      select * into allocation_row from public.inventory_transfer_allocations a
      where a.id=(closure_item->>'transfer_allocation_id')::uuid
        and a.transfer_line_id=line_row.id;
      if not found then raise exception 'Inventory transfer remainder closure allocation denied'; end if;
      select coalesce(sum(o.quantity_base),0) into issued_qty
      from public.inventory_transfer_operations o
      where o.transfer_allocation_id=allocation_row.id and o.operation_type='issue';
      select coalesce(sum(c.quantity_base),0) into closed_qty
      from public.inventory_transfer_remainder_closures c where c.transfer_allocation_id=allocation_row.id;
      select coalesce(sum((x.value->>'quantity_base')::numeric),0) into allocation_new_qty
      from jsonb_array_elements(canonical) x
      where nullif(x.value->>'transfer_allocation_id','')::uuid=allocation_row.id;
      if issued_qty+closed_qty+allocation_new_qty>allocation_row.planned_quantity_base then
        raise exception 'Inventory transfer remainder closure exceeds allocation remaining' using errcode='23514';
      end if;
      select * into reservation_row from public.inventory_reservations r
      where r.transfer_allocation_id=allocation_row.id;
      if not found or allocation_new_qty>public.inventory_transfer_reservation_remaining(reservation_row.id) then
        raise exception 'Inventory transfer remainder closure exceeds reservation remaining' using errcode='23514';
      end if;
      insert into public.inventory_transfer_remainder_closures(
        transfer_id,transfer_line_id,transfer_allocation_id,inventory_item_profile_id,
        reservation_id,quantity_base,command_id,reason,created_by
      ) values (
        p_transfer,line_row.id,allocation_row.id,line_row.inventory_item_profile_id,
        reservation_row.id,quantity,command_id,trim(p_reason),auth.uid()
      ) returning id into closure_id;
      perform public.append_inventory_reservation_adjustment(
        reservation_row.id,allocation_row.id,p_transfer,command_id,'closure_released',
        quantity,null,closure_id,trim(p_reason)
      );
    else
      select coalesce(sum(a.planned_quantity_base),0) into planned_qty
      from public.inventory_transfer_allocations a where a.transfer_line_id=line_row.id;
      select coalesce(sum(c.quantity_base),0) into closed_qty
      from public.inventory_transfer_remainder_closures c
      where c.transfer_line_id=line_row.id and c.transfer_allocation_id is null;
      select coalesce(sum((x.value->>'quantity_base')::numeric),0)
        into line_new_unallocated_qty
      from jsonb_array_elements(canonical) x
      where (x.value->>'transfer_line_id')::uuid=line_row.id
        and nullif(x.value->>'transfer_allocation_id','') is null;
      if line_new_unallocated_qty+closed_qty>line_row.requested_quantity_base-coalesce(planned_qty,0) then
        raise exception 'Inventory transfer remainder closure exceeds line remaining' using errcode='23514';
      end if;
      insert into public.inventory_transfer_remainder_closures(
        transfer_id,transfer_line_id,inventory_item_profile_id,quantity_base,
        command_id,reason,created_by
      ) values (
        p_transfer,line_row.id,line_row.inventory_item_profile_id,quantity,
        command_id,trim(p_reason),auth.uid()
      ) returning id into closure_id;
    end if;
    perform public.inventory_transfer_write_event(
      p_transfer,command_id,null,'inventory.transfer_remainder_closed',
      jsonb_build_object('closure_id',closure_id,'quantity_base',quantity)
    );
  end loop;
  update public.inventory_commands set status='posted',posted_at=now(),
    payload=payload||jsonb_build_object('result_transfer_id',p_transfer)
  where id=command_id;
  perform public.inventory_transfer_refresh_status(p_transfer);
  return p_transfer;
end;
$$;

-- Retain SKIP LOCKED only for worker scheduling.  Once selected, each
-- reservation enters the same deterministic graph lock protocol as clients.
create or replace function public.expire_inventory_transfer_reservations(
  p_actor uuid,
  p_limit integer default 100
) returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  candidate record;
  transfer_row public.inventory_transfers%rowtype;
  allocation_row public.inventory_transfer_allocations%rowtype;
  reservation_row public.inventory_reservations%rowtype;
  command_id uuid;
  remaining_quantity numeric;
  request_key text;
  request_hash text;
  expired_count integer:=0;
begin
  if auth.role()<>'service_role' then
    raise exception 'Inventory reservation expiry requires trusted execution' using errcode='42501';
  end if;
  if p_actor is null or p_limit is null or p_limit not between 1 and 1000 then
    raise exception 'Inventory reservation expiry invocation is invalid' using errcode='22023';
  end if;
  perform set_config('request.jwt.claim.sub',p_actor::text,true);

  for candidate in
    select rr.id as reservation_id,a.id as allocation_id,l.transfer_id
    from public.inventory_reservations rr
    join public.inventory_transfer_allocations a on a.id=rr.transfer_allocation_id
    join public.inventory_transfer_lines l on l.id=a.transfer_line_id
    where rr.expires_at<=now()
      and public.inventory_transfer_reservation_remaining(rr.id)>0
    order by rr.expires_at,rr.id limit p_limit
  loop
    select * into transfer_row from public.inventory_transfers
    where id=candidate.transfer_id for update skip locked;
    if not found then continue; end if;

    perform public.inventory_lock_transfer_execution_graph(
      transfer_row.id,array[candidate.allocation_id]
    );

    select * into transfer_row from public.inventory_transfers
    where id=candidate.transfer_id for update;
    if not found or transfer_row.status in ('cancelled','completed') then continue; end if;
    if not public.inventory_actor_has_permission(
      p_actor,'inventory.transfer.reserve',transfer_row.tenant_id,
      transfer_row.organization_id,transfer_row.facility_id
    ) then
      raise exception 'Inventory reservation expiry actor is not authorized' using errcode='42501';
    end if;
    select * into allocation_row from public.inventory_transfer_allocations a
    where a.id=candidate.allocation_id and a.transfer_line_id in (
      select l.id from public.inventory_transfer_lines l where l.transfer_id=transfer_row.id
    );
    if not found then
      raise exception 'Inventory reservation expiry allocation integrity denied' using errcode='23503';
    end if;
    select * into reservation_row from public.inventory_reservations r
    where r.id=candidate.reservation_id and r.transfer_allocation_id=allocation_row.id;
    if not found or reservation_row.expires_at>now() then continue; end if;
    remaining_quantity:=public.inventory_transfer_reservation_remaining(reservation_row.id);
    if remaining_quantity<=0 then continue; end if;

    request_key:='reservation-expiry:'||reservation_row.id::text;
    request_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
      'version',1,'action','transfer_reservation_expire','transfer_id',transfer_row.id,
      'reservation_id',reservation_row.id,'expires_at',reservation_row.expires_at
    )::text,'utf8'),'sha256'),'hex');
    command_id:=public.claim_inventory_transfer_command(
      transfer_row.id,'transfer_reservation_expire',request_key,request_hash,
      jsonb_build_object('version',1,'transfer_id',transfer_row.id,
        'reservation_id',reservation_row.id,'expires_at',reservation_row.expires_at),
      'reservation expiry'
    );
    if (select payload ? 'result_reservation_id' from public.inventory_commands where id=command_id) then
      continue;
    end if;
    perform public.append_inventory_reservation_adjustment(
      reservation_row.id,allocation_row.id,transfer_row.id,command_id,
      'expiry_released',remaining_quantity,null,null,'reservation expiry',
      jsonb_build_object('expires_at',reservation_row.expires_at)
    );
    update public.inventory_commands set status='posted',posted_at=now(),
      payload=payload||jsonb_build_object('result_transfer_id',transfer_row.id,
        'result_reservation_id',reservation_row.id,
        'expired_quantity_base',remaining_quantity)
    where id=command_id;
    perform public.inventory_transfer_write_event(
      transfer_row.id,command_id,null,'inventory.transfer_reservation_expired',
      jsonb_build_object('reservation_id',reservation_row.id,
        'quantity_base',remaining_quantity,'expires_at',reservation_row.expires_at)
    );
    perform public.inventory_transfer_refresh_status(transfer_row.id);
    expired_count:=expired_count+1;
  end loop;
  return expired_count;
end;
$$;

drop function if exists public.expire_inventory_transfer_reservations();

revoke all on function public.inventory_lock_transfer_execution_lines(uuid,uuid[])
  from public,anon,authenticated,service_role;
revoke all on function public.inventory_lock_transfer_execution_graph(uuid,uuid[])
  from public,anon,authenticated,service_role;
