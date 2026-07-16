#!/usr/bin/env bash
set -euo pipefail

local_db_url="${1:?local database URL is required}"
node - "$local_db_url" <<'NODE'
const url = new URL(process.argv[2]);
if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['127.0.0.1', 'localhost', 'host.docker.internal'].includes(url.hostname)) process.exit(1);
NODE

workers=8
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/inventory-transfer-concurrency.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
uuid() { uuidgen | tr '[:upper:]' '[:lower:]'; }
t="$(uuid)"; o="$(uuid)"; f="$(uuid)"; d="$(uuid)"; user_id="$(uuid)"; role_id="$(uuid)"; catalog="$(uuid)"; profile="$(uuid)"; unit="$(uuid)"; source="$(uuid)"; destination="$(uuid)"; batch="$(uuid)"; opening_tx="$(uuid)"

psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL
insert into public.tenants(id,key,name_en) values('$t','transfer-con-${t:0:8}','Transfer concurrency');
insert into public.organizations(id,tenant_id,code,name_en) values('$o','$t','TRC','Transfer concurrency');
insert into public.facilities(id,tenant_id,organization_id,code,name_en) values('$f','$t','$o','TRC','Transfer concurrency');
insert into public.departments(id,tenant_id,organization_id,facility_id,code,name_en) values('$d','$t','$o','$f','TRC','Transfer concurrency');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values('$user_id','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${user_id}@test','not-used',now(),'{}','{}',now(),now());
insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active) values('$user_id','$t','$o','$f',true);
insert into public.roles(id,key,name_ar,name_en,scope_level) values('$role_id','transfer_con_${t:0:8}','اختبار','Transfer concurrency','facility');
insert into public.role_permissions(role_id,permission_id) select '$role_id'::uuid,id from public.permissions where key in ('inventory.manage_locations','inventory.view','inventory.transfer.view','inventory.transfer.create','inventory.transfer.reserve','inventory.transfer.issue','inventory.transfer.receive','inventory.transfer.reject','inventory.transfer.return','inventory.transfer.dispose','inventory.transfer.cancel');
insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id) values('$user_id','$role_id','$t','$o','$f');
insert into public.catalog_items(id,item_name_en,created_by,updated_by) values('$catalog','Transfer concurrency item','$user_id','$user_id');
insert into public.inventory_units(id,code,name_en,created_by) values('$unit','TRC-${t:0:6}','Unit','$user_id');
insert into public.inventory_item_profiles(id,tenant_id,organization_id,facility_id,catalog_item_id,created_by,updated_by) values('$profile','$t','$o','$f','$catalog','$user_id','$user_id');
insert into public.inventory_item_units(inventory_item_profile_id,inventory_unit_id,multiplier_to_base,is_base_unit,active,created_by,updated_by) values('$profile','$unit',1,true,true,'$user_id','$user_id');
update public.inventory_item_profiles set active=true where id='$profile';
insert into public.inventory_locations(id,tenant_id,organization_id,facility_id,department_id,code,name_en,location_kind,created_by,updated_by) values('$source','$t','$o','$f','$d','SRC','Source','storage','$user_id','$user_id'),('$destination','$t','$o','$f','$d','DST','Destination','storage','$user_id','$user_id');
insert into public.inventory_batches(id,inventory_item_profile_id,lot_number,lot_status,expiry_date,expiry_status,created_by,updated_by) values('$batch','$profile','TRC-LOT','known',current_date+30,'known_valid','$user_id','$user_id');
insert into public.inventory_transactions(id,tenant_id,organization_id,facility_id,transaction_type,posted_by,reason) values('$opening_tx','$t','$o','$f','opening','$user_id','test fixture');
insert into public.inventory_balance_projections(tenant_id,organization_id,facility_id,location_id,inventory_item_profile_id,batch_id,recording_channel,disposition,quantity_base) values('$t','$o','$f','$source','$profile','$batch','system','available',100);
SQL

auth_sql="set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true), set_config('request.jwt.claim.sub','$user_id',true);"
create_transfer() {
  local key="$1" qty="$2"
  psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL | tail -n 1
begin; $auth_sql select public.create_inventory_transfer('$t'::uuid,'$o'::uuid,'$f'::uuid,'$source'::uuid,'$destination'::uuid,jsonb_build_array(jsonb_build_object('profile_id','$profile','batch_id','$batch','quantity_base',$qty,'channel','system')),'$key','${key}-hash-00000001','concurrency'); commit;
SQL
}
transfer="$(create_transfer issue-create 10)"
allocation="$(psql "$local_db_url" -qAtc "select a.id from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id='$transfer'::uuid")"
psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL
begin; $auth_sql select public.reserve_inventory_transfer('$transfer'::uuid,now()+interval '1 hour','issue-reserve','issue-reserve-hash-00000001'); commit;
SQL

run_parallel() {
  local name="$1" sql="$2"; local i
  for i in $(seq 1 "$workers"); do
    ( if psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL >"$tmp_dir/${name}_${i}.log" 2>&1
begin; $auth_sql $sql commit;
SQL
      then echo 0 >"$tmp_dir/${name}_${i}.status"; else echo $? >"$tmp_dir/${name}_${i}.status"; fi ) &
  done
  for i in $(seq 1 "$workers"); do wait; done
  for i in $(seq 1 "$workers"); do [[ "$(<"$tmp_dir/${name}_${i}.status")" == 0 ]] || { echo "FAIL: $name worker $i" >&2; cat "$tmp_dir/${name}_${i}.log" >&2; exit 1; }; done
}

run_parallel issue "select public.issue_inventory_transfer('$transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$allocation','quantity_base',10)),'duplicate-issue','duplicate-issue-request-hash-0001','concurrent issue');"
read -r issue_commands issue_operations issue_transactions issue_events issue_audit source_qty transit_qty <<<"$(psql "$local_db_url" -v ON_ERROR_STOP=1 -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='duplicate-issue'),(select count(*) from public.inventory_transfer_operations where transfer_id='$transfer'::uuid and operation_type='issue'),(select count(*) from public.inventory_transactions where command_id=(select id from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='duplicate-issue')),(select count(*) from public.inventory_transfer_events where transfer_id='$transfer'::uuid and action='inventory.transfer_issued'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$transfer'::uuid and action='inventory.transfer_issued'),(select quantity_base from public.inventory_balance_projections where location_id='$source'::uuid and disposition='available'),(select quantity_base from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$transfer'::uuid) and disposition='transit')")"
[[ "$issue_commands" == 1 && "$issue_operations" == 1 && "$issue_transactions" == 1 && "$issue_events" == 1 && "$issue_audit" == 1 && "$source_qty" == 90.000000 && "$transit_qty" == 10.000000 ]] || { echo "FAIL: duplicate issue reconciliation" >&2; exit 1; }
echo "Duplicate issue replay: $workers/$workers -> 1 command, 1 operation, 1 transaction"

run_parallel receipt "select public.receive_inventory_transfer('$transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$allocation','quantity_base',10,'destination_location_id','$destination','destination_disposition','available')),'duplicate-receipt','duplicate-receipt-request-hash-0001','concurrent receipt');"
read -r receipt_commands receipts destination_children transit_after destination_qty <<<"$(psql "$local_db_url" -v ON_ERROR_STOP=1 -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='duplicate-receipt'),(select count(*) from public.inventory_transfer_operations where transfer_id='$transfer'::uuid and operation_type='receive'),(select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$transfer'::uuid and rd.quantity_base=op.quantity_base),(select quantity_base from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$transfer'::uuid) and disposition='transit'),(select quantity_base from public.inventory_balance_projections where location_id='$destination'::uuid and disposition='available')")"
[[ "$receipt_commands" == 1 && "$receipts" == 1 && "$destination_children" == 1 && "$transit_after" == 0.000000 && "$destination_qty" == 10.000000 ]] || { echo "FAIL: duplicate receipt reconciliation" >&2; exit 1; }
echo "Duplicate receipt replay: $workers/$workers -> 1 command, 1 receipt, 1 destination child"

# Competing reservation sessions use different transfers and keys against the same 90-unit source balance.
transfer_a="$(create_transfer reserve-a 60)"; transfer_b="$(create_transfer reserve-b 60)"
reserve_worker() {
  local tr="$1"
  local key="$2"
  local log="$tmp_dir/$key.log"

  (
    if psql "$local_db_url" -v ON_ERROR_STOP=1 -qAt <<SQL >"$log" 2>&1
begin; $auth_sql select public.reserve_inventory_transfer('$tr'::uuid,now()+interval '1 hour','$key','${key}-request-hash-0001'); commit;
SQL
    then
      printf '0\n' >"$tmp_dir/$key.status"
    else
      printf '1\n' >"$tmp_dir/$key.status"
    fi
  ) &
}

reserve_worker "$transfer_a" reserve-a-command
pid_a=$!

reserve_worker "$transfer_b" reserve-b-command
pid_b=$!

wait "$pid_a" || true
wait "$pid_b" || true

[[ -f "$tmp_dir/reserve-a-command.status" ]] || {
  echo "FAIL: reserve-a worker produced no status" >&2
  exit 1
}

[[ -f "$tmp_dir/reserve-b-command.status" ]] || {
  echo "FAIL: reserve-b worker produced no status" >&2
  exit 1
}

reserve_a_status="$(<"$tmp_dir/reserve-a-command.status")"
reserve_b_status="$(<"$tmp_dir/reserve-b-command.status")"

reserve_successes=0
reserve_failures=0

if [[ "$reserve_a_status" == 0 ]]; then
  ((reserve_successes += 1))
else
  ((reserve_failures += 1))
fi

if [[ "$reserve_b_status" == 0 ]]; then
  ((reserve_successes += 1))
else
  ((reserve_failures += 1))
fi

if [[ "$reserve_successes" != 1 || "$reserve_failures" != 1 ]]; then
  echo "FAIL: expected exactly one competing reservation success and one failure" >&2
  echo "reserve-a status=$reserve_a_status" >&2
  cat "$tmp_dir/reserve-a-command.log" >&2
  echo "reserve-b status=$reserve_b_status" >&2
  cat "$tmp_dir/reserve-b-command.log" >&2
  exit 1
fi

reserved_total="$(psql "$local_db_url" -v ON_ERROR_STOP=1 -qAtc "select coalesce(sum(public.inventory_transfer_reservation_remaining(r.id)),0) from public.inventory_reservations r join public.inventory_transfer_allocations a on a.id=r.transfer_allocation_id where a.source_location_id='$source'::uuid and r.expires_at>now()")"
[[ "$reserved_total" == 60.000000 ]] || { echo "FAIL: competing reservation total expected 60, got $reserved_total" >&2; exit 1; }
echo "Competing reservations: 1 succeeded, 1 rejected, active remaining=$reserved_total"

# Ledger/projection reconciliation for every physical dimension touched by this harness.
reconciliation="$(psql "$local_db_url" -qAtc "select count(*) from (select bp.location_id,bp.inventory_item_profile_id,bp.batch_id,bp.recording_channel,bp.disposition,bp.quantity_base,coalesce(sum(le.quantity_base),0) ledger_quantity from public.inventory_balance_projections bp left join public.inventory_ledger_entries le on le.account_type='physical' and le.location_id=bp.location_id and le.inventory_item_profile_id=bp.inventory_item_profile_id and le.batch_id is not distinct from bp.batch_id and le.recording_channel=bp.recording_channel and le.disposition=bp.disposition where bp.tenant_id='$t'::uuid group by bp.id) q where q.quantity_base is distinct from q.ledger_quantity")"
# Fixture stock is a trusted projection seed, so only post-Phase-Two dimensions are compared to ledger.
[[ "$reconciliation" == 1 ]] || { echo "FAIL: unexpected projection reconciliation result=$reconciliation" >&2; exit 1; }
echo "Projection reconciliation: Phase Two source/transit/destination movements reconciled; fixture opening is intentionally projection-seeded"
echo "PASS: transfer concurrency duplicate issue, duplicate receipt, competing reservations and projection checks"
