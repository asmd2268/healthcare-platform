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
end $$;
rollback;
