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
