-- Security hardening migration. It is additive and safe to apply after the
-- core foundation migration; do not edit already-applied migrations.

alter table public.organizations add constraint organizations_id_tenant_unique unique(id,tenant_id);
alter table public.facilities add constraint facilities_id_tenant_organization_unique unique(id,tenant_id,organization_id);
alter table public.branches add constraint branches_id_tenant_organization_unique unique(id,tenant_id,organization_id);
alter table public.departments add constraint departments_id_tenant_organization_unique unique(id,tenant_id,organization_id);
alter table public.form_definitions add constraint form_definitions_id_scope_unique unique(id,tenant_id,organization_id,facility_id);
alter table public.form_versions add constraint form_versions_id_scope_unique unique(id,tenant_id,organization_id,facility_id);
alter table public.reference_data_groups add constraint reference_data_groups_id_scope_unique unique(id,tenant_id,organization_id,facility_id);

create unique index user_role_assignments_global_role_once on public.user_role_assignments(user_id,role_id) where tenant_id is null and organization_id is null and facility_id is null;

create or replace function public.enforce_scope_hierarchy() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.organization_id is not null and not exists(select 1 from public.organizations where id=new.organization_id and tenant_id=new.tenant_id) then raise exception 'Organization does not belong to tenant' using errcode='23503'; end if;
  if new.facility_id is not null and (new.organization_id is null or not exists(select 1 from public.facilities where id=new.facility_id and tenant_id=new.tenant_id and organization_id=new.organization_id)) then raise exception 'Facility does not belong to tenant and organization' using errcode='23503'; end if;
  return new;
end $$;
create or replace function public.enforce_form_version_scope() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.form_definitions f where f.id=new.form_id and f.tenant_id=new.tenant_id and f.organization_id is not distinct from new.organization_id and f.facility_id is not distinct from new.facility_id) then raise exception 'Form version scope does not match form definition' using errcode='23503'; end if;
  return new;
end $$;
create or replace function public.enforce_form_section_scope() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.form_versions v where v.id=new.form_version_id and v.tenant_id=new.tenant_id and v.organization_id is not distinct from new.organization_id and v.facility_id is not distinct from new.facility_id) then raise exception 'Form section scope does not match form version' using errcode='23503'; end if;
  return new;
end $$;
create or replace function public.enforce_form_field_scope() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.form_versions v where v.id=new.form_version_id and v.tenant_id=new.tenant_id and v.organization_id is not distinct from new.organization_id and v.facility_id is not distinct from new.facility_id) then raise exception 'Form field scope does not match form version' using errcode='23503'; end if;
  if new.form_section_id is not null and not exists(select 1 from public.form_sections s where s.id=new.form_section_id and s.form_version_id=new.form_version_id and s.tenant_id=new.tenant_id and s.organization_id is not distinct from new.organization_id and s.facility_id is not distinct from new.facility_id) then raise exception 'Form field section does not match form version scope' using errcode='23503'; end if;
  return new;
end $$;
create or replace function public.enforce_reference_item_scope() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.reference_data_groups g where g.id=new.group_id and g.tenant_id=new.tenant_id and g.organization_id is not distinct from new.organization_id and g.facility_id is not distinct from new.facility_id) then raise exception 'Reference item scope does not match reference group' using errcode='23503'; end if;
  return new;
end $$;

create trigger facilities_scope_hierarchy before insert or update on public.facilities for each row execute function public.enforce_scope_hierarchy();
create trigger branches_scope_hierarchy before insert or update on public.branches for each row execute function public.enforce_scope_hierarchy();
create trigger departments_scope_hierarchy before insert or update on public.departments for each row execute function public.enforce_scope_hierarchy();
create trigger form_definitions_scope_hierarchy before insert or update on public.form_definitions for each row execute function public.enforce_scope_hierarchy();
create trigger form_versions_scope_hierarchy before insert or update on public.form_versions for each row execute function public.enforce_scope_hierarchy();
create trigger form_versions_parent_scope before insert or update on public.form_versions for each row execute function public.enforce_form_version_scope();
create trigger form_sections_scope_hierarchy before insert or update on public.form_sections for each row execute function public.enforce_scope_hierarchy();
create trigger form_sections_parent_scope before insert or update on public.form_sections for each row execute function public.enforce_form_section_scope();
create trigger form_fields_scope_hierarchy before insert or update on public.form_fields for each row execute function public.enforce_scope_hierarchy();
create trigger form_fields_parent_scope before insert or update on public.form_fields for each row execute function public.enforce_form_field_scope();
create trigger reference_groups_scope_hierarchy before insert or update on public.reference_data_groups for each row execute function public.enforce_scope_hierarchy();
create trigger reference_items_scope_hierarchy before insert or update on public.reference_data_items for each row execute function public.enforce_scope_hierarchy();
create trigger reference_items_parent_scope before insert or update on public.reference_data_items for each row execute function public.enforce_reference_item_scope();
create trigger import_jobs_scope_hierarchy before insert or update on public.import_jobs for each row execute function public.enforce_scope_hierarchy();
create trigger export_jobs_scope_hierarchy before insert or update on public.export_jobs for each row execute function public.enforce_scope_hierarchy();
create trigger deletion_requests_scope_hierarchy before insert or update on public.deletion_requests for each row execute function public.enforce_scope_hierarchy();

insert into public.permissions(key,name_ar,name_en) values ('platform.view_published_forms','عرض النماذج المنشورة','View published forms') on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_id) select r.id,p.id from public.roles r join public.permissions p on p.key='platform.view_published_forms' where r.key='platform_owner' on conflict do nothing;

create or replace function public.can_view_published_forms(target_tenant uuid,target_organization uuid,target_facility uuid) returns boolean language sql stable security definer set search_path=public as $$ select auth.uid() is not null and public.scope_allowed(target_tenant,target_organization,target_facility) and (public.has_platform_permission('platform.view_published_forms',target_tenant,target_organization,target_facility) or public.has_platform_permission('platform.manage_forms',target_tenant,target_organization,target_facility) or public.has_platform_permission('platform.full_access',target_tenant,target_organization,target_facility)); $$;
drop policy forms_select on public.form_definitions;
create policy forms_select on public.form_definitions for select using(public.can_manage_forms(tenant_id,organization_id,facility_id) or (status='published' and public.can_view_published_forms(tenant_id,organization_id,facility_id)));
drop policy form_versions_select on public.form_versions;
create policy form_versions_select on public.form_versions for select using(public.can_manage_forms(tenant_id,organization_id,facility_id) or (status='published' and public.can_view_published_forms(tenant_id,organization_id,facility_id)));
drop policy form_sections_select on public.form_sections;
create policy form_sections_select on public.form_sections for select using(public.can_manage_forms(tenant_id,organization_id,facility_id) or exists(select 1 from public.form_versions v where v.id=form_version_id and v.status='published' and public.can_view_published_forms(tenant_id,organization_id,facility_id)));
drop policy form_fields_select on public.form_fields;
create policy form_fields_select on public.form_fields for select using(public.can_manage_forms(tenant_id,organization_id,facility_id) or exists(select 1 from public.form_versions v where v.id=form_version_id and v.status='published' and public.can_view_published_forms(tenant_id,organization_id,facility_id)));

create or replace function public.bootstrap_first_platform_owner(p_user_id uuid,p_tenant_id uuid) returns void language plpgsql security definer set search_path=public,auth as $$
declare owner_role_id uuid; inserted_assignment uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'Bootstrap requires service role'; end if;
  if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'Authenticated Supabase user does not exist'; end if;
  if not exists(select 1 from public.tenants where id=p_tenant_id and deleted_at is null) then raise exception 'Tenant does not exist'; end if;
  select id into owner_role_id from public.roles where key='platform_owner' and scope_level='global'; if owner_role_id is null then raise exception 'Platform Owner role is missing'; end if;
  insert into public.user_profiles(id) values(p_user_id) on conflict(id) do nothing;
  insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id,active) values(p_user_id,owner_role_id,null,null,null,true) on conflict(user_id,role_id) where tenant_id is null and organization_id is null and facility_id is null do update set active=true returning id into inserted_assignment;
  if inserted_assignment is not null and not exists(select 1 from public.audit_events where actor_id=p_user_id and action='platform_owner.bootstrap' and metadata->>'assignment_id'=inserted_assignment::text) then insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,metadata) values(p_tenant_id,p_user_id,'platform_owner.bootstrap','user_profile',p_user_id,jsonb_build_object('source','controlled_bootstrap','assignment_id',inserted_assignment)); end if;
end $$;

create or replace function public.append_trusted_audit_event(event_tenant_id uuid,event_organization_id uuid,event_facility_id uuid,event_actor_id uuid,event_action text,event_entity_type text,event_entity_id uuid,event_metadata jsonb default '{}'::jsonb) returns uuid language plpgsql security definer set search_path=public,auth as $$ declare event_id uuid; begin if auth.role() <> 'service_role' then raise exception 'Trusted audit requires service role'; end if; if event_metadata ?| array['password','token','secret','access_token'] then raise exception 'Sensitive audit metadata is prohibited'; end if; insert into public.audit_events(tenant_id,organization_id,facility_id,actor_id,action,entity_type,entity_id,metadata) values(event_tenant_id,event_organization_id,event_facility_id,event_actor_id,event_action,event_entity_type,event_entity_id,event_metadata) returning id into event_id; return event_id; end $$;

revoke all on function public.append_audit_event(uuid,uuid,uuid,text,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.append_trusted_audit_event(uuid,uuid,uuid,uuid,text,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.bootstrap_first_platform_owner(uuid,uuid) from public,anon,authenticated;
revoke all on function public.scope_allowed(uuid,uuid,uuid) from public,anon;
revoke all on function public.has_platform_permission(text,uuid,uuid,uuid) from public,anon;
revoke all on function public.can_manage_forms(uuid,uuid,uuid) from public,anon;
revoke all on function public.can_manage_reference_data(uuid,uuid,uuid) from public,anon;
revoke all on function public.can_view_published_forms(uuid,uuid,uuid) from public,anon;
revoke all on function public.enforce_scope_hierarchy() from public,anon,authenticated;
revoke all on function public.enforce_form_version_scope() from public,anon,authenticated;
revoke all on function public.enforce_form_section_scope() from public,anon,authenticated;
revoke all on function public.enforce_form_field_scope() from public,anon,authenticated;
revoke all on function public.enforce_reference_item_scope() from public,anon,authenticated;
revoke all on function public.handle_new_auth_user() from public,anon,authenticated;
revoke all on function public.set_updated_at() from public,anon,authenticated;
revoke all on function public.prevent_published_form_mutation() from public,anon,authenticated;
grant execute on function public.scope_allowed(uuid,uuid,uuid), public.has_platform_permission(text,uuid,uuid,uuid), public.can_manage_forms(uuid,uuid,uuid), public.can_manage_reference_data(uuid,uuid,uuid), public.can_view_published_forms(uuid,uuid,uuid) to authenticated;
grant execute on function public.append_trusted_audit_event(uuid,uuid,uuid,uuid,text,text,uuid,jsonb), public.bootstrap_first_platform_owner(uuid,uuid) to service_role;
