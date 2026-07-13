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

const auditInputSchema=z.object({tenantId:z.string().uuid(),organizationId:z.string().uuid().nullable().optional(),facilityId:z.string().uuid().nullable().optional(),actorId:z.string().uuid().nullable().optional(),action:z.enum(['role.assignment','permission.change','form.created','form.updated','form.version_created','form.published','form.archived','form.restored','reference_data.changed','import.requested','export.requested','deletion.requested','record.corrected']),entityType:z.string().min(1).max(100),entityId:z.string().uuid().nullable().optional(),metadata:z.record(z.string(),z.unknown()).default({})});
/** Service-role-only audit writer. It is deliberately unavailable to browser and user-request modules. */
export async function appendTrustedAuditEvent(input:unknown){const value=auditInputSchema.parse(input);const admin=createAdminSupabaseClient();const {error}=await admin.rpc('append_trusted_audit_event',{event_tenant_id:value.tenantId,event_organization_id:value.organizationId??null,event_facility_id:value.facilityId??null,event_actor_id:value.actorId??null,event_action:value.action,event_entity_type:value.entityType,event_entity_id:value.entityId??null,event_metadata:value.metadata});if(error)throw new Error('Trusted audit write failed.');}
