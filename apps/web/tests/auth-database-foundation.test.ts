import fs from 'node:fs';
import path from 'node:path';
import {describe,expect,it} from 'vitest';
import {authenticationRequired,protectedRouteSegments} from '@/lib/auth-policy';
import {canApprovePermanentDeletion} from '@/features/administration/repository';

const migration=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130001_core_platform_foundation.sql'),'utf8');

describe('authentication fail-closed policy',()=>{
  it('never treats a configured-but-unverified session as authenticated',()=>{expect(authenticationRequired(false,false)).toBe(true);expect(authenticationRequired(true,false)).toBe(true);expect(authenticationRequired(true,true)).toBe(false);expect(protectedRouteSegments.has('administration')).toBe(true);});
});
describe('database foundation migration',()=>{
  it('contains the required tenant-owned tables and enables RLS without permissive policies',()=>{for(const table of ['tenants','organizations','facilities','departments','user_profiles','memberships','roles','permissions','audit_events','form_definitions','form_versions','form_sections','form_fields','reference_data_groups','reference_data_items','deletion_requests'])expect(migration).toContain(`public.${table}`);expect(migration).not.toMatch(/using\s*\(\s*true\s*\)/i);expect(migration).toContain('enable row level security');});
  it('protects published versions and defines cross-tenant scope checks',()=>{expect(migration).toContain('Published form versions are immutable');expect(migration).toContain('create function public.scope_allowed');expect(migration).toContain('create function public.has_platform_permission');});
  it('keeps incomplete deletion safeguards disabled',()=>{expect(canApprovePermanentDeletion({recordId:'x',requesterId:'one',reason:'reason',typedConfirmation:'x',dependenciesChecked:true,backupConfirmed:true,reauthenticated:true,secondApprovalRequired:true,secondApproverId:'one',protectedRecord:false})).toBe(false);});
});
