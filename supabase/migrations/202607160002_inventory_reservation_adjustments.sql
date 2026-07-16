-- Phase Two reservation accounting, Phase One.  Adjustment rows are the
-- single source of truth for reservation consumption and releases.  Expiry,
-- backfill, reversal and manual-release APIs are deliberately deferred.

create type public.inventory_reservation_adjustment_type as enum (
  'issue_consumed',
  'manually_released',
  'closure_released'
);

create table public.inventory_reservation_adjustments (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.inventory_reservations(id) on delete restrict,
  transfer_allocation_id uuid not null references public.inventory_transfer_allocations(id) on delete restrict,
  transfer_id uuid not null references public.inventory_transfers(id) on delete restrict,
  command_id uuid not null references public.inventory_commands(id) on delete restrict,
  adjustment_type public.inventory_reservation_adjustment_type not null,
  quantity_base numeric(20,6) not null check(quantity_base>0),
  related_operation_id uuid references public.inventory_transfer_operations(id) on delete restrict,
  related_closure_id uuid references public.inventory_transfer_remainder_closures(id) on delete restrict,
  reason text not null check(nullif(trim(reason),'') is not null),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  check(not (metadata ?| array['password','token','secret','access_token'])),
  unique nulls not distinct(command_id,reservation_id,adjustment_type,related_operation_id,related_closure_id)
);

-- A single idempotent issue command may intentionally contain multiple JSON
-- issue grains for the same allocation.  Command ownership prevents replay;
-- this older operation-grain uniqueness would incorrectly reject the second
-- legitimate row before its matching adjustment could be recorded.
alter table public.inventory_transfer_operations
  drop constraint if exists inventory_transfer_operations_command_id_transfer_allocatio_key;

-- Preserve duplicate-grain protection for every non-issue operation while
-- intentionally allowing repeated issue grains within one idempotent command.
create unique index inventory_transfer_operations_non_issue_command_grain_uidx
  on public.inventory_transfer_operations (
    command_id,
    transfer_allocation_id,
    operation_type,
    destination_location_id
  ) nulls not distinct
  where operation_type <> 'issue';

-- Reservation rows are created once by the reserve command.  Their quantity
-- and expiry are historical facts; availability is derived only from the
-- append-only adjustment ledger below.
create or replace function public.prevent_inventory_reservation_mutation() returns trigger language plpgsql security definer set search_path=public as $$
begin
  raise exception 'Posted inventory reservation records are append-only' using errcode='42501';
end $$;
create trigger inventory_reservations_immutable before update or delete on public.inventory_reservations for each row execute function public.prevent_inventory_reservation_mutation();
create trigger inventory_reservation_adjustments_immutable before update or delete on public.inventory_reservation_adjustments for each row execute function public.prevent_inventory_reservation_mutation();

create or replace function public.enforce_inventory_reservation_adjustment_integrity() returns trigger language plpgsql security definer set search_path=public as $$
declare
  reservation_row public.inventory_reservations%rowtype;
  allocation_row public.inventory_transfer_allocations%rowtype;
  line_row public.inventory_transfer_lines%rowtype;
  transfer_row public.inventory_transfers%rowtype;
  command_row public.inventory_commands%rowtype;
  operation_row public.inventory_transfer_operations%rowtype;
  closure_row public.inventory_transfer_remainder_closures%rowtype;
  adjusted_total numeric;
begin
  select * into reservation_row from public.inventory_reservations where id=new.reservation_id for update;
  select * into allocation_row from public.inventory_transfer_allocations where id=new.transfer_allocation_id;
  if not found or reservation_row.transfer_allocation_id<>allocation_row.id then
    raise exception 'Inventory reservation adjustment allocation integrity denied' using errcode='23503';
  end if;
  select * into line_row from public.inventory_transfer_lines where id=allocation_row.transfer_line_id;
  select * into transfer_row from public.inventory_transfers where id=new.transfer_id;
  if not found or line_row.transfer_id<>transfer_row.id then
    raise exception 'Inventory reservation adjustment transfer integrity denied' using errcode='23503';
  end if;
  select * into command_row from public.inventory_commands where id=new.command_id;
  if not found
     or (command_row.tenant_id,command_row.organization_id,command_row.facility_id) is distinct from (transfer_row.tenant_id,transfer_row.organization_id,transfer_row.facility_id)
     or command_row.requester_id<>new.created_by then
    raise exception 'Inventory reservation adjustment command integrity denied' using errcode='23503';
  end if;

  if new.adjustment_type='issue_consumed' then
    select * into operation_row from public.inventory_transfer_operations where id=new.related_operation_id;
    if new.related_operation_id is null or new.related_closure_id is not null
       or not found or operation_row.operation_type<>'issue'
       or operation_row.transfer_id<>new.transfer_id
       or operation_row.transfer_allocation_id<>new.transfer_allocation_id
       or operation_row.command_id<>new.command_id
       or operation_row.quantity_base<>new.quantity_base
       or command_row.command_type<>'transfer_issue' then
      raise exception 'Inventory reservation issue adjustment integrity denied' using errcode='23503';
    end if;
  elsif new.adjustment_type='closure_released' then
    select * into closure_row from public.inventory_transfer_remainder_closures where id=new.related_closure_id;
    if new.related_operation_id is not null or new.related_closure_id is null
       or not found or closure_row.transfer_id<>new.transfer_id
       or closure_row.transfer_allocation_id<>new.transfer_allocation_id
       or closure_row.reservation_id<>new.reservation_id
       or closure_row.command_id<>new.command_id
       or closure_row.quantity_base<>new.quantity_base
       or command_row.command_type<>'transfer_close_remainder' then
      raise exception 'Inventory reservation closure adjustment integrity denied' using errcode='23503';
    end if;
  elsif new.adjustment_type='manually_released' then
    if new.related_operation_id is not null or new.related_closure_id is not null
       or command_row.command_type<>'transfer_cancel' then
      raise exception 'Inventory reservation release adjustment integrity denied' using errcode='23503';
    end if;
  else
    raise exception 'Inventory reservation adjustment type denied' using errcode='23503';
  end if;

  select coalesce(sum(quantity_base),0) into adjusted_total
    from public.inventory_reservation_adjustments where reservation_id=new.reservation_id;
  if adjusted_total+new.quantity_base>reservation_row.quantity_base then
    raise exception 'Inventory reservation adjustment exceeds reservation quantity' using errcode='23514';
  end if;
  return new;
end $$;
create trigger inventory_reservation_adjustment_integrity before insert on public.inventory_reservation_adjustments for each row execute function public.enforce_inventory_reservation_adjustment_integrity();

create or replace function public.enforce_inventory_reservation_adjustment_total() returns trigger language plpgsql security definer set search_path=public as $$
declare reservation_row public.inventory_reservations%rowtype; adjusted_total numeric; begin
  select * into reservation_row from public.inventory_reservations where id=new.reservation_id for update;
  select coalesce(sum(quantity_base),0) into adjusted_total from public.inventory_reservation_adjustments where reservation_id=new.reservation_id;
  if not found or adjusted_total>reservation_row.quantity_base then
    raise exception 'Inventory reservation adjustment exceeds reservation quantity' using errcode='23514';
  end if;
  return null;
end $$;
create constraint trigger inventory_reservation_adjustment_total_guard after insert on public.inventory_reservation_adjustments deferrable initially deferred for each row execute function public.enforce_inventory_reservation_adjustment_total();

-- Private only.  Controlled transfer functions have already locked their
-- transfer/allocation/reservation context; the insert trigger repeats the
-- relational and remaining-quantity checks for defence in depth.
create or replace function public.append_inventory_reservation_adjustment(
  p_reservation uuid,
  p_allocation uuid,
  p_transfer uuid,
  p_command uuid,
  p_type public.inventory_reservation_adjustment_type,
  p_quantity numeric,
  p_operation uuid,
  p_closure uuid,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare adjustment_id uuid; reservation_row public.inventory_reservations%rowtype; adjusted_total numeric; begin
  select * into reservation_row from public.inventory_reservations where id=p_reservation and transfer_allocation_id=p_allocation for update;
  if not found or p_quantity<=0 or coalesce(trim(p_reason),'')='' or p_metadata ?| array['password','token','secret','access_token'] then
    raise exception 'Inventory reservation adjustment denied';
  end if;
  select coalesce(sum(quantity_base),0) into adjusted_total from public.inventory_reservation_adjustments where reservation_id=p_reservation;
  if adjusted_total+p_quantity>reservation_row.quantity_base then
    raise exception 'Inventory reservation adjustment exceeds reservation quantity' using errcode='23514';
  end if;
  insert into public.inventory_reservation_adjustments(reservation_id,transfer_allocation_id,transfer_id,command_id,adjustment_type,quantity_base,related_operation_id,related_closure_id,reason,metadata,created_by)
  values(p_reservation,p_allocation,p_transfer,p_command,p_type,p_quantity,p_operation,p_closure,trim(p_reason),coalesce(p_metadata,'{}'::jsonb),auth.uid()) returning id into adjustment_id;
  return adjustment_id;
end $$;

create or replace function public.inventory_transfer_reservation_remaining(p_reservation uuid) returns numeric language sql stable security definer set search_path=public as $$
  select greatest(0,r.quantity_base-coalesce((select sum(a.quantity_base) from public.inventory_reservation_adjustments a where a.reservation_id=r.id),0))
  from public.inventory_reservations r where r.id=p_reservation;
$$;

create or replace function public.issue_inventory_transfer(p_transfer uuid,p_issues jsonb,p_key text,p_hash text,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare transfer_row public.inventory_transfers%rowtype; command_id uuid; transaction_id uuid; item jsonb; allocation_row record; reservation_row public.inventory_reservations%rowtype; quantity numeric; reservation_requested_now numeric; allocation_requested_now numeric; line_existing_issued numeric; line_closed numeric; line_requested_now numeric; entries jsonb:='[]'::jsonb; operation_id uuid; base_unit_id uuid; begin
 select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
 if not found or transfer_row.status not in ('reserved','partially_issued','issued') or jsonb_typeof(p_issues)<>'array' or jsonb_array_length(p_issues)=0 or coalesce(trim(p_reason),'')='' or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.issue') then raise exception 'Inventory transfer issue denied'; end if;
 command_id:=public.claim_inventory_transfer_command(p_transfer,'transfer_issue',p_key,p_hash,jsonb_build_object('issues',p_issues),p_reason); if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then return p_transfer; end if;
 for item in select value from jsonb_array_elements(p_issues) loop
  select ia.*,il.inventory_item_profile_id,il.requested_quantity_base into allocation_row from public.inventory_transfer_allocations ia join public.inventory_transfer_lines il on il.id=ia.transfer_line_id where ia.id=(item->>'transfer_allocation_id')::uuid and il.transfer_id=p_transfer for update;
  select * into reservation_row from public.inventory_reservations ir where ir.transfer_allocation_id=allocation_row.id for update; quantity:=(item->>'quantity_base')::numeric;
  if not found or quantity<=0 or reservation_row.expires_at<=now() then raise exception 'Inventory transfer issue reservation denied'; end if;
  select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into reservation_requested_now from jsonb_array_elements(p_issues) request_item join public.inventory_reservations request_reservation on request_reservation.transfer_allocation_id=(request_item.value->>'transfer_allocation_id')::uuid where request_reservation.id=reservation_row.id;
  if reservation_requested_now>public.inventory_transfer_reservation_remaining(reservation_row.id) then raise exception 'Inventory transfer issue exceeds reservation remaining quantity' using errcode='23514'; end if;
  select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into allocation_requested_now from jsonb_array_elements(p_issues) request_item where (request_item.value->>'transfer_allocation_id')::uuid=allocation_row.id;
  if allocation_requested_now+coalesce((select sum(o.quantity_base) from public.inventory_transfer_operations o where o.transfer_allocation_id=allocation_row.id and o.operation_type='issue'),0)+coalesce((select sum(c.quantity_base) from public.inventory_transfer_remainder_closures c where c.transfer_allocation_id=allocation_row.id),0)>allocation_row.planned_quantity_base then raise exception 'Inventory transfer issue exceeds allocation planned quantity' using errcode='23514'; end if;
  select coalesce(sum(o.quantity_base),0) into line_existing_issued from public.inventory_transfer_operations o join public.inventory_transfer_allocations a on a.id=o.transfer_allocation_id where a.transfer_line_id=allocation_row.transfer_line_id and o.operation_type='issue';
  select coalesce(sum(c.quantity_base),0) into line_closed from public.inventory_transfer_remainder_closures c where c.transfer_line_id=allocation_row.transfer_line_id;
  select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into line_requested_now from jsonb_array_elements(p_issues) request_item join public.inventory_transfer_allocations request_allocation on request_allocation.id=(request_item.value->>'transfer_allocation_id')::uuid where request_allocation.transfer_line_id=allocation_row.transfer_line_id;
  if line_existing_issued+line_closed+line_requested_now>allocation_row.requested_quantity_base then raise exception 'Inventory transfer issue exceeds line requested quantity' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',allocation_row.source_location_id::text,allocation_row.inventory_item_profile_id::text,allocation_row.batch_id::text,allocation_row.recording_channel::text,'available'),0));
  if not exists(select 1 from public.inventory_balance_projections bp where bp.location_id=allocation_row.source_location_id and bp.inventory_item_profile_id=allocation_row.inventory_item_profile_id and bp.batch_id=allocation_row.batch_id and bp.recording_channel=allocation_row.recording_channel and bp.disposition='available' and bp.quantity_base>=quantity) then raise exception 'Inventory transfer issue would create negative physical balance' using errcode='23514'; end if;
  select iu.id into base_unit_id from public.inventory_item_units iu where iu.inventory_item_profile_id=allocation_row.inventory_item_profile_id and iu.active and iu.is_base_unit;
  entries:=entries||jsonb_build_array(jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,'channel',allocation_row.recording_channel,'account_type','physical','location_id',allocation_row.source_location_id,'disposition','available','quantity_base',-quantity),jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,'channel',allocation_row.recording_channel,'account_type','physical','location_id',transfer_row.transit_location_id,'disposition','transit','quantity_base',quantity));
 end loop;
 insert into public.inventory_transactions(tenant_id,organization_id,facility_id,command_id,transaction_type,posted_by,reason) values(transfer_row.tenant_id,transfer_row.organization_id,transfer_row.facility_id,command_id,'transfer_issue',auth.uid(),trim(p_reason)) returning id into transaction_id; perform public.inventory_post_entries(transaction_id,entries,'inventory.transfer_issued',jsonb_build_object('transfer_id',p_transfer));
 for item in select value from jsonb_array_elements(p_issues) loop
  select ia.*,il.inventory_item_profile_id,r.id as reservation_id into allocation_row from public.inventory_transfer_allocations ia join public.inventory_transfer_lines il on il.id=ia.transfer_line_id join public.inventory_reservations r on r.transfer_allocation_id=ia.id where ia.id=(item->>'transfer_allocation_id')::uuid;
  quantity:=(item->>'quantity_base')::numeric;
  insert into public.inventory_transfer_operations(transfer_id,transfer_allocation_id,command_id,transaction_id,operation_type,inventory_item_profile_id,batch_id,recording_channel,source_location_id,destination_location_id,source_disposition,destination_disposition,quantity_base,reason,created_by) values(p_transfer,allocation_row.id,command_id,transaction_id,'issue',allocation_row.inventory_item_profile_id,allocation_row.batch_id,allocation_row.recording_channel,allocation_row.source_location_id,transfer_row.transit_location_id,'available','transit',quantity,trim(p_reason),auth.uid()) returning id into operation_id;
  perform public.append_inventory_reservation_adjustment(allocation_row.reservation_id,allocation_row.id,p_transfer,command_id,'issue_consumed',quantity,operation_id,null,trim(p_reason));
  perform public.inventory_transfer_write_event(p_transfer,command_id,operation_id,'inventory.transfer_issued',jsonb_build_object('quantity_base',quantity));
 end loop;
 update public.inventory_commands set status='posted',posted_at=now(),result_transaction_id=transaction_id,payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=command_id; perform public.inventory_transfer_refresh_status(p_transfer); return p_transfer;
end $$;

create or replace function public.cancel_inventory_transfer(p_transfer uuid,p_key text,p_hash text,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare t public.inventory_transfers%rowtype; cmd uuid; r record; begin
 select * into t from public.inventory_transfers where id=p_transfer for update;
 if not found or t.status not in ('draft','reserved') or exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue') or coalesce(trim(p_reason),'')='' or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.cancel') then raise exception 'Inventory transfer cancellation denied'; end if;
 cmd:=public.claim_inventory_transfer_command(p_transfer,'transfer_cancel',p_key,p_hash,jsonb_build_object('transfer_id',p_transfer),p_reason);
 if (select payload ? 'result_transfer_id' from public.inventory_commands where id=cmd) then return p_transfer; end if;
 for r in select rr.id reservation_id,a.id allocation_id,public.inventory_transfer_reservation_remaining(rr.id) q from public.inventory_reservations rr join public.inventory_transfer_allocations a on a.id=rr.transfer_allocation_id join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id=p_transfer order by a.id for update of rr,a loop
  if r.q>0 then perform public.append_inventory_reservation_adjustment(r.reservation_id,r.allocation_id,p_transfer,cmd,'manually_released',r.q,null,null,trim(p_reason)); end if;
 end loop;
 insert into public.inventory_transfer_operations(transfer_id,command_id,operation_type,reason,created_by) values(p_transfer,cmd,'cancel',trim(p_reason),auth.uid());
 update public.inventory_commands set status='posted',posted_at=now(),payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=cmd;
 perform public.inventory_transfer_refresh_status(p_transfer); perform public.inventory_transfer_write_event(p_transfer,cmd,null,'inventory.transfer_cancelled',jsonb_build_object('reason',trim(p_reason))); return p_transfer;
end $$;

create or replace function public.close_inventory_transfer_remainder(p_transfer uuid,p_closures jsonb,p_key text,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare transfer_row public.inventory_transfers%rowtype; command_id uuid; closure_item jsonb; canonical jsonb; request_hash text; line_row public.inventory_transfer_lines%rowtype; allocation_row public.inventory_transfer_allocations%rowtype; reservation_row public.inventory_reservations%rowtype; quantity numeric; issued_qty numeric; closed_qty numeric; planned_qty numeric; line_new_qty numeric; line_new_unallocated_qty numeric; allocation_new_qty numeric; closure_id uuid; begin
 if jsonb_typeof(p_closures)<>'array' or jsonb_array_length(p_closures)=0 or coalesce(trim(p_reason),'')='' then raise exception 'Inventory transfer remainder closure denied'; end if;
 select jsonb_agg(value order by coalesce(value->>'transfer_allocation_id',''),value->>'transfer_line_id',value->>'quantity_base') into canonical from jsonb_array_elements(p_closures); request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('version',1,'action','transfer_close_remainder','transfer_id',p_transfer,'closures',canonical,'reason',trim(p_reason))::text,'utf8'),'sha256'),'hex');
 select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
 if not found then raise exception 'Inventory transfer remainder closure denied'; end if;
 if transfer_row.status in ('draft','reserved','cancelled','completed') or not exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue') then raise exception 'Inventory transfer remainder closure lifecycle denied'; end if;
 if not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.close_remainder') then raise exception 'Inventory transfer remainder closure authorization denied'; end if;
 command_id:=public.claim_inventory_transfer_command(p_transfer,'transfer_close_remainder',p_key,request_hash,jsonb_build_object('version',1,'closures',canonical),trim(p_reason));
 if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then return p_transfer; end if;
 for closure_item in select value from jsonb_array_elements(canonical) loop
  select * into line_row from public.inventory_transfer_lines l where l.id=(closure_item->>'transfer_line_id')::uuid and l.transfer_id=p_transfer for update; quantity:=(closure_item->>'quantity_base')::numeric; if not found or quantity<=0 or (closure_item->>'inventory_item_profile_id')::uuid is distinct from line_row.inventory_item_profile_id then raise exception 'Inventory transfer remainder closure denied'; end if;
  select coalesce(sum(o.quantity_base),0) into issued_qty from public.inventory_transfer_operations o join public.inventory_transfer_allocations a on a.id=o.transfer_allocation_id where a.transfer_line_id=line_row.id and o.operation_type='issue';
  select coalesce(sum(c.quantity_base),0) into closed_qty from public.inventory_transfer_remainder_closures c where c.transfer_line_id=line_row.id;
  select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into line_new_qty from jsonb_array_elements(canonical) request_item where (request_item.value->>'transfer_line_id')::uuid=line_row.id;
  if issued_qty+closed_qty+line_new_qty>line_row.requested_quantity_base then raise exception 'Inventory transfer remainder closure exceeds line requested quantity' using errcode='23514'; end if;
  if closure_item ? 'transfer_allocation_id' and nullif(closure_item->>'transfer_allocation_id','') is not null then
   select * into allocation_row from public.inventory_transfer_allocations a where a.id=(closure_item->>'transfer_allocation_id')::uuid and a.transfer_line_id=line_row.id for update; if not found then raise exception 'Inventory transfer remainder closure allocation denied'; end if;
   select coalesce(sum(o.quantity_base),0) into issued_qty from public.inventory_transfer_operations o where o.transfer_allocation_id=allocation_row.id and o.operation_type='issue';
   select coalesce(sum(c.quantity_base),0) into closed_qty from public.inventory_transfer_remainder_closures c where c.transfer_allocation_id=allocation_row.id;
   select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into allocation_new_qty from jsonb_array_elements(canonical) request_item where nullif(request_item.value->>'transfer_allocation_id','')::uuid=allocation_row.id;
   if issued_qty+closed_qty+allocation_new_qty>allocation_row.planned_quantity_base then raise exception 'Inventory transfer remainder closure exceeds allocation remaining' using errcode='23514'; end if;
   select * into reservation_row from public.inventory_reservations r where r.transfer_allocation_id=allocation_row.id for update;
   if not found or quantity>public.inventory_transfer_reservation_remaining(reservation_row.id) then raise exception 'Inventory transfer remainder closure exceeds reservation remaining' using errcode='23514'; end if;
   insert into public.inventory_transfer_remainder_closures(transfer_id,transfer_line_id,transfer_allocation_id,inventory_item_profile_id,reservation_id,quantity_base,command_id,reason,created_by) values(p_transfer,line_row.id,allocation_row.id,line_row.inventory_item_profile_id,reservation_row.id,quantity,command_id,trim(p_reason),auth.uid()) returning id into closure_id;
   perform public.append_inventory_reservation_adjustment(reservation_row.id,allocation_row.id,p_transfer,command_id,'closure_released',quantity,null,closure_id,trim(p_reason));
  else
   select coalesce(sum(a.planned_quantity_base),0) into planned_qty from public.inventory_transfer_allocations a where a.transfer_line_id=line_row.id;
   select coalesce(sum(c.quantity_base),0) into closed_qty from public.inventory_transfer_remainder_closures c where c.transfer_line_id=line_row.id and c.transfer_allocation_id is null;
   select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into line_new_unallocated_qty from jsonb_array_elements(canonical) request_item where (request_item.value->>'transfer_line_id')::uuid=line_row.id and nullif(request_item.value->>'transfer_allocation_id','') is null;
   if line_new_unallocated_qty+closed_qty>line_row.requested_quantity_base-coalesce(planned_qty,0) then raise exception 'Inventory transfer remainder closure exceeds line remaining' using errcode='23514'; end if;
   insert into public.inventory_transfer_remainder_closures(transfer_id,transfer_line_id,inventory_item_profile_id,quantity_base,command_id,reason,created_by) values(p_transfer,line_row.id,line_row.inventory_item_profile_id,quantity,command_id,trim(p_reason),auth.uid()) returning id into closure_id;
  end if;
  perform public.inventory_transfer_write_event(p_transfer,command_id,null,'inventory.transfer_remainder_closed',jsonb_build_object('closure_id',closure_id,'quantity_base',quantity));
 end loop;
 update public.inventory_commands set status='posted',posted_at=now(),payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=command_id; perform public.inventory_transfer_refresh_status(p_transfer); return p_transfer;
end $$;

alter table public.inventory_reservation_adjustments enable row level security;
create policy inventory_reservation_adjustments_read on public.inventory_reservation_adjustments for select using(public.can_view_inventory_transfer(transfer_id));
revoke all on public.inventory_reservation_adjustments from public,anon,authenticated;
grant select on public.inventory_reservation_adjustments to authenticated;
revoke all on function public.prevent_inventory_reservation_mutation(),public.enforce_inventory_reservation_adjustment_integrity(),public.enforce_inventory_reservation_adjustment_total(),public.append_inventory_reservation_adjustment(uuid,uuid,uuid,uuid,public.inventory_reservation_adjustment_type,numeric,uuid,uuid,text,jsonb),public.inventory_transfer_reservation_remaining(uuid) from public,anon,authenticated,service_role;

-- Expiry remains excluded from ATP by expires_at, but its former writer used
-- legacy reservation events that are no longer accounting truth.  Keep the
-- trusted-only signature and fail closed until a scoped automation identity
-- and adjustment-backed expiry command are introduced.
create or replace function public.expire_inventory_transfer_reservations() returns integer language plpgsql security definer set search_path=public as $$
begin
  if auth.role() not in ('service_role','postgres') then
    raise exception 'Inventory reservation expiry requires trusted execution';
  end if;
  raise exception 'Inventory reservation expiry adjustment automation is deferred' using errcode='0A000';
end $$;
