-- Align trusted inventory authorization with the platform-wide global-owner
-- contract. Global platform owners are intentionally membership-free, while
-- every other actor remains membership- and scope-bound.

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
    and (
      exists (
        select 1
        from public.user_role_assignments global_assignment
        join public.roles global_role on global_role.id=global_assignment.role_id
        where global_assignment.user_id=p_actor
          and global_assignment.active
          and global_role.key='platform_owner'
          and global_role.scope_level='global'
          and global_assignment.tenant_id is null
          and global_assignment.organization_id is null
          and global_assignment.facility_id is null
      )
      or exists (
        select 1
        from public.memberships m
        where m.user_id=p_actor
          and m.active
          and m.tenant_id=p_tenant
          and (m.organization_id is null or m.organization_id=p_organization)
          and (m.facility_id is null or m.facility_id=p_facility)
      )
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

revoke all on function public.inventory_actor_has_permission(
  uuid,text,uuid,uuid,uuid
) from public,anon,authenticated,service_role;
