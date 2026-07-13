-- Run with `supabase db reset` against a disposable local database after both
-- migrations. This script never targets production. It uses only fictional IDs.
begin;

do $$
declare tenant_a uuid:=gen_random_uuid(); tenant_b uuid:=gen_random_uuid(); org_a uuid:=gen_random_uuid(); org_b uuid:=gen_random_uuid(); facility_a uuid:=gen_random_uuid(); facility_b uuid:=gen_random_uuid(); form_a uuid:=gen_random_uuid();
begin
  insert into public.tenants(id,key,name_en) values(tenant_a,'sql-a-'||substring(tenant_a::text,1,8),'SQL Tenant A'),(tenant_b,'sql-b-'||substring(tenant_b::text,1,8),'SQL Tenant B');
  insert into public.organizations(id,tenant_id,name_en,code) values(org_a,tenant_a,'SQL Org A','A'),(org_b,tenant_b,'SQL Org B','B');
  insert into public.facilities(id,tenant_id,organization_id,name_en,code) values(facility_a,tenant_a,org_a,'SQL Facility A','A'),(facility_b,tenant_b,org_b,'SQL Facility B','B');
  begin insert into public.facilities(tenant_id,organization_id,name_en,code) values(tenant_b,org_a,'Rejected cross tenant facility','X'); raise exception 'Expected cross-tenant organization rejection'; exception when foreign_key_violation then null; end;
  insert into public.form_definitions(id,tenant_id,organization_id,facility_id,module_key,name_en,status) values(form_a,tenant_a,org_a,facility_a,'platform','SQL Form','draft');
  begin insert into public.form_versions(form_id,tenant_id,organization_id,facility_id,version_number,status) values(form_a,tenant_b,org_b,facility_b,1,'draft'); raise exception 'Expected cross-tenant form hierarchy rejection'; exception when foreign_key_violation then null; end;
end $$;

-- Configure a real fictional local Auth user UUID before executing this block:
-- select set_config('test.bootstrap_user_id','<local-auth-user-uuid>',false);
-- select set_config('test.bootstrap_tenant_id','<local-tenant-uuid>',false);
-- The bootstrap function must be invoked through a service-role local session.
-- select public.bootstrap_first_platform_owner(current_setting('test.bootstrap_user_id')::uuid,current_setting('test.bootstrap_tenant_id')::uuid);
-- select public.bootstrap_first_platform_owner(current_setting('test.bootstrap_user_id')::uuid,current_setting('test.bootstrap_tenant_id')::uuid);
-- select count(*) = 1 as exactly_one_global_owner_assignment from public.user_role_assignments ura join public.roles r on r.id=ura.role_id where ura.user_id=current_setting('test.bootstrap_user_id')::uuid and r.key='platform_owner' and ura.tenant_id is null and ura.organization_id is null and ura.facility_id is null;

-- Anonymous and authenticated users must receive permission denied for trusted
-- audit writes. Run each under the corresponding local JWT role:
-- select public.append_trusted_audit_event(gen_random_uuid(),null,null,null,'form.created','form',null,'{}'::jsonb);
-- Expected: permission denied (and never an inserted event).

-- With two fictional authenticated users and scoped assignments, verify:
-- 1) anonymous access returns no protected rows;
-- 2) a user scoped to organization A cannot read organization B;
-- 3) a facility-scoped user cannot read another facility;
-- 4) platform.view_published_forms can read published forms only;
-- 5) that same user cannot read draft forms or mutate any form.
rollback;
