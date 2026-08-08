\set ON_ERROR_STOP on
begin;

do $$
declare
  tenant_a uuid:='81000000-0000-0000-0000-000000000001';
  tenant_b uuid:='82000000-0000-0000-0000-000000000001';
  org_a uuid:='81000000-0000-0000-0000-000000000002';
  org_b uuid:='82000000-0000-0000-0000-000000000002';
  facility_a uuid:='81000000-0000-0000-0000-000000000003';
  facility_b uuid:='82000000-0000-0000-0000-000000000003';
  user_a uuid:='81000000-0000-0000-0000-000000000004';
  user_b uuid:='82000000-0000-0000-0000-000000000004';
  manager_role uuid:='81000000-0000-0000-0000-000000000005';
  license_a uuid:='81000000-0000-0000-0000-000000000006';
  license_b uuid:='82000000-0000-0000-0000-000000000006';
begin
  insert into public.tenants(id,key,name_en) values
    (tenant_a,'white-label-test-a','White Label Test A'),
    (tenant_b,'white-label-test-b','White Label Test B');
  insert into public.organizations(id,tenant_id,code,name_en) values
    (org_a,tenant_a,'WLA','White Label Organization A'),
    (org_b,tenant_b,'WLB','White Label Organization B');
  insert into public.facilities(id,tenant_id,organization_id,code,name_en) values
    (facility_a,tenant_a,org_a,'WLA-F','White Label Facility A'),
    (facility_b,tenant_b,org_b,'WLB-F','White Label Facility B');
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
    (user_a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','white-label-a@test.invalid','not-used',now(),'{}','{}',now(),now()),
    (user_b,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','white-label-b@test.invalid','not-used',now(),'{}','{}',now(),now());
  insert into public.memberships(user_id,tenant_id,organization_id,facility_id) values
    (user_a,tenant_a,org_a,null),(user_b,tenant_b,org_b,facility_b);
  insert into public.roles(id,key,name_ar,name_en,scope_level) values
    (manager_role,'white_label_test_manager','مدير هوية اختباري','White-label test manager','organization');
  insert into public.role_permissions(role_id,permission_id)
    select manager_role,p.id from public.permissions p where p.key='platform.manage_branding';
  insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id)
    values(user_a,manager_role,tenant_a,org_a,null);
  insert into public.commercial_licenses(id,tenant_id,organization_id,facility_id,license_model,status,starts_at,expires_at,grace_ends_at,white_label_enabled)
    values
      (license_a,tenant_a,org_a,null,'annual','active',now()-interval '1 day',now()+interval '1 year',now()+interval '1 year 14 days',true),
      (license_b,tenant_b,org_b,facility_b,'monthly','active',now()-interval '1 day',now()+interval '1 month',now()+interval '1 month 7 days',false);
  insert into public.license_entitlements(license_id,module_key) values
    (license_a,'inventory'),(license_a,'policies'),(license_b,'inspections');
  insert into public.branding_domains(tenant_id,organization_id,hostname,public_branding,verified_at)
    values(tenant_a,org_a,'customer-a.example.test',jsonb_build_object('platformNameEn','Customer A Operations','showDeveloperAttribution',false),now());
end $$;

set local role service_role;
select set_config('request.jwt.claim.role','service_role',true),set_config('request.jwt.claim.sub','',true);

do $$
declare
  first_id uuid;
  replay_id uuid;
  fixed_start timestamptz:='2026-08-01 00:00:00+00';
begin
  first_id:=public.provision_commercial_license(
    '81000000-0000-0000-0000-000000000001',null,null,
    'perpetual','draft','private_cloud',fixed_start,null,null,false,null,null,null,'billing-test-idempotent'
  );
  replay_id:=public.provision_commercial_license(
    '81000000-0000-0000-0000-000000000001',null,null,
    'perpetual','draft','private_cloud',fixed_start,null,null,false,null,null,null,'billing-test-idempotent'
  );
  if first_id<>replay_id then raise exception 'ASSERT: provisioning replay created a different license'; end if;
end $$;

reset role;

do $$
declare provisioned_id uuid;
begin
  if (select count(*) from public.commercial_licenses where external_reference='billing-test-idempotent')<>1 then
    raise exception 'ASSERT: provisioning replay created duplicate licenses';
  end if;
  select id into provisioned_id from public.commercial_licenses where external_reference='billing-test-idempotent';
  if exists(select 1 from public.license_entitlements where license_id=provisioned_id) then
    raise exception 'ASSERT: null module list did not normalize to empty';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000004',true);

do $$
declare
  tenant_a uuid:='81000000-0000-0000-0000-000000000001';
  tenant_b uuid:='82000000-0000-0000-0000-000000000001';
  org_a uuid:='81000000-0000-0000-0000-000000000002';
  org_b uuid:='82000000-0000-0000-0000-000000000002';
  facility_a uuid:='81000000-0000-0000-0000-000000000003';
  facility_b uuid:='82000000-0000-0000-0000-000000000003';
  saved record;
  effective jsonb;
begin
  begin
    perform public.provision_commercial_license(
      tenant_a,org_a,null,'annual','active','cloud',now(),now()+interval '1 year',now()+interval '1 year 7 days',
      false,array['inventory'],null,null,'unauthorized-provision-attempt'
    );
    raise exception 'ASSERT: authenticated user provisioned a commercial license';
  exception when others then
    if sqlerrm='ASSERT: authenticated user provisioned a commercial license' then raise; end if;
  end;
  if not public.has_module_entitlement('inventory',tenant_a,org_a,facility_a) then raise exception 'ASSERT: licensed inventory module denied'; end if;
  if (select count(*) from public.memberships)<>1
    or exists(select 1 from public.memberships where tenant_id=tenant_b)
  then raise exception 'ASSERT: membership SELECT grant bypassed self-only RLS'; end if;
  if public.has_module_entitlement('medication_errors',tenant_a,org_a,facility_a) then raise exception 'ASSERT: unlicensed module allowed'; end if;
  if not public.has_module_entitlement('core',tenant_a,org_a,facility_a) then raise exception 'ASSERT: scoped core denied'; end if;
  if public.has_module_entitlement('core',tenant_b,org_b,facility_b) then raise exception 'ASSERT: cross-tenant core allowed'; end if;
  if (select count(*) from public.current_module_entitlements(tenant_a,org_a,facility_a))<>2 then raise exception 'ASSERT: entitlement set is incorrect'; end if;
  if (public.current_commercial_summary(tenant_a,org_a,facility_a)->>'whiteLabelEnabled')::boolean is not true then raise exception 'ASSERT: white-label entitlement missing'; end if;
  if exists(select 1 from public.commercial_licenses) then raise exception 'ASSERT: branding manager can read commercial license tables'; end if;

  select * into saved from public.update_scoped_branding(tenant_a,org_a,null,jsonb_build_object(
    'platformNameAr','منصة العميل','platformNameEn','Customer Platform',
    'organizationNameAr','منظمة العميل','organizationNameEn','Customer Organization',
    'primaryColor','#112233','accentColor','#445566','showDeveloperAttribution',false
  ),null);
  if saved.revision<>1 then raise exception 'ASSERT: initial branding revision is incorrect'; end if;
  select * into saved from public.update_scoped_branding(tenant_a,org_a,facility_a,jsonb_build_object(
    'facilityNameAr','منشأة العميل','facilityNameEn','Customer Facility',
    'primaryColor','#abcdef','showDeveloperAttribution',false
  ),null);
  effective:=public.resolve_effective_branding(tenant_a,org_a,facility_a);
  if effective->>'platformNameEn'<>'Customer Platform' or effective->>'facilityNameEn'<>'Customer Facility' or effective->>'primaryColor'<>'#abcdef' then
    raise exception 'ASSERT: branding hierarchy did not merge correctly';
  end if;
  begin
    perform public.update_scoped_branding(tenant_a,org_a,facility_a,jsonb_build_object('platformNameEn','Conflict'),99);
    raise exception 'ASSERT: stale branding revision accepted';
  exception when others then
    if sqlerrm='ASSERT: stale branding revision accepted' or sqlerrm<>'Branding revision conflict' then raise; end if;
  end;
end $$;

reset role;
do $$ begin
  if not exists(select 1 from public.audit_events where action='branding.updated' and tenant_id='81000000-0000-0000-0000-000000000001'::uuid and actor_id='81000000-0000-0000-0000-000000000004'::uuid) then
    raise exception 'ASSERT: branding audit event missing';
  end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000004',true);

do $$
declare
  tenant_a uuid:='81000000-0000-0000-0000-000000000001';
  tenant_b uuid:='82000000-0000-0000-0000-000000000001';
  org_a uuid:='81000000-0000-0000-0000-000000000002';
  org_b uuid:='82000000-0000-0000-0000-000000000002';
  facility_a uuid:='81000000-0000-0000-0000-000000000003';
  facility_b uuid:='82000000-0000-0000-0000-000000000003';
begin
  if not public.has_module_entitlement('inspections',tenant_b,org_b,facility_b) then raise exception 'ASSERT: second tenant entitlement denied'; end if;
  if exists(select 1 from public.current_module_entitlements(tenant_a,org_a,facility_a)) then raise exception 'ASSERT: cross-tenant entitlements exposed'; end if;
  if public.resolve_effective_branding(tenant_a,org_a,facility_a)<>'{}'::jsonb then raise exception 'ASSERT: cross-tenant branding exposed'; end if;
  begin
    perform public.update_scoped_branding(tenant_b,org_b,facility_b,jsonb_build_object('platformNameEn','Denied'),null);
    raise exception 'ASSERT: unauthorized branding update accepted';
  exception when others then
    if sqlerrm='ASSERT: unauthorized branding update accepted' or sqlerrm<>'Branding update is not authorized' then raise; end if;
  end;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claim.role','anon',true),set_config('request.jwt.claim.sub','',true);

do $$
declare public_brand jsonb;
begin
  public_brand:=public.resolve_public_branding('CUSTOMER-A.EXAMPLE.TEST:443');
  if public_brand->>'platformNameEn'<>'Customer A Operations' then raise exception 'ASSERT: verified public branding was not resolved'; end if;
  if public.resolve_public_branding('unknown.example.test')<>'{}'::jsonb then raise exception 'ASSERT: unknown host exposed branding'; end if;
  if has_table_privilege('anon','public.branding_domains','SELECT') then raise exception 'ASSERT: anon can read branding domain mappings'; end if;
  if has_table_privilege('anon','public.branding_settings','SELECT') then raise exception 'ASSERT: anon can read scoped branding'; end if;
  if has_table_privilege('anon','public.memberships','SELECT') then raise exception 'ASSERT: anon can read memberships'; end if;
  if has_function_privilege('anon','public.update_scoped_branding(uuid,uuid,uuid,jsonb,integer)','EXECUTE') then raise exception 'ASSERT: anon can update branding'; end if;
end $$;

reset role;
rollback;
