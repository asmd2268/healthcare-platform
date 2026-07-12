import 'server-only';
import {z} from 'zod';
import {createAdminSupabaseClient} from './supabase-admin.server';

const inputSchema=z.object({userId:z.string().uuid(),tenantId:z.string().uuid(),confirmation:z.literal('BOOTSTRAP_PLATFORM_OWNER')});
/** Reviewed server-only bootstrap entry point. No browser route imports this module. */
export async function bootstrapFirstPlatformOwner(input:unknown){
  const {userId,tenantId,confirmation}=inputSchema.parse(input);
  if(confirmation!==process.env.PLATFORM_OWNER_BOOTSTRAP_CONFIRMATION)throw new Error('Bootstrap confirmation is missing or invalid.');
  const admin=createAdminSupabaseClient(); const {error}=await admin.rpc('bootstrap_first_platform_owner',{p_user_id:userId,p_tenant_id:tenantId});
  if(error)throw new Error('Platform Owner bootstrap failed.');
}
