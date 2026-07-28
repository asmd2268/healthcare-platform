\set ON_ERROR_STOP on
begin;

do $$
declare
  profile_rls_enabled boolean;
  profile_policy_roles name[];
begin
  select c.relrowsecurity
    into profile_rls_enabled
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='user_profiles';

  if not coalesce(profile_rls_enabled,false) then
    raise exception 'ASSERT: user_profiles RLS is not enabled';
  end if;

  if not has_table_privilege(
    'authenticated','public.user_profiles','SELECT'
  ) then
    raise exception 'ASSERT: authenticated cannot select its profile';
  end if;

  if has_table_privilege('anon','public.user_profiles','SELECT') then
    raise exception 'ASSERT: anon can select user profiles';
  end if;

  select roles
    into profile_policy_roles
    from pg_policies
    where schemaname='public'
      and tablename='user_profiles'
      and policyname='profile_self'
      and cmd='SELECT'
      and qual='(id = auth.uid())';

  if profile_policy_roles is distinct from array['authenticated']::name[] then
    raise exception 'ASSERT: profile_self is not authenticated-only';
  end if;
end $$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000009',
  true
);

do $$
begin
  if exists(select 1 from public.user_profiles) then
    raise exception 'ASSERT: profile_self exposed another user profile';
  end if;
end $$;

reset role;
rollback;
