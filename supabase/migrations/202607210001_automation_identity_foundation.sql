-- Automation identities are profile-backed, non-interactive operational
-- principals. They deliberately reuse existing actor foreign keys instead of
-- introducing a parallel audit identity model. Auth-user provisioning and
-- disabling interactive sign-in remain an external service-role responsibility.

create table public.automation_identities (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references public.user_profiles(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  organization_id uuid references public.organizations(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  purpose text not null check (purpose='inventory.reservation_expiry'),
  display_name text not null check (coalesce(trim(display_name),'')<>''),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  deactivated_at timestamptz,
  deactivated_by uuid references public.user_profiles(id) on delete restrict,
  deactivation_reason text,
  check (
    (active and deactivated_at is null and deactivated_by is null and deactivation_reason is null)
    or
    (not active and deactivated_at is not null and deactivated_by is not null
      and coalesce(trim(deactivation_reason),'')<>'')
  ),
  check (facility_id is null or organization_id is not null),
  check (principal_id<>created_by)
);

-- One active principal/purpose binding per tenant keeps scope resolution
-- unambiguous. Rotate by registering a new principal and deactivating the old.
create unique index automation_identities_active_principal_purpose_tenant_uidx
  on public.automation_identities(principal_id,purpose,tenant_id)
  where active;

create index automation_identities_active_scope_idx
  on public.automation_identities(purpose,tenant_id,organization_id,facility_id,principal_id)
  where active;

create or replace function public.enforce_automation_identity_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  principal_profile public.user_profiles%rowtype;
begin
  if tg_op='DELETE' then
    raise exception 'Automation identity records cannot be deleted' using errcode='42501';
  end if;

  if tg_op='UPDATE' then
    if old.active is false
       or new.principal_id is distinct from old.principal_id
       or new.tenant_id is distinct from old.tenant_id
       or new.organization_id is distinct from old.organization_id
       or new.facility_id is distinct from old.facility_id
       or new.purpose is distinct from old.purpose
       or new.display_name is distinct from old.display_name
       or new.created_at is distinct from old.created_at
       or new.created_by is distinct from old.created_by
       or new.active is not false
       or current_setting('app.automation_identity_lifecycle',true)<>'deactivate' then
      raise exception 'Automation identity records are immutable' using errcode='42501';
    end if;
  end if;

  -- Serialize registration against membership/role assignment for this
  -- principal. Both sides lock the same profile row before checking the other
  -- relation, so an automation identity can never be committed concurrently
  -- with new interactive access.
  select * into principal_profile
  from public.user_profiles
  where id=new.principal_id
  for update;

  if not found
     or exists(
       select 1 from public.memberships m
       where m.user_id=new.principal_id and m.active
     )
     or exists(
       select 1 from public.user_role_assignments ura
       where ura.user_id=new.principal_id and ura.active
     ) then
    raise exception 'Automation identity principal is not eligible' using errcode='23514';
  end if;

  if not exists(
    select 1 from public.organizations o
    where o.id=new.organization_id and o.tenant_id=new.tenant_id
  ) and new.organization_id is not null then
    raise exception 'Automation identity organization scope denied' using errcode='23503';
  end if;

  if new.facility_id is not null and not exists(
    select 1 from public.facilities f
    where f.id=new.facility_id
      and f.tenant_id=new.tenant_id
      and f.organization_id=new.organization_id
  ) then
    raise exception 'Automation identity facility scope denied' using errcode='23503';
  end if;

  if new.purpose<>'inventory.reservation_expiry'
     or coalesce(trim(new.display_name),'')=''
     or new.principal_id=new.created_by then
    raise exception 'Automation identity invocation is invalid' using errcode='22023';
  end if;

  return new;
end;
$$;

create trigger automation_identities_integrity
before insert or update or delete on public.automation_identities
for each row execute function public.enforce_automation_identity_integrity();

-- An active automation principal must not later receive ordinary interactive
-- membership or role access. Deactivation is required before that transition.
create or replace function public.prevent_active_automation_principal_access()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  candidate_principal uuid;
  candidate_active boolean;
begin
  candidate_principal:=new.user_id;
  candidate_active:=new.active;
  -- Match the registration trigger's parent-row lock. This makes the
  -- non-interactive invariant safe under concurrent registration and access
  -- assignment, rather than relying on visibility of uncommitted rows.
  perform 1
  from public.user_profiles up
  where up.id=candidate_principal
  for update;
  if candidate_active and exists(
    select 1 from public.automation_identities ai
    where ai.principal_id=candidate_principal and ai.active
  ) then
    raise exception 'Automation identity principal cannot receive interactive access'
      using errcode='23514';
  end if;
  return new;
end;
$$;

create trigger memberships_prevent_active_automation_principal_access
before insert or update of user_id,active on public.memberships
for each row execute function public.prevent_active_automation_principal_access();

create trigger ura_prevent_active_automation_access
before insert or update of user_id,active on public.user_role_assignments
for each row execute function public.prevent_active_automation_principal_access();

create or replace function public.require_automation_identity(
  p_principal uuid,
  p_purpose text,
  p_tenant uuid,
  p_organization uuid,
  p_facility uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  identity_row public.automation_identities%rowtype;
  has_active_purpose boolean;
  has_inactive_purpose boolean;
begin
  if auth.role()<>'service_role' then
    raise exception 'Automation identity resolution requires trusted execution'
      using errcode='42501';
  end if;

  if p_principal is null
     or coalesce(trim(p_purpose),'')=''
     or (p_tenant is null and (p_organization is not null or p_facility is not null))
     or (p_tenant is not null and p_facility is not null and p_organization is null) then
    raise exception 'Automation identity invocation is invalid' using errcode='22023';
  end if;

  if p_purpose<>'inventory.reservation_expiry' then
    raise exception 'Automation identity purpose is invalid' using errcode='22023';
  end if;

  select * into identity_row
  from public.automation_identities ai
  where ai.principal_id=p_principal
    and ai.purpose=p_purpose
    and ai.active
    and (
      p_tenant is null
      or (
        ai.tenant_id=p_tenant
        and (ai.organization_id is null or ai.organization_id=p_organization)
        and (ai.facility_id is null or ai.facility_id=p_facility)
      )
    )
  order by ai.created_at desc,ai.id desc
  limit 1
  -- Deactivation changes a non-key lifecycle field, so KEY SHARE would not
  -- conflict with its NO KEY UPDATE lock. SHARE keeps a validated identity
  -- active through the caller's transaction and serializes expiry/deactivation.
  for share;

  if found then
    return identity_row.principal_id;
  end if;

  select exists(
    select 1 from public.automation_identities ai
    where ai.principal_id=p_principal
      and ai.purpose=p_purpose
      and ai.active
  ) into has_active_purpose;

  select exists(
    select 1 from public.automation_identities ai
    where ai.principal_id=p_principal
      and ai.purpose=p_purpose
      and not ai.active
  ) into has_inactive_purpose;

  if has_active_purpose then
    raise exception 'Automation identity scope is not authorized' using errcode='42501';
  elsif has_inactive_purpose then
    raise exception 'Automation identity is inactive' using errcode='42501';
  end if;

  raise exception 'Automation identity is not registered for purpose' using errcode='42501';
end;
$$;

create or replace function public.register_automation_identity(
  p_principal uuid,
  p_tenant uuid,
  p_organization uuid,
  p_facility uuid,
  p_purpose text,
  p_display_name text,
  p_administrator uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  identity_id uuid;
begin
  if auth.role()<>'service_role' then
    raise exception 'Automation identity registration requires trusted execution'
      using errcode='42501';
  end if;

  if p_principal is null
     or p_tenant is null
     or p_administrator is null
     or p_principal=p_administrator
     or p_purpose<>'inventory.reservation_expiry'
     or coalesce(trim(p_display_name),'')=''
     or (p_facility is not null and p_organization is null)
     or not public.inventory_actor_has_permission(
       p_administrator,'platform.manage_roles',p_tenant,p_organization,p_facility
     ) then
    raise exception 'Automation identity registration denied' using errcode='42501';
  end if;

  insert into public.automation_identities(
    principal_id,tenant_id,organization_id,facility_id,purpose,display_name,created_by
  ) values (
    p_principal,p_tenant,p_organization,p_facility,p_purpose,trim(p_display_name),p_administrator
  ) returning id into identity_id;

  perform public.append_trusted_audit_event(
    p_tenant,p_organization,p_facility,p_administrator,
    'automation_identity.registered','automation_identity',identity_id,
    jsonb_build_object('principal_id',p_principal,'purpose',p_purpose)
  );

  return identity_id;
end;
$$;

create or replace function public.deactivate_automation_identity(
  p_identity uuid,
  p_administrator uuid,
  p_reason text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  identity_row public.automation_identities%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'Automation identity deactivation requires trusted execution'
      using errcode='42501';
  end if;

  select * into identity_row
  from public.automation_identities
  where id=p_identity
  for update;

  if not found
     or not identity_row.active
     or p_administrator is null
     or coalesce(trim(p_reason),'')=''
     or not public.inventory_actor_has_permission(
       p_administrator,'platform.manage_roles',identity_row.tenant_id,
       identity_row.organization_id,identity_row.facility_id
     ) then
    raise exception 'Automation identity deactivation denied' using errcode='42501';
  end if;

  perform set_config('app.automation_identity_lifecycle','deactivate',true);
  update public.automation_identities
  set active=false,
      deactivated_at=now(),
      deactivated_by=p_administrator,
      deactivation_reason=trim(p_reason)
  where id=identity_row.id;

  perform public.append_trusted_audit_event(
    identity_row.tenant_id,identity_row.organization_id,identity_row.facility_id,
    p_administrator,'automation_identity.deactivated','automation_identity',identity_row.id,
    jsonb_build_object('principal_id',identity_row.principal_id,'purpose',identity_row.purpose,
      'reason',trim(p_reason))
  );
end;
$$;

-- Strict cutover: p_actor remains for RPC compatibility, but it is now an
-- approved automation principal rather than a caller-selectable human actor.
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

  perform public.require_automation_identity(
    p_actor,'inventory.reservation_expiry',null,null,null
  );
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

    perform public.require_automation_identity(
      p_actor,'inventory.reservation_expiry',transfer_row.tenant_id,
      transfer_row.organization_id,transfer_row.facility_id
    );

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

alter table public.automation_identities enable row level security;

revoke all on public.automation_identities from public,anon,authenticated;

revoke all on function public.enforce_automation_identity_integrity(),
  public.prevent_active_automation_principal_access(),
  public.require_automation_identity(uuid,text,uuid,uuid,uuid),
  public.register_automation_identity(uuid,uuid,uuid,uuid,text,text,uuid),
  public.deactivate_automation_identity(uuid,uuid,text)
  from public,anon,authenticated;

grant execute on function public.require_automation_identity(uuid,text,uuid,uuid,uuid),
  public.register_automation_identity(uuid,uuid,uuid,uuid,text,text,uuid),
  public.deactivate_automation_identity(uuid,uuid,text)
  to service_role;

revoke all on function public.expire_inventory_transfer_reservations(uuid,integer)
  from public,anon,authenticated;
grant execute on function public.expire_inventory_transfer_reservations(uuid,integer)
  to service_role;

comment on table public.automation_identities is
  'Profile-backed non-interactive automation principals. Provision their Auth users outside migrations; rotate through deactivation and a new registry row.';
comment on function public.expire_inventory_transfer_reservations(uuid,integer) is
  'Strict-cutover service-role worker: p_actor must be an active inventory.reservation_expiry automation principal in each transfer scope.';
