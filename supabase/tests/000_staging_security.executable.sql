\set ON_ERROR_STOP on
begin;
do $$ declare result_type text; authenticated_can_execute boolean; anon_can_execute boolean; begin
 select pg_get_function_result(p.oid) into result_type from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='approve_workflow_request' and oidvectortypes(p.proargtypes)='uuid, text';
 if result_type <> 'boolean' then raise exception 'ASSERT: expected boolean workflow approval return, got %',result_type; end if;
 select has_function_privilege('authenticated','public.approve_workflow_request(uuid,text)','EXECUTE'),has_function_privilege('anon','public.approve_workflow_request(uuid,text)','EXECUTE') into authenticated_can_execute,anon_can_execute;
 if not authenticated_can_execute or anon_can_execute then raise exception 'ASSERT: unsafe workflow approval grants'; end if;
 if has_function_privilege('authenticated','public.append_trusted_audit_event(uuid,uuid,uuid,uuid,text,text,uuid,jsonb)','EXECUTE') then raise exception 'ASSERT: trusted audit forgery grant'; end if;
end $$;
rollback;
