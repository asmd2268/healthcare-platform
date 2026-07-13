import fs from 'node:fs';
import path from 'node:path';
import {describe, expect, it} from 'vitest';
import {canTransitionPolicy,createDraftPolicyVersion,policyPermissions,policySearchContract,type PolicyDefinition,type PolicyVersion} from '@healthcare/policies-procedures';

const scope={tenantId:'tenant',organizationId:'organization',facilityId:'facility'};
const definition:PolicyDefinition={...scope,id:'policy',policyId:'POL-001',policyNumber:'POL-001',ownerId:'owner',status:'published',currentVersionId:'version',title:{ar:'سياسة',en:'Policy'},related:[]};
const version:PolicyVersion={...scope,id:'version',policyId:'policy',versionMajor:1,versionMinor:0,status:'published',title:{ar:'سياسة',en:'Policy'},contentLanguage:'bilingual',changeSummary:'Initial',keywords:['policy'],tags:[],createdBy:'owner',createdAt:'2026-07-13T00:00:00.000Z'};

describe('policies and procedures contracts',()=>{
  it('creates an independent draft from a published policy version',()=>{const draft=createDraftPolicyVersion(definition,version,'editor','Clarify review interval');draft.keywords.push('review');expect(draft.status).toBe('draft');expect(draft.versionMinor).toBe(1);expect(version.keywords).toEqual(['policy']);expect(()=>createDraftPolicyVersion(definition,version,'editor',' ')).toThrow('change summary')});
  it('permits only declared lifecycle transitions',()=>{expect(canTransitionPolicy('draft','under_review')).toBe(true);expect(canTransitionPolicy('published','draft')).toBe(false);expect(canTransitionPolicy('archived','published')).toBe(false)});
  it('bounds the portable bilingual search contract',()=>{expect(policySearchContract({query:'سياسة',page:0,pageSize:999}).pageSize).toBe(200);expect(policySearchContract({page:1,pageSize:1}).fullTextFuture.columns).toContain('title_ar')});
  it('exposes granular policy permissions',()=>{expect(policyPermissions).toContain('policies.publish');expect(policyPermissions).toContain('policies.acknowledge')});
});

describe('policies database foundation',()=>{
  const sql=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130016_policies_and_procedures_foundation.sql'),'utf8');
  it('uses scoped metadata-only documents and immutable published versions',()=>{for(const expected of ['policy_definitions','policy_versions','policy_documents','storage_bucket','storage_key','checksum','byte_size','enable row level security','Published policy versions are immutable','Published policy must reference its own published current version'])expect(sql).toContain(expected)});
  it('reuses controlled workflow, acknowledgement, and audit contracts',()=>{for(const expected of ['workflow_instance_id','create_policy_draft_version','publish_policy_version','acknowledge_policy_version','policy_events','policies.manage_configuration'])expect(sql).toContain(expected)});
});

describe('policies lifecycle and storage hardening',()=>{
  const sql=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130017_secure_policy_lifecycle_documents_storage.sql'),'utf8');
  it('removes broad writes and routes lifecycle actions through controlled functions',()=>{for(const expected of ['drop policy if exists policy_definitions_write','drop policy if exists policy_versions_draft_write','create_policy_definition','update_policy_draft_metadata','submit_policy_for_review','approve_policy_version','reject_policy_version','archive_policy_definition','restore_policy_definition'])expect(sql).toContain(expected)});
  it('makes publication atomic, single-version, and superseding',()=>{for(const expected of ['policy_versions_one_published_per_definition','for update','status=\'superseded\'','status=\'published\'','Approved policy version required'])expect(sql).toContain(expected)});
  it('protects non-draft documents, private acknowledgements, and append-only events',()=>{for(const expected of ['Documents may only change on draft policy versions','policy_documents_read','can_view_policy_document','policy_acknowledgements_self','policy_acknowledgements_manager','record_policy_event','public.record_policy_event(uuid,uuid,uuid,uuid,uuid,text,jsonb)'])expect(sql).toContain(expected)});
  it('uses a private, scope-checked storage bucket and rejects macro files',()=>{for(const expected of ["'policy-documents'","public=false",'policy_storage_object_allowed','policy_documents_storage_insert','docm|xlsm|pptm','Policy document storage path is unsafe'])expect(sql).toContain(expected)});
  it('requires same-scope user and link targets',()=>{for(const expected of ['Policy user reference is outside scope','Policy document uploader is outside scope','Policy link target is invalid or outside scope','Policy link adapter is not implemented'])expect(sql).toContain(expected)});
});

describe('policies archival, approval, and upload safeguards',()=>{
  const sql=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130018_complete_policy_archival_approval_upload_safeguards.sql'),'utf8');
  it('hides archived and draft content from ordinary policy viewers while allowing explicit history',()=>{for(const expected of ['policies.view_history',"d.status='published' and status='published'","status='archived'","policy_definitions_read","policy_versions_read","can_view_policy_document"])expect(sql).toContain(expected)});
  it('separates submitting and approving from editing and ownership',()=>{for(const expected of ['policies.submit','policies.override_approval_assignment','auth.uid()=v.created_by','auth.uid()=d.owner_id','d.approver_id<>auth.uid()','Policy approval denied'])expect(sql).toContain(expected)});
  it('requires a private bucket and trusted verification before metadata finalization',()=>{for(const expected of ["p_bucket <> 'policy-documents'",'finalize_policy_document_verified','Trusted policy upload finalization requires service role','storage.objects','expected_checksum','malware_scan_status','revoke all on function public.finalize_policy_document'])expect(sql).toContain(expected)});
  it('keeps deletion server-controlled and draft-only',()=>{for(const expected of ['delete_draft_policy_document','Trusted policy document deletion requires service role',"v.status<>'draft'",'policy_actor_has_permission','policy.document_deleted'])expect(sql).toContain(expected)});
});

describe('policies trusted upload and service actor safeguards',()=>{
  const sql=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130019_bind_policy_uploads_to_trusted_authorization_and_audit_actors.sql'),'utf8');
  it('binds storage insertion to the active uploader authorization',()=>{for(const expected of ['a.storage_key=p_name','a.uploader_id=auth.uid()','a.expires_at>now()','a.finalized_at is null',"x.status='draft'",'policy_documents_storage_insert'])expect(sql).toContain(expected)});
  it('prevents authorization reuse and requires trusted checksum and scan states',()=>{for(const expected of ['upload_authorization_id','policy_documents_upload_authorization_unique','a.finalized_at is not null','checksum_verification_status','<>\'verified\'','Policy malware scan is not accepted'])expect(sql).toContain(expected)});
  it('attributes service operations to validated actors and rolls back on audit failure',()=>{for(const expected of ['append_policy_audit_event_for_actor','record_policy_event_for_actor','p_actor','a.uploader_id','policy_member_in_scope','policy_actor_has_permission','insert into public.audit_events'])expect(sql).toContain(expected)});
  it('derives extension from trusted storage and rejects MIME mismatches',()=>{for(const expected of ['extension:=lower','Policy upload MIME or metadata is invalid',"extension not in ('pdf','docx','doc','xlsx','xls','pptx','jpg','jpeg','png','webp')",'p_mime<>'])expect(sql).toContain(expected)});
});

describe('policy upload extension and deletion cleanup contracts',()=>{
  const sql=fs.readFileSync(path.join(process.cwd(),'../../supabase/migrations/202607130020_complete_policy_upload_extension_and_deletion_cleanup.sql'),'utf8');
  it('rejects unsupported, extensionless, macro, and double-executable names before authorization',()=>{for(const expected of ['authorize_policy_upload',"(pdf|docx|doc|xlsx|xls|pptx|jpg|jpeg|png|webp)",'Unsupported or unsafe policy filename','^[a-z0-9][a-z0-9_-]*'])expect(sql).toContain(expected)});
  it('uses a two-phase deletion flow that preserves metadata until storage deletion succeeds',()=>{for(const expected of ['policy_document_deletion_requests','prepare_draft_policy_document_deletion','complete_draft_policy_document_deletion','Policy storage deletion must succeed before metadata deletion','delete from public.policy_documents','policy.document_deletion_prepared'])expect(sql).toContain(expected)});
  it('keeps retained documents out of orphan cleanup and disables the metadata-only deletion API',()=>{for(const expected of ["v.status<>'draft'",'Use prepare_draft_policy_document_deletion and trusted completion','policy_document_deletion_requests_active_unique','storage_delete_failed','expired'])expect(sql).toContain(expected)});
});
