import 'server-only';
import {createServerUserSupabaseClient} from '@/lib/supabase-server';

export async function listRecentAuditEvents(scope:{tenantId:string;organizationId?:string|null;facilityId?:string|null}){const supabase=await createServerUserSupabaseClient();const since=new Date(Date.now()-24*60*60*1000).toISOString();const {data,error}=await supabase.from('audit_events').select('id,action,entity_type,entity_id,created_at,actor_id').eq('tenant_id',scope.tenantId).is('organization_id',scope.organizationId??null).is('facility_id',scope.facilityId??null).gte('created_at',since).order('created_at',{ascending:false});if(error)throw new Error('Unable to load audit events.');return data;}
