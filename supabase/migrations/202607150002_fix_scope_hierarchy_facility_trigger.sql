-- Correct a runtime trigger defect in the already-applied core hardening migration.
-- facilities owns the facility identifier and therefore has no NEW.facility_id.
create or replace function public.enforce_scope_hierarchy() returns trigger language plpgsql security definer set search_path=public as $$
declare target_facility uuid:=nullif(to_jsonb(new)->>'facility_id','')::uuid;
begin
  if new.organization_id is not null and not exists(select 1 from public.organizations where id=new.organization_id and tenant_id=new.tenant_id) then
    raise exception 'Organization does not belong to tenant' using errcode='23503';
  end if;
  if target_facility is not null and (new.organization_id is null or not exists(select 1 from public.facilities where id=target_facility and tenant_id=new.tenant_id and organization_id=new.organization_id)) then
    raise exception 'Facility does not belong to tenant and organization' using errcode='23503';
  end if;
  return new;
end $$;

revoke all on function public.enforce_scope_hierarchy() from public,anon,authenticated;
