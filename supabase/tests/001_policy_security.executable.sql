\set ON_ERROR_STOP on
begin;
-- Security smoke assertions: uses only catalogue data and deterministic fictional identifiers.
do $$
declare
  has_broad_definition_write boolean;
  has_broad_version_write boolean;
  has_document_insert boolean;
  has_event_insert boolean;
begin
  if to_regprocedure('public.publish_policy_version(uuid,uuid)') is null
     or to_regprocedure('public.approve_policy_version(uuid)') is null
     or to_regprocedure('public.finalize_policy_document(uuid,text,text,text,text,bigint,public.content_language,text,boolean,text,text)') is null then
    raise exception 'ASSERT: controlled policy lifecycle functions are missing';
  end if;
  select exists(select 1 from pg_policies where schemaname='public' and tablename='policy_definitions' and policyname='policy_definitions_write') into has_broad_definition_write;
  select exists(select 1 from pg_policies where schemaname='public' and tablename='policy_versions' and policyname='policy_versions_draft_write') into has_broad_version_write;
  if has_broad_definition_write or has_broad_version_write then raise exception 'ASSERT: broad policy lifecycle write policy remains'; end if;
  select has_table_privilege('authenticated','public.policy_documents','INSERT'),has_table_privilege('authenticated','public.policy_events','INSERT') into has_document_insert,has_event_insert;
  -- Table privileges alone are not authorization evidence; RLS must have no client write policies.
  if exists(select 1 from pg_policies where schemaname='public' and tablename='policy_events' and cmd in ('INSERT','ALL')) then raise exception 'ASSERT: policy event forgery policy exists'; end if;
  if not exists(select 1 from pg_indexes where schemaname='public' and indexname='policy_versions_one_published_per_definition') then raise exception 'ASSERT: published policy uniqueness index missing'; end if;
  if not exists(select 1 from storage.buckets where id='policy-documents' and public=false) then raise exception 'ASSERT: private policy storage bucket missing'; end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='policy_documents_storage_insert') then raise exception 'ASSERT: scoped policy storage insert policy missing'; end if;
  if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname in ('policy_documents_storage_update','policy_documents_storage_delete')) then raise exception 'ASSERT: unsafe policy storage mutation policy exists'; end if;
  if to_regprocedure('public.approve_policy_version(uuid)') is null or to_regprocedure('public.authorize_policy_upload(uuid,text,bigint,text)') is null or to_regprocedure('public.finalize_policy_document_verified(uuid,text,public.content_language,text,boolean,text,text)') is null or to_regprocedure('public.delete_draft_policy_document(uuid,uuid)') is null then raise exception 'ASSERT: archival approval or upload safeguard is missing'; end if;
  if exists(select 1 from pg_policies where schemaname='public' and tablename='policy_definitions' and policyname='policy_definitions_read' and qual not like '%view_history%') then raise exception 'ASSERT: policy definition history visibility is not explicit'; end if;
  if has_function_privilege('authenticated','public.finalize_policy_document(uuid,text,text,text,text,bigint,public.content_language,text,boolean,text,text)','EXECUTE') then raise exception 'ASSERT: browser metadata finalization remains executable'; end if;
  if to_regprocedure('public.record_policy_event_for_actor(uuid,uuid,uuid,uuid,uuid,uuid,text,text,jsonb)') is null or to_regprocedure('public.append_policy_audit_event_for_actor(uuid,uuid,uuid,uuid,text,text,text,uuid,jsonb)') is null then raise exception 'ASSERT: trusted actor-aware audit path is missing'; end if;
  if pg_get_functiondef('public.policy_actor_has_permission(uuid,text,uuid,uuid,uuid)'::regprocedure) like '%r.active%' then raise exception 'ASSERT: policy actor permission refers to a nonexistent roles.active column'; end if;
  if has_function_privilege('authenticated','public.record_policy_event_for_actor(uuid,uuid,uuid,uuid,uuid,uuid,text,text,jsonb)','EXECUTE') then raise exception 'ASSERT: authenticated users can forge actor-aware policy events'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='policy_documents' and column_name='upload_authorization_id') then raise exception 'ASSERT: policy document authorization binding is missing'; end if;
  if to_regprocedure('public.prepare_draft_policy_document_deletion(uuid)') is null or to_regprocedure('public.complete_draft_policy_document_deletion(uuid)') is null then raise exception 'ASSERT: two-phase policy deletion contract is missing'; end if;
  if has_function_privilege('authenticated','public.complete_draft_policy_document_deletion(uuid)','EXECUTE') then raise exception 'ASSERT: browser can complete storage-backed deletion'; end if;
end $$;
rollback;
