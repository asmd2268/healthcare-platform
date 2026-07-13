-- Disposable local Supabase test scenarios for published-form access.
-- Run after migrations with fictional users, memberships, and role assignments.

-- Confirm role defaults (must be true for all three and must not include manage_forms):
-- select r.key, exists(select 1 from public.role_permissions rp join public.permissions p on p.id=rp.permission_id where rp.role_id=r.id and p.key='platform.view_published_forms') as can_view_published, exists(select 1 from public.role_permissions rp join public.permissions p on p.id=rp.permission_id where rp.role_id=r.id and p.key='platform.manage_forms') as can_manage_forms from public.roles r where r.key in ('organization_administrator','facility_administrator','scoped_user');

-- Under a fictional scoped_user JWT and matching membership/assignment:
-- select * from public.form_definitions where id='<published-form-in-scope>';
-- Expected: one published form definition and its published version/sections/fields.
-- select * from public.form_definitions where id='<draft-form-in-scope>';
-- Expected: zero rows.
-- select * from public.form_definitions where id='<published-form-other-tenant-or-organization-or-facility>';
-- Expected: zero rows for each cross-scope case.
-- set local role anon;
-- select * from public.form_definitions;
-- Expected: zero rows.

-- Publication integrity scenarios (expect check_violation):
-- update public.form_definitions set status='published', current_version_id='<draft-version-id>' where id='<form-id>';
-- update public.form_definitions set status='published', current_version_id='<archived-version-id>' where id='<form-id>';
-- update public.form_definitions set status='published', current_version_id='<different-form-published-version-id>' where id='<form-id>';
