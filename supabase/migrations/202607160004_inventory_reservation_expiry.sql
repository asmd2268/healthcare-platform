-- Extend the inventory command whitelist after the enum value added by the
-- preceding migration has been committed.

alter table public.inventory_commands
  drop constraint if exists inventory_commands_command_type_check;

alter table public.inventory_commands
  add constraint inventory_commands_command_type_check
  check (
    command_type in (
      'opening',
      'migration',
      'reversal',
      'batch_split',
      'batch_attribute',
      'transfer_create',
      'transfer_reserve',
      'transfer_issue',
      'transfer_receive',
      'transfer_reject',
      'transfer_return',
      'transfer_dispose_rejected',
      'transfer_cancel',
      'transfer_close_remainder',
      'transfer_reservation_expire'
    )
  );

-- Trusted, adjustment-backed inventory reservation expiry.
-- Expiry changes available-to-promise accounting only. It creates no physical
-- inventory transaction, ledger entry, or balance projection movement.

create or replace function public.inventory_actor_has_permission(
  p_actor uuid,
  p_permission text,
  p_tenant uuid,
  p_organization uuid,
  p_facility uuid
) returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select
    p_actor is not null
    and exists (
      select 1
      from public.user_profiles up
      where up.id=p_actor
    )
    and exists (
      select 1
      from public.memberships m
      where m.user_id=p_actor
        and m.active
        and m.tenant_id=p_tenant
        and (m.organization_id is null or m.organization_id=p_organization)
        and (m.facility_id is null or m.facility_id=p_facility)
    )
    and exists (
      select 1
      from public.user_role_assignments ura
      join public.roles r on r.id=ura.role_id
      join public.role_permissions rp on rp.role_id=r.id
      join public.permissions p on p.id=rp.permission_id
      where ura.user_id=p_actor
        and ura.active
        and p.key in (p_permission,'platform.full_access')
        and (ura.tenant_id is null or ura.tenant_id=p_tenant)
        and (ura.organization_id is null or ura.organization_id=p_organization)
        and (ura.facility_id is null or ura.facility_id=p_facility)
    );
$$;

create or replace function public.enforce_inventory_reservation_adjustment_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
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
  select *
    into reservation_row
    from public.inventory_reservations
    where id=new.reservation_id
    for update;

  select *
    into allocation_row
    from public.inventory_transfer_allocations
    where id=new.transfer_allocation_id;

  if not found
     or reservation_row.transfer_allocation_id<>allocation_row.id then
    raise exception
      'Inventory reservation adjustment allocation integrity denied'
      using errcode='23503';
  end if;

  select *
    into line_row
    from public.inventory_transfer_lines
    where id=allocation_row.transfer_line_id;

  select *
    into transfer_row
    from public.inventory_transfers
    where id=new.transfer_id;

  if not found or line_row.transfer_id<>transfer_row.id then
    raise exception
      'Inventory reservation adjustment transfer integrity denied'
      using errcode='23503';
  end if;

  select *
    into command_row
    from public.inventory_commands
    where id=new.command_id;

  if not found
     or (command_row.tenant_id,
         command_row.organization_id,
         command_row.facility_id)
        is distinct from
        (transfer_row.tenant_id,
         transfer_row.organization_id,
         transfer_row.facility_id)
     or command_row.requester_id<>new.created_by then
    raise exception
      'Inventory reservation adjustment command integrity denied'
      using errcode='23503';
  end if;

  if new.adjustment_type='issue_consumed' then
    select *
      into operation_row
      from public.inventory_transfer_operations
      where id=new.related_operation_id;

    if new.related_operation_id is null
       or new.related_closure_id is not null
       or not found
       or operation_row.operation_type<>'issue'
       or operation_row.transfer_id<>new.transfer_id
       or operation_row.transfer_allocation_id<>new.transfer_allocation_id
       or operation_row.command_id<>new.command_id
       or operation_row.quantity_base<>new.quantity_base
       or command_row.command_type<>'transfer_issue' then
      raise exception
        'Inventory reservation issue adjustment integrity denied'
        using errcode='23503';
    end if;

  elsif new.adjustment_type='closure_released' then
    select *
      into closure_row
      from public.inventory_transfer_remainder_closures
      where id=new.related_closure_id;

    if new.related_operation_id is not null
       or new.related_closure_id is null
       or not found
       or closure_row.transfer_id<>new.transfer_id
       or closure_row.transfer_allocation_id<>new.transfer_allocation_id
       or closure_row.reservation_id<>new.reservation_id
       or closure_row.command_id<>new.command_id
       or closure_row.quantity_base<>new.quantity_base
       or command_row.command_type<>'transfer_close_remainder' then
      raise exception
        'Inventory reservation closure adjustment integrity denied'
        using errcode='23503';
    end if;

  elsif new.adjustment_type='manually_released' then
    if new.related_operation_id is not null
       or new.related_closure_id is not null
       or command_row.command_type<>'transfer_cancel' then
      raise exception
        'Inventory reservation release adjustment integrity denied'
        using errcode='23503';
    end if;

  elsif new.adjustment_type='expiry_released' then
    if new.related_operation_id is not null
       or new.related_closure_id is not null
       or command_row.command_type<>'transfer_reservation_expire'
       or reservation_row.expires_at>now() then
      raise exception
        'Inventory reservation expiry adjustment integrity denied'
        using errcode='23503';
    end if;

  else
    raise exception
      'Inventory reservation adjustment type denied'
      using errcode='23503';
  end if;

  select coalesce(sum(quantity_base),0)
    into adjusted_total
    from public.inventory_reservation_adjustments
    where reservation_id=new.reservation_id;

  if adjusted_total+new.quantity_base>reservation_row.quantity_base then
    raise exception
      'Inventory reservation adjustment exceeds reservation quantity'
      using errcode='23514';
  end if;

  return new;
end
$$;

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
    raise exception
      'Inventory reservation expiry requires trusted execution'
      using errcode='42501';
  end if;

  if p_actor is null
     or p_limit is null
     or p_limit not between 1 and 1000 then
    raise exception
      'Inventory reservation expiry invocation is invalid'
      using errcode='22023';
  end if;

  -- Existing controlled inventory helpers use auth.uid() as the durable actor.
  -- The trusted caller supplies that actor explicitly, and this transaction-local
  -- claim makes those existing integrity checks and audit writers actor-aware.
  perform set_config('request.jwt.claim.sub',p_actor::text,true);

  for candidate in
    select
      rr.id as reservation_id,
      a.id as allocation_id,
      l.transfer_id
    from public.inventory_reservations rr
    join public.inventory_transfer_allocations a
      on a.id=rr.transfer_allocation_id
    join public.inventory_transfer_lines l
      on l.id=a.transfer_line_id
    where rr.expires_at<=now()
      and public.inventory_transfer_reservation_remaining(rr.id)>0
    order by rr.expires_at,rr.id
    limit p_limit
  loop
    -- Preserve the normal transfer lock order used by issue and cancellation:
    -- transfer, allocation, then reservation. Busy transfers are retried later.
    select *
      into transfer_row
      from public.inventory_transfers
      where id=candidate.transfer_id
      for update skip locked;

    if not found then
      continue;
    end if;

    if not public.inventory_actor_has_permission(
      p_actor,
      'inventory.transfer.reserve',
      transfer_row.tenant_id,
      transfer_row.organization_id,
      transfer_row.facility_id
    ) then
      raise exception
        'Inventory reservation expiry actor is not authorized'
        using errcode='42501';
    end if;

    select *
      into allocation_row
      from public.inventory_transfer_allocations
      where id=candidate.allocation_id
        and transfer_line_id in (
          select id
          from public.inventory_transfer_lines
          where transfer_id=transfer_row.id
        )
      for update;

    if not found then
      raise exception
        'Inventory reservation expiry allocation integrity denied'
        using errcode='23503';
    end if;

    select *
      into reservation_row
      from public.inventory_reservations
      where id=candidate.reservation_id
        and transfer_allocation_id=allocation_row.id
      for update;

    if not found or reservation_row.expires_at>now() then
      continue;
    end if;

    remaining_quantity:=
      public.inventory_transfer_reservation_remaining(reservation_row.id);

    if remaining_quantity<=0 then
      continue;
    end if;

    request_key:='reservation-expiry:'||reservation_row.id::text;
    request_hash:=encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'version',1,
            'action','transfer_reservation_expire',
            'transfer_id',transfer_row.id,
            'reservation_id',reservation_row.id,
            'expires_at',reservation_row.expires_at
          )::text,
          'utf8'
        ),
        'sha256'
      ),
      'hex'
    );

    command_id:=public.claim_inventory_transfer_command(
      transfer_row.id,
      'transfer_reservation_expire',
      request_key,
      request_hash,
      jsonb_build_object(
        'version',1,
        'transfer_id',transfer_row.id,
        'reservation_id',reservation_row.id,
        'expires_at',reservation_row.expires_at
      ),
      'reservation expiry'
    );

    if (
      select payload ? 'result_reservation_id'
      from public.inventory_commands
      where id=command_id
    ) then
      continue;
    end if;

    perform public.append_inventory_reservation_adjustment(
      reservation_row.id,
      allocation_row.id,
      transfer_row.id,
      command_id,
      'expiry_released',
      remaining_quantity,
      null,
      null,
      'reservation expiry',
      jsonb_build_object('expires_at',reservation_row.expires_at)
    );

    update public.inventory_commands
      set status='posted',
          posted_at=now(),
          payload=payload||jsonb_build_object(
            'result_transfer_id',transfer_row.id,
            'result_reservation_id',reservation_row.id,
            'expired_quantity_base',remaining_quantity
          )
      where id=command_id;

    perform public.inventory_transfer_write_event(
      transfer_row.id,
      command_id,
      null,
      'inventory.transfer_reservation_expired',
      jsonb_build_object(
        'reservation_id',reservation_row.id,
        'quantity_base',remaining_quantity,
        'expires_at',reservation_row.expires_at
      )
    );

    perform public.inventory_transfer_refresh_status(transfer_row.id);

    expired_count:=expired_count+1;
  end loop;

  return expired_count;
end
$$;

revoke all on function public.inventory_actor_has_permission(
  uuid,text,uuid,uuid,uuid
) from public,anon,authenticated,service_role;

drop function if exists public.expire_inventory_transfer_reservations();

revoke all on function public.expire_inventory_transfer_reservations(uuid,integer)
  from public,anon,authenticated;

grant execute on function public.expire_inventory_transfer_reservations(uuid,integer)
  to service_role;
