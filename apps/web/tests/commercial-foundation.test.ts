import fs from 'node:fs';
import path from 'node:path';
import {describe,expect,it} from 'vitest';
import {defaultBranding,localizedBranding,mergeBranding} from '@healthcare/branding';
import {deploymentProfiles,intersectModuleAccess,resolveDeploymentModules} from '@healthcare/licensing';

const repositoryRoot=path.resolve(process.cwd(),'../..');
const read=(file:string)=>fs.readFileSync(path.join(repositoryRoot,file),'utf8');

describe('commercial deployment profiles',()=>{
  it('provides focused standalone-friendly editions',()=>{
    expect(deploymentProfiles.inventory).toEqual(['core','inventory','audit']);
    expect(deploymentProfiles.quality).toContain('inspections');
    expect(deploymentProfiles['medication-safety']).toContain('medication_errors');
    expect(deploymentProfiles.full).toContain('administration');
  });
  it('normalizes custom editions and ignores unknown module names',()=>{
    expect(resolveDeploymentModules('custom','inventory, policies,invalid,inventory')).toEqual(['core','inventory','policies']);
  });
  it('intersects deployment and subscription access only in strict mode',()=>{
    const deployed=resolveDeploymentModules('quality');
    expect(intersectModuleAccess(deployed,['inspections'],'strict')).toEqual(['core','inspections']);
    expect(intersectModuleAccess(deployed,[],'disabled')).toEqual(deployed);
  });
});

describe('white-label branding',()=>{
  it('merges safe layers and localizes official labels without changing content',()=>{
    const branding=mergeBranding({platformNameAr:'منصة العميل',platformNameEn:'Customer Platform',primaryColor:'#112233'});
    expect(branding.primaryColor).toBe('#112233');
    expect(localizedBranding(branding,'ar').platformName).toBe('منصة العميل');
    expect(localizedBranding(branding,'en').platformName).toBe('Customer Platform');
  });
  it('keeps safe defaults when an optional layer is empty or malformed',()=>{
    expect(mergeBranding({platformNameEn:' ',primaryColor:'red'} as never)).toEqual(defaultBranding);
  });
});

describe('commercial security boundaries',()=>{
  const migration=read('supabase/migrations/202608010001_white_label_licensing_foundation.sql');
  const server=read('apps/web/lib/commercial.server.ts');
  it('keeps licensing decisions server-side and fail-closed in strict mode',()=>{
    expect(server).toContain("import 'server-only'");
    expect(server).toContain('intersectModuleAccess');
    expect(server).not.toContain('SUPABASE_SERVICE_ROLE_KEY');
    expect(migration).toContain('public.has_module_entitlement');
    expect(migration).toContain('public.scope_allowed');
  });
  it('does not grant customers direct commercial writes or domain reads',()=>{
    expect(migration).toContain('revoke insert,update,delete,truncate,references,trigger');
    expect(migration).toContain('revoke all on table public.platform_modules,public.commercial_licenses,public.license_entitlements,public.branding_domains from anon');
    expect(migration).toContain('revoke all on table public.branding_settings from anon');
    expect(migration).toContain('grant select on table public.memberships to authenticated');
    expect(migration).toContain('External license reference conflict');
    expect(migration).toContain('grant execute on function public.resolve_public_branding(text) to anon,authenticated');
    expect(migration).not.toMatch(/grant\s+(insert|update|delete)[^;]+commercial_licenses[^;]+authenticated/i);
  });
  it('gates every licensed route family on the server',()=>{
    const layouts=[
      ['inventory','inventory'],['inspections','inspections'],['medication-errors','medication_errors'],
      ['policies','policies'],['capa','capa'],['audit','audit'],['administration','administration']
    ];
    for(const [route,module] of layouts){
      expect(read(`apps/web/app/[locale]/${route}/layout.tsx`)).toContain(`requireModuleAccess('${module}',locale)`);
    }
  });
});
