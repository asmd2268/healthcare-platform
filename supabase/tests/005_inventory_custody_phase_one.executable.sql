\set ON_ERROR_STOP on
begin;

create function public.inventory_test_assert(p_condition boolean,p_message text) returns void language plpgsql as $$
begin if not p_condition then raise exception 'ASSERT: %',p_message; end if; end $$;
create function public.inventory_test_expect_failure(p_sql text,p_fragment text) returns void language plpgsql as $$
begin begin execute p_sql; exception when others then if position(p_fragment in sqlerrm)=0 then raise; end if; return; end; raise exception 'ASSERT: expected failure (%)',p_fragment; end $$;
grant execute on function public.inventory_test_assert(boolean,text),public.inventory_test_expect_failure(text,text) to authenticated;

do $$
declare t uuid:='11000000-0000-0000-0000-000000000001'; o uuid:='11000000-0000-0000-0000-000000000002'; o_other uuid:='11000000-0000-0000-0000-000000000006'; f uuid:='11000000-0000-0000-0000-000000000003'; f_other uuid:='11000000-0000-0000-0000-000000000004'; d uuid:='11000000-0000-0000-0000-000000000005';
  requester uuid:='11000000-0000-0000-0000-000000000011'; approver uuid:='11000000-0000-0000-0000-000000000012'; viewer uuid:='11000000-0000-0000-0000-000000000013'; outsider uuid:='22000000-0000-0000-0000-000000000011';
  r_post uuid:=gen_random_uuid(); r_approve uuid:=gen_random_uuid(); r_view uuid:=gen_random_uuid(); catalog uuid:='11000000-0000-0000-0000-000000000021'; controlled_catalog uuid:='11000000-0000-0000-0000-000000000030'; profile uuid:='11000000-0000-0000-0000-000000000022'; controlled_profile uuid:='11000000-0000-0000-0000-000000000023'; unit uuid:='11000000-0000-0000-0000-000000000024'; unit_two uuid:='11000000-0000-0000-0000-000000000029'; location uuid:='11000000-0000-0000-0000-000000000025'; confidential_location uuid:='11000000-0000-0000-0000-000000000026'; known_batch uuid:='11000000-0000-0000-0000-000000000027'; pending_batch uuid:='11000000-0000-0000-0000-000000000028'; expired_batch uuid:='11000000-0000-0000-0000-000000000031';
begin
 insert into public.tenants(id,key,name_en) values(t,'inventory-test','Inventory Test');
 insert into public.organizations(id,tenant_id,code,name_en) values(o,t,'INV','Inventory Org'),(o_other,t,'OTHER','Other Org');
 insert into public.facilities(id,tenant_id,organization_id,code,name_en) values(f,t,o,'INV','Inventory Facility'),(f_other,t,o_other,'OTHER','Other Facility');
 insert into public.departments(id,tenant_id,organization_id,facility_id,code,name_en) values(d,t,o,f,'PHARM','Pharmacy');
 insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 select x,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x::text||'@inventory.test','not-used',now(),'{}','{}',now(),now() from unnest(array[requester,approver,viewer,outsider]) x;
 insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active) values(requester,t,o,f,true),(approver,t,o,f,true),(viewer,t,o,f,true),(outsider,t,o_other,f_other,true);
 insert into public.roles(id,key,name_ar,name_en,scope_level) values(r_post,'inventory_test_post','اختبار إدخال','Inventory post test','facility'),(r_approve,'inventory_test_approve','اختبار اعتماد','Inventory approve test','facility'),(r_view,'inventory_test_view','اختبار عرض','Inventory view test','facility');
 insert into public.role_permissions(role_id,permission_id) select r_post,id from public.permissions where key in ('inventory.manage_catalog','inventory.manage_locations','inventory.post_opening','inventory.view');
 insert into public.role_permissions(role_id,permission_id) select r_approve,id from public.permissions where key in ('inventory.approve_opening','inventory.reverse','inventory.view','inventory.manage_catalog');
 insert into public.role_permissions(role_id,permission_id) select r_view,id from public.permissions where key='inventory.view';
 insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id) values(requester,r_post,t,o,f),(approver,r_approve,t,o,f),(viewer,r_view,t,o,f),(outsider,r_view,t,o_other,f_other);
 insert into public.catalog_items(id,item_name_en,default_controlled_classification,created_by,updated_by) values(catalog,'Test item','standard',requester,requester),(controlled_catalog,'Controlled test item','controlled',requester,requester);
 insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,authority,authoritative,created_by) values(catalog,'nupco','NUPCO-INV-001','NUPCO-INV-001','NUPCO',true,requester);
 insert into public.inventory_units(id,code,name_en,created_by) values(unit,'TAB','Tablet',requester),(unit_two,'BOX','Box',requester);
 insert into public.inventory_item_profiles(id,tenant_id,organization_id,facility_id,catalog_item_id,operational_controlled_classification,created_by,updated_by) values(profile,t,o,f,catalog,'standard',requester,requester),(controlled_profile,t,o,f,controlled_catalog,'controlled',requester,requester);
 insert into public.inventory_item_units(inventory_item_profile_id,inventory_unit_id,multiplier_to_base,is_base_unit,active,created_by,updated_by) values(profile,unit,1,true,true,requester,requester),(controlled_profile,unit,1,true,true,requester,requester);
 insert into public.inventory_locations(id,tenant_id,organization_id,facility_id,department_id,code,name_en,location_kind,confidential,created_by,updated_by) values(location,t,o,f,d,'MAIN','Main store','storage',false,requester,requester),(confidential_location,t,o,f,d,'CONF','Confidential store','storage',true,requester,requester);
 insert into public.inventory_batches(id,inventory_item_profile_id,lot_number,lot_status,expiry_date,expiry_status,created_by,updated_by) values(known_batch,profile,'LOT-001','known',current_date+30,'known_valid',requester,requester),(pending_batch,controlled_profile,null,'pending',null,'pending',requester,requester),(expired_batch,profile,'LOT-EXPIRED','known',current_date-1,'expired',requester,requester);
end $$;
select id as standard_item_unit from public.inventory_item_units where inventory_item_profile_id='11000000-0000-0000-0000-000000000022' and is_base_unit \gset
select id as controlled_item_unit from public.inventory_item_units where inventory_item_profile_id='11000000-0000-0000-0000-000000000023' and is_base_unit \gset

-- Deferred active-profile invariant: setup-incomplete rows may exist, but no
-- active profile can commit until exactly one active base unit exists.
insert into public.catalog_items(id,item_name_en,created_by,updated_by) values('11000000-0000-0000-0000-000000000032','Invariant item','11000000-0000-0000-0000-000000000011','11000000-0000-0000-0000-000000000011');
select public.inventory_test_expect_failure($$insert into public.inventory_item_profiles(id,tenant_id,organization_id,facility_id,catalog_item_id,active,created_by,updated_by) values('11000000-0000-0000-0000-000000000033','11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000032',true,'11000000-0000-0000-0000-000000000011','11000000-0000-0000-0000-000000000011'); set constraints all immediate$$,'exactly one active base unit');
insert into public.inventory_item_profiles(id,tenant_id,organization_id,facility_id,catalog_item_id,active,created_by,updated_by) values('11000000-0000-0000-0000-000000000034','11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000032',false,'11000000-0000-0000-0000-000000000011','11000000-0000-0000-0000-000000000011');
select public.inventory_test_expect_failure($$update public.inventory_item_profiles set active=true where id='11000000-0000-0000-0000-000000000034'; set constraints all immediate$$,'exactly one active base unit');
insert into public.inventory_item_units(inventory_item_profile_id,inventory_unit_id,multiplier_to_base,is_base_unit,active,created_by,updated_by) values('11000000-0000-0000-0000-000000000034','11000000-0000-0000-0000-000000000024',1,true,true,'11000000-0000-0000-0000-000000000011','11000000-0000-0000-0000-000000000011');
update public.inventory_item_profiles set active=true where id='11000000-0000-0000-0000-000000000034'; set constraints all immediate;
select public.inventory_test_assert((select active from public.inventory_item_profiles where id='11000000-0000-0000-0000-000000000034'),'profile activates with one base unit');
select public.inventory_test_expect_failure($$delete from public.inventory_item_units where inventory_item_profile_id='11000000-0000-0000-0000-000000000034'; set constraints all immediate$$,'exactly one active base unit');
select public.inventory_test_expect_failure($$update public.inventory_item_units set active=false where inventory_item_profile_id='11000000-0000-0000-0000-000000000034'; set constraints all immediate$$,'exactly one active base unit');

-- Database, not caller, controls identifier normalization and authority/context rules.
insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,authority,authoritative) values('11000000-0000-0000-0000-000000000032','moh','  ab c  ','FORGED',' moh ',true);
select public.inventory_test_assert((select normalized_identifier_value='AB C' and authority='MOH' from public.catalog_item_identifiers where catalog_item_id='11000000-0000-0000-0000-000000000032' and identifier_type='moh'),'identifier and authority are normalized by trigger');
select public.inventory_test_expect_failure($$insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,authority,authoritative) values('11000000-0000-0000-0000-000000000021','moh','AB C','BYPASS','moh',true)$$,'duplicate key');
select public.inventory_test_expect_failure($$insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,authoritative) values('11000000-0000-0000-0000-000000000021','moh','missing authority','FORGED',true)$$,'check constraint');
select public.inventory_test_expect_failure($$insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,authoritative) values('11000000-0000-0000-0000-000000000021','local','missing context','FORGED',false)$$,'check constraint');
insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,source_context,authoritative) values('11000000-0000-0000-0000-000000000032','local',' repeat ','FORGED',' Context A ',false),('11000000-0000-0000-0000-000000000030','local','REPEAT','FORGED','context-b',false);
select public.inventory_test_assert((select count(*)=2 from public.catalog_item_identifiers where normalized_identifier_value='REPEAT' and source_context in ('context a','context-b')),'distinct normalized non-authoritative contexts are allowed');
select public.inventory_test_expect_failure($$insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,source_context,authoritative) values('11000000-0000-0000-0000-000000000032','local','REPEAT','BYPASS','context a',false)$$,'duplicate key');

-- Database constraints protect scope and identifiers independently from the UI/RLS.
select public.inventory_test_expect_failure($$insert into public.inventory_item_profiles(tenant_id,organization_id,facility_id,catalog_item_id,created_by,updated_by) values('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000004','11000000-0000-0000-0000-000000000021','11000000-0000-0000-0000-000000000011','11000000-0000-0000-0000-000000000011')$$,'facility scope mismatch');
select public.inventory_test_expect_failure($$insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,authority,authoritative) values('11000000-0000-0000-0000-000000000021','nupco',' nupco-inv-001 ','NUPCO-INV-001','NUPCO',true)$$,'duplicate key');
insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,source_context,authoritative) values('11000000-0000-0000-0000-000000000021','local','shared','SHARED','legacy-a',false),('11000000-0000-0000-0000-000000000030','local','shared','SHARED','legacy-b',false);
select public.inventory_test_expect_failure($$insert into public.catalog_item_identifiers(catalog_item_id,identifier_type,identifier_value,normalized_identifier_value,source_context,authoritative) values('11000000-0000-0000-0000-000000000021','local',' shared ','SHARED','legacy-a',false)$$,'duplicate key');
select public.inventory_test_expect_failure($$insert into public.inventory_item_units(inventory_item_profile_id,inventory_unit_id,multiplier_to_base,is_base_unit,active) values('11000000-0000-0000-0000-000000000022','11000000-0000-0000-0000-000000000029',1,true,true)$$,'duplicate key');
select public.inventory_test_expect_failure($$insert into public.inventory_locations(tenant_id,organization_id,facility_id,parent_location_id,code,name_en,location_kind,created_by,updated_by) values('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000004','11000000-0000-0000-0000-000000000025','CROSS','Cross','storage','11000000-0000-0000-0000-000000000011','11000000-0000-0000-0000-000000000011')$$,'facility scope mismatch');

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000011',true);
-- No direct writes: protected transit and expiry mutation are inaccessible to clients.
select public.inventory_test_expect_failure($$insert into public.inventory_locations(tenant_id,organization_id,facility_id,code,name_en,location_kind,protected_transit,created_by,updated_by) values('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000003','T','Transit','transit',true,'11000000-0000-0000-0000-000000000011','11000000-0000-0000-0000-000000000011')$$,'permission denied');
select public.inventory_test_expect_failure($$update public.inventory_batches set expiry_date=current_date+1 where id='11000000-0000-0000-0000-000000000028'$$,'permission denied');
select public.complete_inventory_batch_expiry('expiry-complete-1','expiry-complete-hash-0001','11000000-0000-0000-0000-000000000028',current_date+40,'known_valid','expiry confirmed') as expiry_transaction \gset
select public.complete_inventory_batch_expiry('expiry-complete-1','expiry-complete-hash-0001','11000000-0000-0000-0000-000000000028',current_date+40,'known_valid','expiry confirmed') as expiry_replay \gset
select public.inventory_test_assert(:'expiry_transaction'::uuid=:'expiry_replay'::uuid,'expiry completion is idempotent');
select public.inventory_test_expect_failure($$select public.complete_inventory_batch_expiry('expiry-complete-1','expiry-complete-other-hash','11000000-0000-0000-0000-000000000028',current_date+40,'known_valid','expiry confirmed')$$,'different request');
select public.inventory_test_assert((select expiry_status='known_valid' from public.inventory_batches where id='11000000-0000-0000-0000-000000000028'),'controlled expiry completion succeeds');
select public.inventory_test_assert((select expiry_status='expired' and expiry_date is not null from public.inventory_batches where id='11000000-0000-0000-0000-000000000031'),'expired batch accepts a non-null expiry date');
reset role;
select public.inventory_test_assert(exists(select 1 from public.inventory_events where transaction_id=:'expiry_transaction' and action='inventory.batch_expiry_completed') and exists(select 1 from public.audit_events where entity_id=:'expiry_transaction' and action='inventory.batch_expiry_completed'),'expiry completion event and audit are written');
set local role authenticated; select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000011',true);

-- An incomplete controlled lot cannot be posted; a balanced standard opening can.
select public.create_inventory_opening_command('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000003','opening',jsonb_build_array(
 jsonb_build_object('profile_id','11000000-0000-0000-0000-000000000023','batch_id','11000000-0000-0000-0000-000000000028','unit_id',:'controlled_item_unit','channel','system','account_type','physical','location_id','11000000-0000-0000-0000-000000000025','disposition','available','quantity_base',1),
 jsonb_build_object('profile_id','11000000-0000-0000-0000-000000000023','batch_id','11000000-0000-0000-0000-000000000028','unit_id',:'controlled_item_unit','channel','system','account_type','external_control','quantity_base',-1)),'controlled-complete','hash-controlled-complete-0001','controlled test') as controlled_command \gset
select public.submit_inventory_command(:'controlled_command');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000012',true);
select public.inventory_test_expect_failure(format('select public.approve_inventory_command(%L::uuid)',:'controlled_command'),'complete known lot');
reset role;

set local role authenticated; select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000011',true);
select public.create_inventory_opening_command('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000003','opening',jsonb_build_array(
 jsonb_build_object('profile_id','11000000-0000-0000-0000-000000000022','batch_id','11000000-0000-0000-0000-000000000027','unit_id',:'standard_item_unit','channel','system','account_type','physical','location_id','11000000-0000-0000-0000-000000000025','disposition','available','quantity_base',10),
 jsonb_build_object('profile_id','11000000-0000-0000-0000-000000000022','batch_id','11000000-0000-0000-0000-000000000027','unit_id',:'standard_item_unit','channel','system','account_type','external_control','quantity_base',-10)),'opening-1','hash-opening-000001','opening stock') as opening_command \gset
select public.create_inventory_opening_command('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000003','opening',jsonb_build_array(
 jsonb_build_object('profile_id','11000000-0000-0000-0000-000000000022','batch_id','11000000-0000-0000-0000-000000000027','unit_id',:'standard_item_unit','channel','system','account_type','physical','location_id','11000000-0000-0000-0000-000000000025','disposition','available','quantity_base',10),
 jsonb_build_object('profile_id','11000000-0000-0000-0000-000000000022','batch_id','11000000-0000-0000-0000-000000000027','unit_id',:'standard_item_unit','channel','system','account_type','external_control','quantity_base',-10)),'opening-1','hash-opening-000001','opening stock') as ignored \gset
select public.inventory_test_expect_failure($$select public.create_inventory_opening_command('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000003','opening','[]','opening-1','different-hash-0001','opening stock')$$,'different request');
select public.submit_inventory_command(:'opening_command');
reset role; set local role authenticated; select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000012',true);
select public.approve_inventory_command(:'opening_command') as opening_transaction \gset
reset role;
select public.inventory_test_assert((select quantity_base=10 from public.inventory_balance_projections where location_id='11000000-0000-0000-0000-000000000025' and inventory_item_profile_id='11000000-0000-0000-0000-000000000022'),'physical projection equals opening');
select public.inventory_test_assert((select count(*)=0 from public.inventory_balance_projections where inventory_item_profile_id='11000000-0000-0000-0000-000000000022' and location_id is null),'external control is absent from projection');
select public.inventory_test_assert((select bool_and(s.q=0) from (select sum(quantity_base) q from public.inventory_ledger_entries where transaction_id=:'opening_transaction' group by inventory_item_profile_id,batch_id,recording_channel,inventory_item_unit_id) s),'transaction balances by item/batch/channel/unit');
set local role authenticated; select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000011',true);
select public.inventory_test_assert((select count(*)=1 from public.inventory_transactions where id=:'opening_transaction'),'inventory.view can see transaction summary');
select public.inventory_test_assert((select count(*)=0 from public.inventory_ledger_entries where transaction_id=:'opening_transaction'),'inventory.view alone cannot see ledger detail');
reset role;

set local role authenticated; select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000012',true);
select public.inventory_test_expect_failure($$select public.reverse_inventory_transaction('11000000-0000-0000-0000-000000000000','reverse-none','hash-reverse-none','')$$,'Inventory reversal denied');
select public.reverse_inventory_transaction(:'opening_transaction','reverse-1','hash-reverse-000001','opening correction') as reversal_transaction \gset
select public.inventory_test_expect_failure(format('select public.reverse_inventory_transaction(%L::uuid,''reverse-2'',''hash-reverse-2'',''again'')',:'opening_transaction'),'Inventory reversal denied');
reset role;
select public.inventory_test_assert((select quantity_base=0 from public.inventory_balance_projections where location_id='11000000-0000-0000-0000-000000000025' and inventory_item_profile_id='11000000-0000-0000-0000-000000000022'),'reversal exactly clears projected stock');
select public.inventory_test_assert((select count(*)=2 from public.inventory_events where transaction_id in (:'opening_transaction',:'reversal_transaction')),'inventory events are appended');
select public.inventory_test_assert((select count(*)=2 from public.audit_events where entity_type='inventory_transaction' and entity_id in (:'opening_transaction',:'reversal_transaction')),'shared audit is appended atomically');

set local role authenticated; select set_config('request.jwt.claim.sub','22000000-0000-0000-0000-000000000011',true);
select public.inventory_test_assert((select count(*)=0 from public.inventory_transactions where id=:'opening_transaction'),'cross-facility transaction visibility is zero');
select public.inventory_test_assert((select count(*)=0 from public.inventory_locations where id='11000000-0000-0000-0000-000000000026'),'confidential location visibility is zero');
select public.inventory_test_expect_failure(format('insert into public.inventory_ledger_entries(transaction_id,inventory_item_profile_id,inventory_item_unit_id,recording_channel,account_type,quantity_base) values(%L::uuid,''11000000-0000-0000-0000-000000000022'',''11000000-0000-0000-0000-000000000024'',''system'',''external_control'',1)',:'opening_transaction'),'permission denied');
select public.inventory_test_expect_failure(format('update public.inventory_transactions set reason=''tamper'' where id=%L::uuid',:'opening_transaction'),'permission denied');
select public.inventory_test_expect_failure(format('delete from public.inventory_transactions where id=%L::uuid',:'opening_transaction'),'permission denied');
select public.inventory_test_expect_failure(format('update public.inventory_ledger_entries set quantity_base=2 where transaction_id=%L::uuid',:'opening_transaction'),'permission denied');
select public.inventory_test_expect_failure(format('delete from public.inventory_ledger_entries where transaction_id=%L::uuid',:'opening_transaction'),'permission denied');
select public.inventory_test_expect_failure(format('insert into public.inventory_events(transaction_id,tenant_id,organization_id,facility_id,actor_id,action) values(%L::uuid,''11000000-0000-0000-0000-000000000001'',''11000000-0000-0000-0000-000000000002'',''11000000-0000-0000-0000-000000000003'',''22000000-0000-0000-0000-000000000011'',''tamper'')',:'opening_transaction'),'permission denied');
select public.inventory_test_expect_failure(format('update public.inventory_balance_projections set quantity_base=99 where inventory_item_profile_id=''11000000-0000-0000-0000-000000000022'''),'permission denied');
select public.inventory_test_expect_failure(format('select public.inventory_post_entries(%L::uuid,''[]''::jsonb,''tamper'', ''{}''::jsonb)',:'opening_transaction'),'permission denied');
reset role;

\echo 'PASS: inventory Phase One catalog, units, locations, batches, RLS, command, ledger, projection, idempotency, reversal and audit tests'
rollback;
