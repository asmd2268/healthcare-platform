-- Commercial packaging and white-label foundation.
--
-- This migration is additive and backward compatible. Existing deployments do
-- not become license-gated until the application enables strict enforcement.
-- License provisioning and domain verification remain trusted operator tasks;
-- authenticated customers can only read their scoped commercial state and use
-- the controlled branding update function.

do $$ begin
  create type public.commercial_license_model as enum
    ('monthly','annual','perpetual','enterprise','trial');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.commercial_license_status as enum
    ('draft','trial','active','suspended','expired','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.commercial_hosting_mode as enum
    ('cloud','on_premises','private_cloud');
exception when duplicate_object then null; end $$;

create table public.platform_modules (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  name_ar text not null,
  name_en text not null,
  description_ar text,
  description_en text,
  standalone_capable boolean not null default false,
  active boolean not null default true,
  display_order integer not null check (display_order >= 0),
  created_at timestamptz not null default now(),
  unique(display_order)
);

insert into public.platform_modules
  (key,name_ar,name_en,description_ar,description_en,standalone_capable,display_order)
values
  ('core','النواة','Core','الهوية والصلاحيات والإعدادات المشتركة.','Shared identity, authorization, and settings.',false,0),
  ('inventory','المخزون والعهدة','Inventory & Custody','المواقع والأرصدة والتحويلات والعهدة.','Locations, balances, transfers, and custody.',true,10),
  ('inspections','التفتيشات','Inspections','قوالب التفتيش والتنفيذ والنتائج.','Inspection templates, execution, and findings.',true,20),
  ('medication_errors','أخطاء الدواء','Medication Errors','بلاغات سلامة الدواء ومراجعتها.','Medication-safety reports and review.',true,30),
  ('policies','السياسات والإجراءات','Policies & Procedures','إدارة الوثائق والإصدارات والإقرارات.','Document, version, and acknowledgement management.',true,40),
  ('capa','الإجراءات التصحيحية والوقائية','CAPA','إجراءات CAPA المشتركة القابلة لإعادة الاستخدام.','Reusable corrective and preventive actions.',true,50),
  ('reporting','التقارير والتحليلات','Reporting & Analytics','التقارير واللوحات والتصدير.','Reports, dashboards, and exports.',false,60),
  ('administration','إدارة المنصة','Platform Administration','إدارة القوالب والبيانات المرجعية والإعدادات.','Templates, reference data, and platform settings.',false,70),
  ('audit','التدقيق','Audit','سجل التغييرات والأثر التدقيقي.','Change history and audit trail.',false,80)
on conflict(key) do update set
  name_ar=excluded.name_ar,
  name_en=excluded.name_en,
  description_ar=excluded.description_ar,
  description_en=excluded.description_en,
  standalone_capable=excluded.standalone_capable,
  active=true,
  display_order=excluded.display_order;

create table public.commercial_licenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  organization_id uuid references public.organizations(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  license_model public.commercial_license_model not null,
  status public.commercial_license_status not null default 'draft',
  hosting_mode public.commercial_hosting_mode not null default 'cloud',
  starts_at timestamptz not null,
  expires_at timestamptz,
  grace_ends_at timestamptz,
  white_label_enabled boolean not null default false,
  max_users integer check (max_users is null or max_users > 0),
  max_facilities integer check (max_facilities is null or max_facilities > 0),
  external_reference text check (external_reference is null or length(external_reference) <= 160),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.user_profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.user_profiles(id),
  archived_at timestamptz,
  archived_by uuid references public.user_profiles(id),
  check (facility_id is null or organization_id is not null),
  check (expires_at is null or expires_at > starts_at),
  check (grace_ends_at is null or (expires_at is not null and grace_ends_at >= expires_at)),
  check (license_model not in ('monthly','annual','trial') or expires_at is not null)
);

create table public.license_entitlements (
  license_id uuid not null references public.commercial_licenses(id) on delete cascade,
  module_key text not null references public.platform_modules(key) on delete restrict,
  enabled boolean not null default true,
  limits jsonb not null default '{}'::jsonb check (jsonb_typeof(limits)='object'),
  created_at timestamptz not null default now(),
  created_by uuid references public.user_profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.user_profiles(id),
  primary key(license_id,module_key)
);

create table public.branding_domains (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  facility_id uuid references public.facilities(id) on delete cascade,
  hostname text not null,
  public_branding jsonb not null default '{}'::jsonb,
  verified_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.user_profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.user_profiles(id),
  check (hostname=lower(hostname)),
  check (hostname ~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$'),
  check (facility_id is null or organization_id is not null),
  unique(hostname)
);

create unique index branding_settings_tenant_once
  on public.branding_settings(tenant_id)
  where organization_id is null and facility_id is null;
create unique index branding_settings_organization_once
  on public.branding_settings(tenant_id,organization_id)
  where organization_id is not null and facility_id is null;
create unique index branding_settings_facility_once
  on public.branding_settings(tenant_id,organization_id,facility_id)
  where facility_id is not null;

alter table public.branding_settings
  add constraint branding_settings_facility_requires_organization
  check (facility_id is null or organization_id is not null);

create index commercial_licenses_scope_status_idx
  on public.commercial_licenses(tenant_id,organization_id,facility_id,status,starts_at,expires_at)
  where archived_at is null;
create index license_entitlements_enabled_idx
  on public.license_entitlements(module_key,license_id)
  where enabled;
create unique index commercial_licenses_external_reference_once
  on public.commercial_licenses(external_reference)
  where external_reference is not null;

create or replace function public.validate_branding_payload(payload jsonb)
returns boolean
language plpgsql
immutable
set search_path=public
as $$
declare
  allowed_keys constant text[]:=array[
    'platformNameAr','platformNameEn','organizationNameAr','organizationNameEn',
    'facilityNameAr','facilityNameEn','branchNameAr','branchNameEn',
    'logoUrl','faviconUrl','primaryColor','accentColor','contactEmail',
    'reportHeaderAr','reportHeaderEn','reportFooterAr','reportFooterEn',
    'emailSenderNameAr','emailSenderNameEn','showDeveloperAttribution'
  ];
  item record;
begin
  if payload is null or jsonb_typeof(payload)<>'object' then return false; end if;
  if exists(select 1 from jsonb_object_keys(payload) key where not (key=any(allowed_keys))) then return false; end if;
  for item in select key,value from jsonb_each(payload) loop
    if item.key='showDeveloperAttribution' then
      if jsonb_typeof(item.value)<>'boolean' then return false; end if;
    elsif item.key in ('primaryColor','accentColor') then
      if jsonb_typeof(item.value)<>'string' or trim(both '"' from item.value::text) !~ '^#[0-9A-Fa-f]{6}$' then return false; end if;
    elsif item.key in ('logoUrl','faviconUrl') then
      if jsonb_typeof(item.value)<>'string' or trim(both '"' from item.value::text) !~ '^https://[^[:space:]]{1,500}$' then return false; end if;
    elsif item.key='contactEmail' then
      if jsonb_typeof(item.value)<>'string' or length(trim(both '"' from item.value::text))>254 or trim(both '"' from item.value::text) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then return false; end if;
    elsif jsonb_typeof(item.value)<>'string' or length(trim(both '"' from item.value::text))>500 then
      return false;
    end if;
  end loop;
  return true;
end $$;

alter table public.branding_settings
  add constraint branding_settings_payload_valid
  check (public.validate_branding_payload(settings));
alter table public.branding_domains
  add constraint branding_domains_payload_valid
  check (public.validate_branding_payload(public_branding));

create or replace function public.validate_commercial_scope()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.organization_id is not null and not exists(
    select 1 from public.organizations o where o.id=new.organization_id and o.tenant_id=new.tenant_id and o.deleted_at is null
  ) then raise exception 'Commercial organization scope is invalid'; end if;
  if new.facility_id is not null and not exists(
    select 1 from public.facilities f where f.id=new.facility_id and f.tenant_id=new.tenant_id and f.organization_id=new.organization_id and f.deleted_at is null
  ) then raise exception 'Commercial facility scope is invalid'; end if;
  return new;
end $$;

create trigger commercial_licenses_scope_guard
before insert or update of tenant_id,organization_id,facility_id
on public.commercial_licenses for each row execute function public.validate_commercial_scope();
create trigger branding_domains_scope_guard
before insert or update of tenant_id,organization_id,facility_id
on public.branding_domains for each row execute function public.validate_commercial_scope();
create trigger commercial_licenses_updated_at
before update on public.commercial_licenses for each row execute function public.set_updated_at();
create trigger license_entitlements_updated_at
before update on public.license_entitlements for each row execute function public.set_updated_at();
create trigger branding_domains_updated_at
before update on public.branding_domains for each row execute function public.set_updated_at();

create or replace function public.active_commercial_license(
  target_tenant uuid,target_organization uuid,target_facility uuid
) returns public.commercial_licenses
language sql
stable
security definer
set search_path=public
as $$
  select l
  from public.commercial_licenses l
  where auth.uid() is not null
    and public.scope_allowed(target_tenant,target_organization,target_facility)
    and l.tenant_id=target_tenant
    and (l.organization_id is null or l.organization_id=target_organization)
    and (l.facility_id is null or l.facility_id=target_facility)
    and l.archived_at is null
    and l.status in ('active','trial')
    and l.starts_at<=now()
    and (l.expires_at is null or now()<=coalesce(l.grace_ends_at,l.expires_at))
  order by (l.facility_id is not null) desc,(l.organization_id is not null) desc,l.created_at desc
  limit 1
$$;

create or replace function public.current_module_entitlements(
  target_tenant uuid,target_organization uuid,target_facility uuid
) returns table(module_key text)
language sql
stable
security definer
set search_path=public
as $$
  select e.module_key
  from public.active_commercial_license(target_tenant,target_organization,target_facility) l
  join public.license_entitlements e on e.license_id=l.id and e.enabled
  join public.platform_modules m on m.key=e.module_key and m.active
  order by m.display_order
$$;

create or replace function public.has_module_entitlement(
  requested_module text,target_tenant uuid,target_organization uuid,target_facility uuid
) returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select auth.uid() is not null
    and public.scope_allowed(target_tenant,target_organization,target_facility)
    and (
      requested_module='core' or exists(
        select 1 from public.current_module_entitlements(target_tenant,target_organization,target_facility) e
        where e.module_key=requested_module
      )
    )
$$;

create or replace function public.has_white_label_entitlement(
  target_tenant uuid,target_organization uuid,target_facility uuid
) returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce((select l.white_label_enabled from public.active_commercial_license(target_tenant,target_organization,target_facility) l),false)
$$;

create or replace function public.current_commercial_summary(
  target_tenant uuid,target_organization uuid,target_facility uuid
) returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when l.id is null then null else jsonb_build_object(
    'licenseModel',l.license_model,
    'status',l.status,
    'hostingMode',l.hosting_mode,
    'startsAt',l.starts_at,
    'expiresAt',l.expires_at,
    'graceEndsAt',l.grace_ends_at,
    'whiteLabelEnabled',l.white_label_enabled,
    'maxUsers',l.max_users,
    'maxFacilities',l.max_facilities,
    'modules',coalesce((select jsonb_agg(e.module_key order by m.display_order) from public.license_entitlements e join public.platform_modules m on m.key=e.module_key where e.license_id=l.id and e.enabled and m.active),'[]'::jsonb)
  ) end
  from (select 1) seed
  left join lateral public.active_commercial_license(target_tenant,target_organization,target_facility) l on true
$$;

create or replace function public.resolve_effective_branding(
  target_tenant uuid,target_organization uuid,target_facility uuid
) returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case
    when auth.uid() is null or not public.scope_allowed(target_tenant,target_organization,target_facility) then '{}'::jsonb
    else
      coalesce((select b.settings from public.branding_settings b where b.tenant_id=target_tenant and b.organization_id is null and b.facility_id is null),'{}'::jsonb)
      || coalesce((select b.settings from public.branding_settings b where b.tenant_id=target_tenant and b.organization_id=target_organization and b.facility_id is null),'{}'::jsonb)
      || coalesce((select b.settings from public.branding_settings b where b.tenant_id=target_tenant and b.organization_id=target_organization and b.facility_id=target_facility),'{}'::jsonb)
  end
$$;

create or replace function public.resolve_public_branding(request_hostname text)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select coalesce((
    select d.public_branding
    from public.branding_domains d
    where d.hostname=lower(split_part(trim(request_hostname),':',1))
      and d.active and d.verified_at is not null
    limit 1
  ),'{}'::jsonb)
$$;

create or replace function public.update_scoped_branding(
  target_tenant uuid,target_organization uuid,target_facility uuid,
  branding_payload jsonb,expected_revision integer default null
) returns table(id uuid,revision integer,settings jsonb)
language plpgsql
security definer
set search_path=public
as $$
declare
  existing public.branding_settings;
  saved public.branding_settings;
  normalized jsonb:=jsonb_strip_nulls(branding_payload);
begin
  if auth.uid() is null
    or not public.scope_allowed(target_tenant,target_organization,target_facility)
    or not (
      public.has_platform_permission('platform.manage_branding',target_tenant,target_organization,target_facility)
      or public.has_platform_permission('platform.full_access',target_tenant,target_organization,target_facility)
    ) then raise exception 'Branding update is not authorized'; end if;
  if target_facility is not null and target_organization is null then raise exception 'Branding scope is invalid'; end if;
  if not public.validate_branding_payload(normalized) then raise exception 'Branding payload is invalid'; end if;
  if coalesce((normalized->>'showDeveloperAttribution')::boolean,true)=false
    and not public.has_white_label_entitlement(target_tenant,target_organization,target_facility)
  then raise exception 'White-label entitlement is required'; end if;

  select b.* into existing from public.branding_settings b
  where b.tenant_id=target_tenant
    and b.organization_id is not distinct from target_organization
    and b.facility_id is not distinct from target_facility
  for update;

  if found then
    if expected_revision is null or existing.revision<>expected_revision then raise exception 'Branding revision conflict'; end if;
    update public.branding_settings b set
      settings=normalized,revision=b.revision+1,updated_at=now(),updated_by=auth.uid()
    where b.id=existing.id returning b.* into saved;
  else
    if expected_revision is not null then raise exception 'Branding revision conflict'; end if;
    insert into public.branding_settings(tenant_id,organization_id,facility_id,settings,created_by,updated_by)
    values(target_tenant,target_organization,target_facility,normalized,auth.uid(),auth.uid()) returning * into saved;
  end if;

  insert into public.audit_events(tenant_id,organization_id,facility_id,actor_id,action,entity_type,entity_id,metadata)
  values(target_tenant,target_organization,target_facility,auth.uid(),'branding.updated','branding_settings',saved.id,jsonb_build_object('revision',saved.revision));
  return query select saved.id,saved.revision,saved.settings;
end $$;

create or replace function public.provision_commercial_license(
  target_tenant uuid,target_organization uuid,target_facility uuid,
  requested_model public.commercial_license_model,
  requested_status public.commercial_license_status,
  requested_hosting public.commercial_hosting_mode,
  requested_starts_at timestamptz,requested_expires_at timestamptz,requested_grace_ends_at timestamptz,
  requested_white_label boolean,requested_modules text[],requested_max_users integer default null,
  requested_max_facilities integer default null,requested_external_reference text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  new_license_id uuid;
  normalized_modules text[];
  existing_modules text[];
  existing_license public.commercial_licenses;
  normalized_reference text:=nullif(trim(requested_external_reference),'');
begin
  if auth.role()<>'service_role' then raise exception 'Trusted license provisioning requires service role'; end if;
  select coalesce(array_agg(distinct module_key order by module_key),'{}'::text[]) into normalized_modules from unnest(coalesce(requested_modules,'{}'::text[])) module_key where module_key<>'core';
  if exists(select 1 from unnest(normalized_modules) module_key where not exists(select 1 from public.platform_modules m where m.key=module_key and m.active)) then raise exception 'Unknown module entitlement'; end if;
  if requested_status not in ('draft','trial','active') then raise exception 'New license status is invalid'; end if;

  if normalized_reference is not null then
    select l.* into existing_license
    from public.commercial_licenses l
    where l.external_reference=normalized_reference
    for update;
    if found then
      select coalesce(array_agg(e.module_key order by e.module_key),'{}'::text[])
      into existing_modules
      from public.license_entitlements e
      where e.license_id=existing_license.id and e.enabled;
      if existing_license.tenant_id=target_tenant
        and existing_license.organization_id is not distinct from target_organization
        and existing_license.facility_id is not distinct from target_facility
        and existing_license.license_model=requested_model
        and existing_license.status=requested_status
        and existing_license.hosting_mode=requested_hosting
        and existing_license.starts_at=requested_starts_at
        and existing_license.expires_at is not distinct from requested_expires_at
        and existing_license.grace_ends_at is not distinct from requested_grace_ends_at
        and existing_license.white_label_enabled=requested_white_label
        and existing_license.max_users is not distinct from requested_max_users
        and existing_license.max_facilities is not distinct from requested_max_facilities
        and existing_modules=normalized_modules
      then return existing_license.id;
      end if;
      raise exception 'External license reference conflict';
    end if;
  end if;

  insert into public.commercial_licenses(
    tenant_id,organization_id,facility_id,license_model,status,hosting_mode,starts_at,expires_at,grace_ends_at,
    white_label_enabled,max_users,max_facilities,external_reference
  ) values(
    target_tenant,target_organization,target_facility,requested_model,requested_status,requested_hosting,requested_starts_at,
    requested_expires_at,requested_grace_ends_at,requested_white_label,requested_max_users,requested_max_facilities,normalized_reference
  ) returning id into new_license_id;
  insert into public.license_entitlements(license_id,module_key)
    select new_license_id,module_key from unnest(normalized_modules) module_key;
  insert into public.audit_events(tenant_id,organization_id,facility_id,action,entity_type,entity_id,metadata)
    values(target_tenant,target_organization,target_facility,'license.provisioned','commercial_license',new_license_id,
      jsonb_build_object('model',requested_model,'status',requested_status,'hostingMode',requested_hosting,'whiteLabel',requested_white_label,'modules',normalized_modules));
  return new_license_id;
end $$;

create or replace function public.transition_commercial_license(
  target_license uuid,requested_status public.commercial_license_status,
  requested_expires_at timestamptz,requested_grace_ends_at timestamptz,expected_revision integer
) returns integer
language plpgsql
security definer
set search_path=public
as $$
declare existing public.commercial_licenses;next_revision integer;
begin
  if auth.role()<>'service_role' then raise exception 'Trusted license transition requires service role'; end if;
  select * into existing from public.commercial_licenses where id=target_license and archived_at is null for update;
  if not found then raise exception 'Commercial license not found'; end if;
  if existing.revision<>expected_revision then raise exception 'Commercial license revision conflict'; end if;
  if requested_status not in ('active','suspended','expired','cancelled') then raise exception 'Commercial license transition is invalid'; end if;
  update public.commercial_licenses set status=requested_status,expires_at=requested_expires_at,grace_ends_at=requested_grace_ends_at,
    revision=revision+1,updated_at=now() where id=target_license returning revision into next_revision;
  insert into public.audit_events(tenant_id,organization_id,facility_id,action,entity_type,entity_id,metadata)
    values(existing.tenant_id,existing.organization_id,existing.facility_id,'license.status_changed','commercial_license',existing.id,
      jsonb_build_object('previousStatus',existing.status,'status',requested_status,'revision',next_revision));
  return next_revision;
end $$;

alter table public.platform_modules enable row level security;
alter table public.commercial_licenses enable row level security;
alter table public.license_entitlements enable row level security;
alter table public.branding_domains enable row level security;

create policy platform_modules_authenticated_read on public.platform_modules
for select to authenticated using(active);
create policy commercial_licenses_manager_read on public.commercial_licenses
for select to authenticated using(
  public.scope_allowed(tenant_id,organization_id,facility_id)
  and (
    public.has_platform_permission('platform.manage_licensing',tenant_id,organization_id,facility_id)
    or public.has_platform_permission('platform.full_access',tenant_id,organization_id,facility_id)
  )
);
create policy license_entitlements_manager_read on public.license_entitlements
for select to authenticated using(exists(
  select 1 from public.commercial_licenses l
  where l.id=license_id
    and public.scope_allowed(l.tenant_id,l.organization_id,l.facility_id)
    and (
      public.has_platform_permission('platform.manage_licensing',l.tenant_id,l.organization_id,l.facility_id)
      or public.has_platform_permission('platform.full_access',l.tenant_id,l.organization_id,l.facility_id)
    )
));

revoke all on table public.platform_modules,public.commercial_licenses,public.license_entitlements,public.branding_domains from anon;
revoke insert,update,delete,truncate,references,trigger on table public.platform_modules,public.commercial_licenses,public.license_entitlements,public.branding_domains from authenticated;
grant select on table public.platform_modules,public.commercial_licenses,public.license_entitlements to authenticated;
grant select on table public.memberships to authenticated;
revoke all on table public.branding_settings from anon;
revoke insert,update,delete,truncate,references,trigger on table public.branding_settings from authenticated;
grant select on table public.branding_settings to authenticated;

revoke all on function public.active_commercial_license(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.current_module_entitlements(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.has_module_entitlement(text,uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.has_white_label_entitlement(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.current_commercial_summary(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.resolve_effective_branding(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.resolve_public_branding(text) from public,anon,authenticated;
revoke all on function public.update_scoped_branding(uuid,uuid,uuid,jsonb,integer) from public,anon,authenticated;
revoke all on function public.provision_commercial_license(uuid,uuid,uuid,public.commercial_license_model,public.commercial_license_status,public.commercial_hosting_mode,timestamptz,timestamptz,timestamptz,boolean,text[],integer,integer,text) from public,anon,authenticated;
revoke all on function public.transition_commercial_license(uuid,public.commercial_license_status,timestamptz,timestamptz,integer) from public,anon,authenticated;

grant execute on function public.current_module_entitlements(uuid,uuid,uuid) to authenticated;
grant execute on function public.has_module_entitlement(text,uuid,uuid,uuid) to authenticated;
grant execute on function public.has_white_label_entitlement(uuid,uuid,uuid) to authenticated;
grant execute on function public.current_commercial_summary(uuid,uuid,uuid) to authenticated;
grant execute on function public.resolve_effective_branding(uuid,uuid,uuid) to authenticated;
grant execute on function public.resolve_public_branding(text) to anon,authenticated;
grant execute on function public.update_scoped_branding(uuid,uuid,uuid,jsonb,integer) to authenticated;
grant execute on function public.provision_commercial_license(uuid,uuid,uuid,public.commercial_license_model,public.commercial_license_status,public.commercial_hosting_mode,timestamptz,timestamptz,timestamptz,boolean,text[],integer,integer,text) to service_role;
grant execute on function public.transition_commercial_license(uuid,public.commercial_license_status,timestamptz,timestamptz,integer) to service_role;
