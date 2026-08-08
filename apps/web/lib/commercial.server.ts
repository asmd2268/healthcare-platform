import 'server-only';
import {redirect} from 'next/navigation';
import {mergeBranding, type BrandingSettings} from '@healthcare/branding';
import {intersectModuleAccess,isModuleKey,type CommercialSummary,type ModuleKey} from '@healthcare/licensing';
import {createServerUserSupabaseClient} from './supabase-server';
import {getAuthenticatedUser} from './auth.server';
import {commercialConfiguration} from './commercial-config.server';
import type {CommercialScope as Scope,PlatformExperience} from './commercial-types';

type Result<T> = {data:T|null;error:unknown};

function brandingLayer(value: unknown): Partial<BrandingSettings> | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Partial<BrandingSettings> : null;
}

function commercialSummary(value: unknown): CommercialSummary | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const row = value as Record<string,unknown>;
  const modules = Array.isArray(row.modules) ? row.modules.filter((item):item is ModuleKey => typeof item === 'string' && isModuleKey(item)) : [];
  if (!['monthly','annual','perpetual','enterprise','trial'].includes(String(row.licenseModel))) return null;
  if (!['trial','active'].includes(String(row.status))) return null;
  if (!['cloud','on_premises','private_cloud'].includes(String(row.hostingMode))) return null;
  return {
    licenseModel: row.licenseModel as CommercialSummary['licenseModel'],
    status: row.status as CommercialSummary['status'],
    hostingMode: row.hostingMode as CommercialSummary['hostingMode'],
    startsAt: String(row.startsAt),
    expiresAt: typeof row.expiresAt === 'string' ? row.expiresAt : null,
    graceEndsAt: typeof row.graceEndsAt === 'string' ? row.graceEndsAt : null,
    whiteLabelEnabled: row.whiteLabelEnabled === true,
    maxUsers: typeof row.maxUsers === 'number' ? row.maxUsers : null,
    maxFacilities: typeof row.maxFacilities === 'number' ? row.maxFacilities : null,
    modules
  };
}

async function loadPublicBranding(hostname?: string | null) {
  if (!hostname) return null;
  try {
    const supabase = await createServerUserSupabaseClient();
    const {data,error} = await supabase.rpc('resolve_public_branding',{request_hostname:hostname}) as unknown as Result<unknown>;
    return error ? null : brandingLayer(data);
  } catch { return null; }
}

export async function loadPlatformExperience(hostname?: string | null): Promise<PlatformExperience> {
  const publicBranding = await loadPublicBranding(hostname);
  let scopedBranding: Partial<BrandingSettings> | null = null;
  let summary: CommercialSummary | null = null;
  let scope: Scope | null = null;
  try {
    const user = await getAuthenticatedUser();
    if (user) {
      const supabase = await createServerUserSupabaseClient();
      const membership = await supabase.from('memberships').select('tenant_id,organization_id,facility_id').eq('user_id',user.id).eq('active',true).limit(1).maybeSingle();
      if (!membership.error && membership.data) {
        scope = {tenantId:membership.data.tenant_id,organizationId:membership.data.organization_id,facilityId:membership.data.facility_id};
        const [brandingResult,summaryResult] = await Promise.all([
          supabase.rpc('resolve_effective_branding',{target_tenant:scope.tenantId,target_organization:scope.organizationId,target_facility:scope.facilityId}),
          supabase.rpc('current_commercial_summary',{target_tenant:scope.tenantId,target_organization:scope.organizationId,target_facility:scope.facilityId})
        ]);
        if (!brandingResult.error) scopedBranding = brandingLayer(brandingResult.data);
        if (!summaryResult.error) summary = commercialSummary(summaryResult.data);
      }
    }
  } catch { /* Public and build-time rendering use safe deployment defaults. */ }

  const licensedModules = summary?.modules ?? [];
  return {
    branding: mergeBranding(commercialConfiguration.branding,publicBranding,scopedBranding),
    enabledModules: intersectModuleAccess(commercialConfiguration.deploymentModules,licensedModules,commercialConfiguration.licenseEnforcement),
    deploymentProfile: commercialConfiguration.deploymentProfile,
    licenseEnforcement: commercialConfiguration.licenseEnforcement,
    commercialSummary: summary,
    scope
  };
}

export async function requireModuleAccess(module: ModuleKey, locale: string) {
  const experience = await loadPlatformExperience();
  if (!experience.enabledModules.includes(module)) redirect(`/${locale}/unauthorized`);
  return experience;
}

export async function loadScopedBrandingRecord(scope: Scope, level: 'organization' | 'facility') {
  try {
    const supabase=await createServerUserSupabaseClient();
    let query=supabase.from('branding_settings').select('id,revision,settings')
      .eq('tenant_id',scope.tenantId).eq('organization_id',scope.organizationId!);
    query=level==='facility' ? query.eq('facility_id',scope.facilityId!) : query.is('facility_id',null);
    const {data,error}=await query.maybeSingle();
    if(error||!data)return null;
    return {id:data.id,revision:data.revision,settings:brandingLayer(data.settings)};
  } catch{return null;}
}

export async function loadBrandingEditorContext(scope: Scope, level: 'organization' | 'facility') {
  const targetFacility=level==='facility'?scope.facilityId:null;
  const record=await loadScopedBrandingRecord(scope,level);
  try{
    const supabase=await createServerUserSupabaseClient();
    const [brandingResult,whiteLabelResult]=await Promise.all([
      supabase.rpc('resolve_effective_branding',{target_tenant:scope.tenantId,target_organization:scope.organizationId,target_facility:targetFacility}),
      supabase.rpc('has_white_label_entitlement',{target_tenant:scope.tenantId,target_organization:scope.organizationId,target_facility:targetFacility})
    ]);
    return {
      record,
      branding:mergeBranding(commercialConfiguration.branding,brandingResult.error?null:brandingLayer(brandingResult.data)),
      whiteLabelEnabled:!whiteLabelResult.error&&whiteLabelResult.data===true
    };
  }catch{
    return {record,branding:mergeBranding(commercialConfiguration.branding,record?.settings),whiteLabelEnabled:false};
  }
}
