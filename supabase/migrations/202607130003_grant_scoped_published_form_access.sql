-- Scoped published-form access. This migration grants view-only access without
-- granting platform.manage_forms or weakening RLS scope checks.

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.key='platform.view_published_forms'
where r.key in ('organization_administrator','facility_administrator','scoped_user')
on conflict do nothing;

create or replace function public.enforce_published_form_current_version() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='published' then
    if new.current_version_id is null then raise exception 'Published form definition requires a current published version' using errcode='23514'; end if;
    if not exists(select 1 from public.form_versions v where v.id=new.current_version_id and v.form_id=new.id and v.status='published' and v.tenant_id=new.tenant_id and v.organization_id is not distinct from new.organization_id and v.facility_id is not distinct from new.facility_id) then raise exception 'Published form definition must reference a published version in the same scope' using errcode='23514'; end if;
  end if;
  return new;
end $$;
create trigger form_definitions_published_current_version before insert or update of status,current_version_id,tenant_id,organization_id,facility_id on public.form_definitions for each row execute function public.enforce_published_form_current_version();

revoke all on function public.enforce_published_form_current_version() from public,anon,authenticated;
