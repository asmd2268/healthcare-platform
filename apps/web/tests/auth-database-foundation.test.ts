import fs from 'node:fs';
import path from 'node:path';
import {describe,expect,it} from 'vitest';
import {authenticationRequired,protectedRouteSegments} from '@/lib/auth-policy';
import {passwordResetRedirect,safeLocale} from '@/lib/auth-redirect';
import {canApprovePermanentDeletion} from '@/features/administration/repository';

const migration=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130001_core_platform_foundation.sql'),'utf8');
const hardeningMigration=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130002_harden_tenant_integrity_audit_and_bootstrap.sql'),'utf8');
const publishedFormMigration=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130003_grant_scoped_published_form_access.sql'),'utf8');

describe('authentication fail-closed policy',()=>{
  it('never treats a configured-but-unverified session as authenticated',()=>{expect(authenticationRequired(false,false)).toBe(true);expect(authenticationRequired(true,false)).toBe(true);expect(authenticationRequired(true,true)).toBe(false);expect(protectedRouteSegments.has('administration')).toBe(true);});
  it('builds password reset redirects from a validated base URL and a safe locale',()=>{expect(passwordResetRedirect('https://platform.example','en')).toBe('https://platform.example/auth/callback?locale=en');expect(safeLocale('attacker')).toBe('ar');expect(()=>passwordResetRedirect('ftp://platform.example','ar')).toThrow();});
});
describe('database foundation migration',()=>{
  it('contains the required tenant-owned tables and enables RLS without permissive policies',()=>{for(const table of ['tenants','organizations','facilities','departments','user_profiles','memberships','roles','permissions','audit_events','form_definitions','form_versions','form_sections','form_fields','reference_data_groups','reference_data_items','deletion_requests'])expect(migration).toContain(`public.${table}`);expect(migration).not.toMatch(/using\s*\(\s*true\s*\)/i);expect(migration).toContain('enable row level security');});
  it('protects published versions and defines cross-tenant scope checks',()=>{expect(migration).toContain('Published form versions are immutable');expect(migration).toContain('create function public.scope_allowed');expect(migration).toContain('create function public.has_platform_permission');});
  it('keeps incomplete deletion safeguards disabled',()=>{expect(canApprovePermanentDeletion({recordId:'x',requesterId:'one',reason:'reason',typedConfirmation:'x',dependenciesChecked:true,backupConfirmed:true,reauthenticated:true,secondApprovalRequired:true,secondApproverId:'one',protectedRecord:false})).toBe(false);});
  it('adds deterministic bootstrap, trusted-audit, tenant-integrity, and published-view protections',()=>{expect(hardeningMigration).toContain('user_role_assignments_global_role_once');expect(hardeningMigration).toContain('append_trusted_audit_event');expect(hardeningMigration).toContain('revoke all on function public.append_audit_event');expect(hardeningMigration).toContain('enforce_form_version_scope');expect(hardeningMigration).toContain('platform.view_published_forms');});
  it('grants scoped roles view-only access to published forms and preserves publication integrity',()=>{const permissionGrant=publishedFormMigration.split('create or replace function')[0];for(const role of ['organization_administrator','facility_administrator','scoped_user'])expect(permissionGrant).toContain(`'${role}'`);expect(permissionGrant).toContain("p.key='platform.view_published_forms'");expect(permissionGrant).not.toContain("p.key='platform.manage_forms'");expect(publishedFormMigration).toContain('enforce_published_form_current_version');expect(publishedFormMigration).toContain("v.status='published'");});
});
