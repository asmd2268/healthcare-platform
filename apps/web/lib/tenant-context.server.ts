import 'server-only';
import {requireAuthenticatedUser} from './auth.server';
import {createServerUserSupabaseClient} from './supabase-server';

export async function getCurrentTenantContext(){const user=await requireAuthenticatedUser();const supabase=await createServerUserSupabaseClient();const {data,error}=await supabase.from('memberships').select('tenant_id,organization_id,facility_id').eq('user_id',user.id).eq('active',true).limit(1).maybeSingle();if(error)throw new Error('Tenant context is unavailable.');return data?{tenantId:data.tenant_id,organizationId:data.organization_id,facilityId:data.facility_id}:null;}
