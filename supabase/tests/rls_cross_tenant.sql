-- Run only against a disposable local Supabase database after creating two
-- authenticated test users and memberships. These assertions must return false.
-- select public.scope_allowed('<tenant-a>', '<organization-a>', '<facility-a>');
-- select public.scope_allowed('<tenant-b>', '<organization-b>', '<facility-b>');
-- A user scoped to tenant A must not select, insert, update, or archive tenant B rows.
-- Verify with `set local role authenticated` and `set_config('request.jwt.claim.sub', '<user-a>', true)`.

