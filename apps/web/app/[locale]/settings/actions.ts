'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {getCurrentTenantContext} from '@/lib/tenant-context.server';
import {requirePlatformPermission} from '@/lib/auth.server';
import {createServerUserSupabaseClient} from '@/lib/supabase-server';

export type BrandingActionState={status:'idle'|'saved'|'conflict'|'denied'|'invalid'|'failed'};

const optionalText=(maximum:number)=>z.preprocess((value)=>value===''?undefined:value,z.string().trim().max(maximum).optional());
const schema=z.object({
  locale:z.enum(['ar','en']),scopeLevel:z.enum(['organization','facility']),
  expectedRevision:z.preprocess((value)=>value===''?null:Number(value),z.number().int().positive().nullable()),
  platformNameAr:z.string().trim().min(1).max(160),platformNameEn:z.string().trim().min(1).max(160),
  organizationNameAr:z.string().trim().min(1).max(160),organizationNameEn:z.string().trim().min(1).max(160),
  facilityNameAr:optionalText(160),facilityNameEn:optionalText(160),
  logoUrl:z.preprocess((value)=>value===''?undefined:value,z.string().url().startsWith('https://').max(500).optional()),
  faviconUrl:z.preprocess((value)=>value===''?undefined:value,z.string().url().startsWith('https://').max(500).optional()),
  primaryColor:z.string().regex(/^#[0-9a-f]{6}$/i),accentColor:z.string().regex(/^#[0-9a-f]{6}$/i),
  contactEmail:z.preprocess((value)=>value===''?undefined:value,z.string().email().max(254).optional()),
  reportHeaderAr:optionalText(500),reportHeaderEn:optionalText(500),reportFooterAr:optionalText(500),reportFooterEn:optionalText(500),
  emailSenderNameAr:optionalText(160),emailSenderNameEn:optionalText(160),
  showDeveloperAttribution:z.enum(['true','false']).transform((value)=>value==='true')
});

export async function updateBrandingAction(_state:BrandingActionState,formData:FormData):Promise<BrandingActionState>{
  const parsed=schema.safeParse(Object.fromEntries(formData));
  if(!parsed.success)return {status:'invalid'};
  try{
    const context=await getCurrentTenantContext();
    if(!context?.organizationId)return {status:'denied'};
    const {locale,scopeLevel,expectedRevision,...settings}=parsed.data;
    if(scopeLevel==='facility'&&!context.facilityId)return {status:'denied'};
    const targetScope={tenantId:context.tenantId,organizationId:context.organizationId,facilityId:scopeLevel==='facility'?context.facilityId:null};
    await requirePlatformPermission('platform.manage_branding',targetScope);
    const supabase=await createServerUserSupabaseClient();
    const {error}=await supabase.rpc('update_scoped_branding',{
      target_tenant:targetScope.tenantId,
      target_organization:targetScope.organizationId,
      target_facility:targetScope.facilityId,
      branding_payload:settings,
      expected_revision:expectedRevision
    });
    if(error){
      if(/revision conflict/i.test(error.message))return {status:'conflict'};
      if(/not authorized|entitlement/i.test(error.message))return {status:'denied'};
      if(/invalid/i.test(error.message))return {status:'invalid'};
      return {status:'failed'};
    }
    revalidatePath(`/${locale}/settings`);
    return {status:'saved'};
  }catch{return {status:'denied'};}
}
