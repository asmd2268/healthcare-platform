\set ON_ERROR_STOP on
begin;

-- These tests intentionally use the same request claims and database role that
-- Supabase applies to an authenticated API request.  Fixture writes happen only
-- before SET LOCAL ROLE authenticated; every asserted CAPA operation after that
-- point is subject to real grants, RLS and auth.uid().
create function public.capa_test_assert(p_condition boolean,p_message text) returns void language plpgsql as $$
begin if not p_condition then raise exception 'ASSERT: %',p_message; end if; end $$;
create function public.capa_test_expect_failure(p_sql text,p_fragment text) returns void language plpgsql as $$
begin
  begin execute p_sql; exception when others then
    if position(p_fragment in sqlerrm)=0 then raise; end if;
    return;
  end;
  raise exception 'ASSERT: expected failure (%)',p_fragment;
end $$;
grant execute on function public.capa_test_assert(boolean,text),public.capa_test_expect_failure(text,text) to authenticated;

do $$
declare t_a uuid:='00000000-0000-0000-0000-00000000a301'; o_a uuid:='00000000-0000-0000-0000-00000000a302'; f_a uuid:='00000000-0000-0000-0000-00000000a303'; f_other uuid:='00000000-0000-0000-0000-00000000a304'; t_b uuid:='00000000-0000-0000-0000-00000000b301'; o_b uuid:='00000000-0000-0000-0000-00000000b302'; f_b uuid:='00000000-0000-0000-0000-00000000b303'; role_all uuid:=gen_random_uuid(); role_view uuid:=gen_random_uuid(); role_conf uuid:=gen_random_uuid(); g uuid:=gen_random_uuid();
begin
  insert into public.tenants(id,key,name_en) values(t_a,'capa-test-a','CAPA test A'),(t_b,'capa-test-b','CAPA test B');
  insert into public.organizations(id,tenant_id,code,name_en) values(o_a,t_a,'CAPA-A','CAPA org A'),(o_b,t_b,'CAPA-B','CAPA org B');
  insert into public.facilities(id,tenant_id,organization_id,code,name_en) values(f_a,t_a,o_a,'CAPA-A','CAPA facility A'),(f_other,t_a,o_a,'CAPA-OTHER','CAPA facility other'),(f_b,t_b,o_b,'CAPA-B','CAPA facility B');
  insert into public.reference_data_groups(id,tenant_id,organization_id,facility_id,key,name_en) values(g,t_a,o_a,f_a,'capa-method','CAPA method');
  insert into public.reference_data_items(id,group_id,tenant_id,organization_id,facility_id,code,label_en,display_order) values('00000000-0000-0000-0000-00000000a350',g,t_a,o_a,f_a,'five-why','Five why',0);
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  select id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','capa-'||right(id::text,4)||'@example.test','not-used',now(),'{}','{}',now(),now()
  from (values
    ('00000000-0000-0000-0000-00000000a311'::uuid),('00000000-0000-0000-0000-00000000a312'::uuid),('00000000-0000-0000-0000-00000000a313'::uuid),('00000000-0000-0000-0000-00000000a314'::uuid),('00000000-0000-0000-0000-00000000a315'::uuid),('00000000-0000-0000-0000-00000000a316'::uuid),('00000000-0000-0000-0000-00000000a317'::uuid),('00000000-0000-0000-0000-00000000a318'::uuid),('00000000-0000-0000-0000-00000000b311'::uuid),('00000000-0000-0000-0000-00000000a319'::uuid)) v(id);
  insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active)
  select id,t_a,o_a,f_a,true from (values ('00000000-0000-0000-0000-00000000a311'::uuid),('00000000-0000-0000-0000-00000000a312'::uuid),('00000000-0000-0000-0000-00000000a313'::uuid),('00000000-0000-0000-0000-00000000a314'::uuid),('00000000-0000-0000-0000-00000000a315'::uuid),('00000000-0000-0000-0000-00000000a316'::uuid),('00000000-0000-0000-0000-00000000a317'::uuid)) v(id);
  insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active) values('00000000-0000-0000-0000-00000000a318',t_a,o_a,f_other,true),('00000000-0000-0000-0000-00000000b311',t_b,o_b,f_b,true),('00000000-0000-0000-0000-00000000a319',t_a,o_a,f_a,false);
  insert into public.roles(id,key,name_ar,name_en,scope_level) values(role_all,'capa_test_all','اختبار كامل','CAPA test all','facility'),(role_view,'capa_test_view','اختبار عرض','CAPA test view','facility'),(role_conf,'capa_test_conf','اختبار سري','CAPA test confidential','facility');
  insert into public.role_permissions(role_id,permission_id) select role_all,id from public.permissions where key like 'capa.%';
  insert into public.role_permissions(role_id,permission_id) select role_view,id from public.permissions where key='capa.view';
  insert into public.role_permissions(role_id,permission_id) select role_conf,id from public.permissions where key in ('capa.view','capa.view_confidential','capa.view_history');
  insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id)
  select id,role_all,t_a,o_a,f_a from (values ('00000000-0000-0000-0000-00000000a311'::uuid),('00000000-0000-0000-0000-00000000a312'::uuid),('00000000-0000-0000-0000-00000000a313'::uuid),('00000000-0000-0000-0000-00000000a314'::uuid),('00000000-0000-0000-0000-00000000a315'::uuid)) v(id);
  insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id) values('00000000-0000-0000-0000-00000000a316',role_view,t_a,o_a,f_a),('00000000-0000-0000-0000-00000000a317',role_conf,t_a,o_a,f_a),('00000000-0000-0000-0000-00000000a318',role_view,t_a,o_a,f_other),('00000000-0000-0000-0000-00000000b311',role_view,t_b,o_b,f_b);
end $$;

-- Lifecycle: owner creates and submits; reviewer and approver are distinct real identities.
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a311',true);
select public.create_capa('00000000-0000-0000-0000-00000000a301','00000000-0000-0000-0000-00000000a302','00000000-0000-0000-0000-00000000a303','اختبار دورة','Lifecycle','وصف فعلي','Actual description','00000000-0000-0000-0000-00000000a311','manual','manual',null) as capa_main \gset
select public.capa_test_expect_failure(format('select public.transition_capa(%L::uuid,''approved'',null)',:'capa_main'),'CAPA lifecycle transition denied');
select public.capa_test_expect_failure(format('update public.capa_records set status=''approved'' where id=%L::uuid',:'capa_main'),'permission denied');
select public.configure_capa_for_review(:'capa_main','00000000-0000-0000-0000-00000000a312','00000000-0000-0000-0000-00000000a313',current_date+30,'00000000-0000-0000-0000-00000000a350','effectiveness criteria');
select public.update_capa_plan(:'capa_main','root cause','corrective action',null,'closure decision');
select public.transition_capa(:'capa_main','submitted',null);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a312',true);
select public.transition_capa(:'capa_main','under_review',null);
select public.record_capa_root_cause(:'capa_main','problem','root cause','conclusion',array['00000000-0000-0000-0000-00000000a311'::uuid]);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a313',true);
select public.transition_capa(:'capa_main','approved',null);
select public.create_capa_action(:'capa_main','إجراء','Action','00000000-0000-0000-0000-00000000a314',current_date+7,true) as action_main \gset
select public.reassign_capa_action(:'action_main','00000000-0000-0000-0000-00000000a314','00000000-0000-0000-0000-00000000a315','verification required');
select public.transition_capa(:'capa_main','in_progress',null);

-- Closure gates are exercised against the same record, before prerequisites are supplied.
select public.capa_test_expect_failure(format('select public.transition_capa(%L::uuid,''completed'',null)',:'capa_main'),'CAPA lifecycle transition denied');
select public.request_capa_due_date_extension(:'capa_main',null,current_date+45,'controlled extension') as extension_main \gset
select public.capa_test_expect_failure(format('select public.transition_capa(%L::uuid,''completed'',null)',:'capa_main'),'CAPA lifecycle transition denied');
select public.capa_test_expect_failure(format('select public.decide_capa_due_date_extension(%L::uuid,true,null)',:'extension_main'),'CAPA due-date extension decision denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a312',true);
select public.decide_capa_due_date_extension(:'extension_main',false,'not justified');
reset role;

-- Action owner cannot complete evidence-required work without trusted evidence.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a314',true);
select public.transition_capa_action(:'action_main','in_progress',null);
select public.transition_capa_action(:'action_main','pending_evidence',null);
select public.capa_test_expect_failure(format('select public.transition_capa_action(%L::uuid,''pending_verification'',null)',:'action_main'),'CAPA action transition denied');
select public.authorize_capa_evidence_upload(:'capa_main',:'action_main','evidence.pdf',10,repeat('a',64)) as upload_main \gset
select public.capa_test_expect_failure(format('select public.finalize_capa_evidence_verified(%L::uuid,''application/pdf'')',:'upload_main'),'permission denied');
reset role;

-- Simulate only the trusted scanner/object writer, then finalization as service role.
update public.capa_upload_authorizations set checksum_verification_status='verified',malware_scan_status='accepted' where id=:'upload_main';
insert into storage.objects(bucket_id,name,owner,metadata) select 'capa-evidence',storage_key,'00000000-0000-0000-0000-00000000a314','{"size":10}'::jsonb from public.capa_upload_authorizations where id=:'upload_main';
select set_config('request.jwt.claim.role','service_role',true),set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a314',true);
select public.finalize_capa_evidence_verified(:'upload_main','application/pdf') as evidence_main \gset
select public.capa_test_assert(exists(select 1 from public.capa_evidence where id=:'evidence_main' and scan_status='accepted'),'trusted evidence finalization');
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a314',true);
select public.transition_capa_action(:'action_main','pending_verification',null);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a315',true);
select public.transition_capa_action(:'action_main','completed',null);
select public.transition_capa(:'capa_main','pending_effectiveness_review',null);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a312',true);
select public.record_capa_effectiveness(:'capa_main','ineffective','failed effectiveness',true) as ineffective_review \gset
reset role;
select public.capa_test_assert((select status='reopened' from public.capa_records where id=:'capa_main'),'ineffective review atomically reopens CAPA');
select public.capa_test_assert(exists(select 1 from public.capa_effectiveness_reviews where id=:'ineffective_review'),'ineffective review is appended');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a312',true);
select public.capa_test_expect_failure(format('update public.capa_effectiveness_reviews set result=''effective'' where id=%L::uuid',:'ineffective_review'),'permission denied');
select public.capa_test_expect_failure(format('delete from public.capa_effectiveness_reviews where id=%L::uuid',:'ineffective_review'),'permission denied');
reset role;

-- Fixture records provide an RLS-only view test across tenant, facility and confidentiality.
select set_config('app.capa_controlled','on',true);
insert into public.capa_records(id,tenant_id,organization_id,facility_id,capa_number,title_en,description_en,owner_id,created_by,updated_by,confidentiality_level) values
 ('00000000-0000-0000-0000-00000000a360','00000000-0000-0000-0000-00000000a301','00000000-0000-0000-0000-00000000a302','00000000-0000-0000-0000-00000000a303','CAPA-RLS-001','Confidential','RLS','00000000-0000-0000-0000-00000000a311','00000000-0000-0000-0000-00000000a311','00000000-0000-0000-0000-00000000a311','confidential'),
 ('00000000-0000-0000-0000-00000000a361','00000000-0000-0000-0000-00000000a301','00000000-0000-0000-0000-00000000a302','00000000-0000-0000-0000-00000000a303','CAPA-RLS-002','Assigned','RLS','00000000-0000-0000-0000-00000000a311','00000000-0000-0000-0000-00000000a311','00000000-0000-0000-0000-00000000a311','normal');
insert into public.capa_sources(capa_id,tenant_id,organization_id,facility_id,source_module,source_record_type,created_by) values('00000000-0000-0000-0000-00000000a360','00000000-0000-0000-0000-00000000a301','00000000-0000-0000-0000-00000000a302','00000000-0000-0000-0000-00000000a303','manual','manual','00000000-0000-0000-0000-00000000a311');
insert into public.capa_assignments(capa_id,tenant_id,organization_id,facility_id,user_id,created_by) values('00000000-0000-0000-0000-00000000a361','00000000-0000-0000-0000-00000000a301','00000000-0000-0000-0000-00000000a302','00000000-0000-0000-0000-00000000a303','00000000-0000-0000-0000-00000000a316','00000000-0000-0000-0000-00000000a311');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000b311',true);
select public.capa_test_assert((select count(*)=0 from public.capa_records where tenant_id='00000000-0000-0000-0000-00000000a301'),'tenant B sees zero tenant A CAPAs');
select public.capa_test_assert((select count(*)=0 from public.capa_actions),'tenant B sees zero CAPA actions');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a318',true);
select public.capa_test_assert((select count(*)=0 from public.capa_records where facility_id='00000000-0000-0000-0000-00000000a303'),'other facility sees zero CAPAs');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000a316',true);
select public.capa_test_assert((select count(*)=0 from public.capa_records where id='00000000-0000-0000-0000-00000000a360'),'same facility without confidential permission sees zero confidential CAPAs');
select public.capa_test_assert((select count(*)=1 from public.capa_records where id='00000000-0000-0000-0000-00000000a361'),'assigned user sees only assigned CAPA');
select public.capa_test_expect_failure('insert into public.capa_comments(capa_id,tenant_id,organization_id,facility_id,body,created_by) values (''00000000-0000-0000-0000-00000000a361'',''00000000-0000-0000-0000-00000000a301'',''00000000-0000-0000-0000-00000000a302'',''00000000-0000-0000-0000-00000000a303'',''direct write'',''00000000-0000-0000-0000-00000000a316'')','permission denied');
reset role;

-- Trigger-level integrity does not rely on UI/RLS: cross-tenant, inactive and immutable child scope all fail.
select public.capa_test_expect_failure('insert into public.capa_assignments(capa_id,tenant_id,organization_id,facility_id,user_id,created_by) values (''00000000-0000-0000-0000-00000000a361'',''00000000-0000-0000-0000-00000000a301'',''00000000-0000-0000-0000-00000000a302'',''00000000-0000-0000-0000-00000000a303'',''00000000-0000-0000-0000-00000000b311'',''00000000-0000-0000-0000-00000000a311'')','CAPA assignment outside scope');
select public.capa_test_expect_failure('insert into public.capa_assignments(capa_id,tenant_id,organization_id,facility_id,user_id,created_by) values (''00000000-0000-0000-0000-00000000a361'',''00000000-0000-0000-0000-00000000a301'',''00000000-0000-0000-0000-00000000a302'',''00000000-0000-0000-0000-00000000a303'',''00000000-0000-0000-0000-00000000a319'',''00000000-0000-0000-0000-00000000a311'')','CAPA assignment outside scope');
select public.capa_test_expect_failure('update public.capa_sources set capa_id=''00000000-0000-0000-0000-00000000a361'' where capa_id=''00000000-0000-0000-0000-00000000a360''','CAPA child scope is immutable');
select public.capa_test_assert(exists(select 1 from public.capa_events where capa_id=:'capa_main') and exists(select 1 from public.audit_events where entity_id=:'capa_main'),'controlled lifecycle writes CAPA and platform audit events');

\echo 'PASS: CAPA behavioural lifecycle, closure gates, trusted evidence, RLS identities, scope integrity and audit tests'
rollback;
