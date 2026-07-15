\set ON_ERROR_STOP on
begin;

-- Catalogue assertions are intentionally executable against a disposable staging
-- database. They cover the controls that must remain true even with no seed data.
do $$
declare fn text; has_write_policy boolean; n integer;
begin
  -- Regression: the generic hierarchy trigger must accept a facility row, whose
  -- identifier is `id` rather than a nonexistent `facility_id` column.
  declare t uuid:=gen_random_uuid(); o uuid:=gen_random_uuid(); f uuid:=gen_random_uuid(); begin
    insert into public.tenants(id,key,name_en) values(t,'scope-'||left(t::text,8),'Scope test');
    insert into public.organizations(id,tenant_id,code,name_en) values(o,t,'SCOPE','Scope organization');
    insert into public.facilities(id,tenant_id,organization_id,code,name_en) values(f,t,o,'SCOPE','Scope facility');
  end;

  if to_regprocedure('public.create_capa(uuid,uuid,uuid,text,text,text,text,uuid,text,text,uuid)') is null
     or to_regprocedure('public.transition_capa(uuid,public.capa_status,text)') is null
     or to_regprocedure('public.transition_capa_action(uuid,public.capa_action_status,text)') is null
     or to_regprocedure('public.request_capa_due_date_extension(uuid,uuid,date,text)') is null
     or to_regprocedure('public.finalize_capa_evidence_verified(uuid,text)') is null then
    raise exception 'ASSERT: controlled CAPA functions are missing';
  end if;

  select pg_get_functiondef('public.record_capa_event(uuid,uuid,uuid,uuid,text,jsonb)'::regprocedure) into fn;
  if fn like '%append_reporting_audit_event%' or fn not like '%append_capa_audit_event%' then
    raise exception 'ASSERT: CAPA audit path depends on Reporting or lacks CAPA audit';
  end if;

  if has_function_privilege('authenticated','public.finalize_capa_evidence_verified(uuid,text)','EXECUTE')
     or has_function_privilege('authenticated','public.record_capa_event(uuid,uuid,uuid,uuid,text,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.next_capa_number(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'ASSERT: untrusted CAPA internal function is executable';
  end if;

  select count(*) into n from storage.buckets where id='capa-evidence' and public=false;
  if n<>1 then raise exception 'ASSERT: CAPA evidence bucket is not private'; end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='capa_evidence_storage_insert')
     or exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname in ('capa_evidence_storage_update','capa_evidence_storage_delete')) then
    raise exception 'ASSERT: CAPA storage policy is unsafe';
  end if;

  select exists(select 1 from pg_policies where schemaname='public' and tablename in ('capa_records','capa_actions','capa_due_date_extensions','capa_evidence','capa_events') and cmd in ('INSERT','UPDATE','DELETE','ALL')) into has_write_policy;
  if has_write_policy then raise exception 'ASSERT: direct CAPA client write policy exists'; end if;

  if not exists(select 1 from pg_indexes where schemaname='public' and indexname='capa_evidence_upload_authorization_unique')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='capa_due_date_extensions' and column_name='action_id') then
    raise exception 'ASSERT: CAPA evidence or action-extension binding is missing';
  end if;
end $$;

-- Behavioural fail-closed checks. Fictitious IDs must be rejected rather than
-- yielding access, and direct finalization must not be callable as authenticated.
do $$
begin
  begin
    perform public.transition_capa('00000000-0000-0000-0000-000000000201'::uuid,'submitted',null);
    raise exception 'ASSERT: nonexistent CAPA transition unexpectedly succeeded';
  exception when others then
    if sqlerrm <> 'CAPA lifecycle transition denied' then raise; end if;
  end;
end $$;

rollback;
