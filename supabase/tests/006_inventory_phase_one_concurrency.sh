#!/usr/bin/env bash
set -euo pipefail

local_db_url="${1:?local database URL is required}"
node - "$local_db_url" <<'NODE'
const url = new URL(process.argv[2]);
if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['127.0.0.1', 'localhost', 'host.docker.internal'].includes(url.hostname)) process.exit(1);
NODE

workers=8
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/inventory-concurrency.XXXXXX")"
t="$(uuidgen | tr '[:upper:]' '[:lower:]')"; o="$(uuidgen | tr '[:upper:]' '[:lower:]')"; f="$(uuidgen | tr '[:upper:]' '[:lower:]')"
requester="$(uuidgen | tr '[:upper:]' '[:lower:]')"; approver="$(uuidgen | tr '[:upper:]' '[:lower:]')"; role_post="$(uuidgen | tr '[:upper:]' '[:lower:]')"; role_approve="$(uuidgen | tr '[:upper:]' '[:lower:]')"
catalog="$(uuidgen | tr '[:upper:]' '[:lower:]')"; profile="$(uuidgen | tr '[:upper:]' '[:lower:]')"; unit="$(uuidgen | tr '[:upper:]' '[:lower:]')"; location="$(uuidgen | tr '[:upper:]' '[:lower:]')"

psql "$local_db_url" -v ON_ERROR_STOP=1 -q <<SQL
insert into public.tenants(id,key,name_en) values('$t','inventory-con-${t:0:8}','Inventory concurrency');
insert into public.organizations(id,tenant_id,code,name_en) values('$o','$t','CON','Concurrency');
insert into public.facilities(id,tenant_id,organization_id,code,name_en) values('$f','$t','$o','CON','Concurrency');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values('$requester','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${requester}@test','not-used',now(),'{}','{}',now(),now()),('$approver','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${approver}@test','not-used',now(),'{}','{}',now(),now());
insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active) values('$requester','$t','$o','$f',true),('$approver','$t','$o','$f',true);
insert into public.roles(id,key,name_ar,name_en,scope_level) values('$role_post','inventory_con_post_${t:0:8}','اختبار','Post','facility'),('$role_approve','inventory_con_approve_${t:0:8}','اختبار','Approve','facility');
insert into public.role_permissions(role_id,permission_id) select '$role_post'::uuid,id from public.permissions where key in ('inventory.post_opening','inventory.view');
insert into public.role_permissions(role_id,permission_id) select '$role_approve'::uuid,id from public.permissions where key in ('inventory.approve_opening','inventory.reverse','inventory.view');
insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id) values('$requester','$role_post','$t','$o','$f'),('$approver','$role_approve','$t','$o','$f');
insert into public.catalog_items(id,item_name_en,created_by,updated_by) values('$catalog','Concurrency item','$requester','$requester');
insert into public.inventory_units(id,code,name_en,created_by) values('$unit','CON-${t:0:6}','Unit','$requester');
insert into public.inventory_item_profiles(id,tenant_id,organization_id,facility_id,catalog_item_id,created_by,updated_by) values('$profile','$t','$o','$f','$catalog','$requester','$requester');
insert into public.inventory_item_units(inventory_item_profile_id,inventory_unit_id,multiplier_to_base,is_base_unit,active,created_by,updated_by) values('$profile','$unit',1,true,true,'$requester','$requester');
insert into public.inventory_locations(id,tenant_id,organization_id,facility_id,code,name_en,location_kind,created_by,updated_by) values('$location','$t','$o','$f','CON','Concurrency','storage','$requester','$requester');
SQL
item_unit="$(psql "$local_db_url" -Atc "select id from public.inventory_item_units where inventory_item_profile_id='$profile'::uuid")"

worker() {
  local i="$1" log="$tmp_dir/$i.log" status="$tmp_dir/$i.status"
  (
    if psql "$local_db_url" -v ON_ERROR_STOP=1 -qAt <<SQL >"$log" 2>&1
begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','$requester',true);
select public.create_inventory_opening_command('$t'::uuid,'$o'::uuid,'$f'::uuid,'opening',jsonb_build_array(jsonb_build_object('profile_id','$profile','unit_id','$item_unit','channel','system','account_type','physical','location_id','$location','disposition','available','quantity_base',10),jsonb_build_object('profile_id','$profile','unit_id','$item_unit','channel','system','account_type','external_control','quantity_base',-10)),'parallel-opening','parallel-opening-request-hash-0001','parallel'); commit;
SQL
    then echo 0 >"$status"; else echo $? >"$status"; fi
  ) &
}
for i in $(seq 1 "$workers"); do worker "$i"; done
wait
failed=0; for i in $(seq 1 "$workers"); do code="$(<"$tmp_dir/$i.status")"; if [[ "$code" != 0 ]]; then echo "FAIL: worker=$i exit_code=$code" >&2; cat "$tmp_dir/$i.log" >&2; failed=1; fi; done; [[ "$failed" == 0 ]] || exit 1
commands="$(psql "$local_db_url" -Atc "select count(*) from public.inventory_commands where tenant_id='$t'::uuid and idempotency_key='parallel-opening'")"; [[ "$commands" == 1 ]] || { echo "FAIL: expected one idempotent command, got $commands" >&2; exit 1; }
command_id="$(psql "$local_db_url" -Atc "select id from public.inventory_commands where tenant_id='$t'::uuid and idempotency_key='parallel-opening'")"
psql "$local_db_url" -v ON_ERROR_STOP=1 -q <<SQL
begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','$requester',true); select public.submit_inventory_command('$command_id'::uuid); commit;
SQL
approval_worker() {
  local i="$1" log="$tmp_dir/approval_$i.log" status="$tmp_dir/approval_$i.status"
  ( if psql "$local_db_url" -v ON_ERROR_STOP=1 -qAt <<SQL >"$log" 2>&1
begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','$approver',true); select public.approve_inventory_command('$command_id'::uuid); commit;
SQL
    then echo 0 >"$status"; else echo $? >"$status"; fi ) &
}
for i in $(seq 1 "$workers"); do approval_worker "$i"; done
wait
for i in $(seq 1 "$workers"); do code="$(<"$tmp_dir/approval_$i.status")"; if [[ "$code" != 0 ]]; then echo "FAIL: approval_worker=$i exit_code=$code" >&2; cat "$tmp_dir/approval_$i.log" >&2; exit 1; fi; done
read -r transactions events audits physical_total <<<"$(psql "$local_db_url" -AtF ' ' -c "select (select count(*) from public.inventory_transactions where command_id='$command_id'::uuid),(select count(*) from public.inventory_events ie join public.inventory_transactions it on it.id=ie.transaction_id where it.command_id='$command_id'::uuid),(select count(*) from public.audit_events ae join public.inventory_transactions it on it.id=ae.entity_id where it.command_id='$command_id'::uuid),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions it on it.id=le.transaction_id where it.command_id='$command_id'::uuid and le.account_type='physical')")"
[[ "$transactions" == 1 && "$events" == 1 && "$audits" == 1 && "$physical_total" == 10.000000 ]] || { echo "FAIL: approval replay transactions=$transactions events=$events audits=$audits physical_total=$physical_total" >&2; exit 1; }
echo "Inventory command concurrency: $workers/$workers replayed to one command"
echo "Inventory posting concurrency: $workers/$workers approvals -> one transaction, event, audit and projection"
