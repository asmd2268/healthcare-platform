-- Restore least-privilege profile reads for authenticated application users.
-- RLS still limits each request to the caller's own auth.uid() row.
revoke select on table public.user_profiles from public, anon;
grant select on table public.user_profiles to authenticated;

alter policy profile_self on public.user_profiles
  to authenticated
  using (id = auth.uid());
