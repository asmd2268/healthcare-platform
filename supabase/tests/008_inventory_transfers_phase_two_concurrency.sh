#!/usr/bin/env bash
set -euo pipefail

local_db_url="${1:?local database URL is required}"
node - "$local_db_url" <<'NODE'
const url = new URL(process.argv[2]);
if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['127.0.0.1', 'localhost', 'host.docker.internal'].includes(url.hostname)) process.exit(1);
NODE

workers=8
scenario_timeout_seconds=30
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/inventory-transfer-concurrency.XXXXXX")"
uuid() { uuidgen | tr '[:upper:]' '[:lower:]'; }
matrix_run_id="$(uuid)"
matrix_application_prefix="inventory-transfer-matrix-${matrix_run_id}"
active_pids=()
cleanup_done=0
barrier_fd_open=0
identity_barrier_fd_open=0

register_pid() { active_pids+=("$1"); }
unregister_pid() {
  local target="$1" pid kept=()
  for pid in "${active_pids[@]:-}"; do [[ -z "$pid" || "$pid" == "$target" ]] || kept+=("$pid"); done
  if (( ${#kept[@]} )); then active_pids=("${kept[@]}"); else active_pids=(); fi
}
terminate_matrix_backends() {
  PGAPPNAME="${matrix_application_prefix}-cleanup" psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
select pg_terminate_backend(pid)
from pg_stat_activity
where application_name like '${matrix_application_prefix}%'
  and pid<>pg_backend_pid();
SQL
}
cleanup() {
  local pid
  (( cleanup_done == 0 )) || return 0
  cleanup_done=1
  if (( barrier_fd_open == 1 )); then exec 3>&- || true; barrier_fd_open=0; fi
  if (( identity_barrier_fd_open == 1 )); then exec 4>&- || true; identity_barrier_fd_open=0; fi
  terminate_matrix_backends
  for pid in "${active_pids[@]:-}"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  for pid in "${active_pids[@]:-}"; do [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true; done
  active_pids=()
  rm -rf "$tmp_dir"
}
trap cleanup EXIT
trap 'cleanup; exit 1' INT TERM
t="$(uuid)"; o="$(uuid)"; f="$(uuid)"; d="$(uuid)"; user_id="$(uuid)"; unauthorized_id="$(uuid)"; approver_id="$(uuid)"; expiry_actor_id="f1000000-0000-0000-0000-000000000001"; expiry_automation_identity_id="$(uuid)"; automation_race_actor_id="$(uuid)"; role_id="$(uuid)"; approver_role_id="$(uuid)"; catalog="$(uuid)"; profile="$(uuid)"; unit="$(uuid)"; catalog_two="$(uuid)"; profile_two="$(uuid)"; unit_two="$(uuid)"; catalog_three="$(uuid)"; profile_three="$(uuid)"; unit_three="$(uuid)"; catalog_four="$(uuid)"; profile_four="$(uuid)"; unit_four="$(uuid)"; source="$(uuid)"; destination="$(uuid)"; batch="$(uuid)"; batch_two="$(uuid)"; batch_three="$(uuid)"; batch_four="$(uuid)"

psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL
insert into public.tenants(id,key,name_en) values('$t','transfer-con-${t:0:8}','Transfer concurrency');
insert into public.organizations(id,tenant_id,code,name_en) values('$o','$t','TRC','Transfer concurrency');
insert into public.facilities(id,tenant_id,organization_id,code,name_en) values('$f','$t','$o','TRC','Transfer concurrency');
insert into public.departments(id,tenant_id,organization_id,facility_id,code,name_en) values('$d','$t','$o','$f','TRC','Transfer concurrency');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('$user_id','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${user_id}@test','not-used',now(),'{}','{}',now(),now()),
('$unauthorized_id','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${unauthorized_id}@test','not-used',now(),'{}','{}',now(),now()),
('$approver_id','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${approver_id}@test','not-used',now(),'{}','{}',now(),now()),
('$expiry_actor_id','00000000-0000-0000-0000-000000000000','authenticated','authenticated','expiry-worker@transfer-concurrency.test','not-used',now(),'{}','{}',now(),now()),
('$automation_race_actor_id','00000000-0000-0000-0000-000000000000','authenticated','authenticated','automation-race-${automation_race_actor_id}@test','not-used',now(),'{}','{}',now(),now())
on conflict (id) do nothing;
insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active) values('$user_id','$t','$o','$f',true),('$unauthorized_id','$t','$o','$f',true),('$approver_id','$t','$o','$f',true) on conflict do nothing;
insert into public.roles(id,key,name_ar,name_en,scope_level) values
('$role_id','transfer_con_${t:0:8}','اختبار','Transfer concurrency','facility'),
('$approver_role_id','transfer_con_approve_${t:0:8}','اعتماد اختبار','Transfer concurrency approver','facility');
insert into public.role_permissions(role_id,permission_id) select '$role_id'::uuid,id from public.permissions where key in ('platform.manage_roles','inventory.manage_locations','inventory.view','inventory.post_opening','inventory.transfer.view','inventory.transfer.create','inventory.transfer.reserve','inventory.transfer.issue','inventory.transfer.receive','inventory.transfer.reject','inventory.transfer.return','inventory.transfer.dispose','inventory.transfer.cancel','inventory.transfer.close_remainder');
insert into public.role_permissions(role_id,permission_id) select '$approver_role_id'::uuid,id from public.permissions where key in ('inventory.approve_opening','inventory.view');
insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id) values('$user_id','$role_id','$t','$o','$f'),('$approver_id','$approver_role_id','$t','$o','$f');
insert into public.automation_identities(id,principal_id,tenant_id,organization_id,facility_id,purpose,display_name,created_by)
values('$expiry_automation_identity_id','$expiry_actor_id','$t','$o','$f','inventory.reservation_expiry','Inventory reservation expiry matrix worker','$user_id');
insert into public.catalog_items(id,item_name_en,created_by,updated_by) values('$catalog','Transfer concurrency item','$user_id','$user_id');
insert into public.inventory_units(id,code,name_en,created_by) values('$unit','TRC-${t:0:6}','Unit','$user_id');
insert into public.inventory_item_profiles(id,tenant_id,organization_id,facility_id,catalog_item_id,created_by,updated_by) values('$profile','$t','$o','$f','$catalog','$user_id','$user_id');
insert into public.inventory_item_units(inventory_item_profile_id,inventory_unit_id,multiplier_to_base,is_base_unit,active,created_by,updated_by) values('$profile','$unit',1,true,true,'$user_id','$user_id');
update public.inventory_item_profiles set active=true where id='$profile';
insert into public.catalog_items(id,item_name_en,created_by,updated_by) values
('$catalog_two','Transfer concurrency item two','$user_id','$user_id'),
('$catalog_three','Transfer concurrency item three','$user_id','$user_id'),
('$catalog_four','Transfer concurrency item four','$user_id','$user_id');
insert into public.inventory_units(id,code,name_en,created_by) values
('$unit_two','TRC2-${t:0:6}','Unit two','$user_id'),
('$unit_three','TRC3-${t:0:6}','Unit three','$user_id'),
('$unit_four','TRC4-${t:0:6}','Unit four','$user_id');
insert into public.inventory_item_profiles(id,tenant_id,organization_id,facility_id,catalog_item_id,created_by,updated_by) values
('$profile_two','$t','$o','$f','$catalog_two','$user_id','$user_id'),
('$profile_three','$t','$o','$f','$catalog_three','$user_id','$user_id'),
('$profile_four','$t','$o','$f','$catalog_four','$user_id','$user_id');
insert into public.inventory_item_units(inventory_item_profile_id,inventory_unit_id,multiplier_to_base,is_base_unit,active,created_by,updated_by) values
('$profile_two','$unit_two',1,true,true,'$user_id','$user_id'),
('$profile_three','$unit_three',1,true,true,'$user_id','$user_id'),
('$profile_four','$unit_four',1,true,true,'$user_id','$user_id');
update public.inventory_item_profiles set active=true where id in ('$profile_two','$profile_three','$profile_four');
insert into public.inventory_locations(id,tenant_id,organization_id,facility_id,department_id,code,name_en,location_kind,created_by,updated_by) values('$source','$t','$o','$f','$d','SRC','Source','storage','$user_id','$user_id'),('$destination','$t','$o','$f','$d','DST','Destination','storage','$user_id','$user_id');
insert into public.inventory_batches(id,inventory_item_profile_id,lot_number,lot_status,expiry_date,expiry_status,created_by,updated_by) values
('$batch','$profile','TRC-LOT','known',current_date+30,'known_valid','$user_id','$user_id'),
('$batch_two','$profile_two','TRC-LOT-2','known',current_date+30,'known_valid','$user_id','$user_id'),
('$batch_three','$profile_three','TRC-LOT-3','known',current_date+30,'known_valid','$user_id','$user_id'),
('$batch_four','$profile_four','TRC-LOT-4','known',current_date+30,'known_valid','$user_id','$user_id');
SQL

auth_sql="set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true), set_config('request.jwt.claim.sub','$user_id',true);"
approver_auth_sql="set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true), set_config('request.jwt.claim.sub','$approver_id',true);"
unauthorized_auth_sql="set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true), set_config('request.jwt.claim.sub','$unauthorized_id',true);"

open_stock() {
  local stock_batch="$1" quantity="$2" key="$3" stock_profile="${4:-$profile}" command
  command="$(psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL | tail -n 1
begin; $auth_sql
select public.create_inventory_opening_command('$t'::uuid,'$o'::uuid,'$f'::uuid,'opening',jsonb_build_array(
  jsonb_build_object('profile_id','$stock_profile','batch_id','$stock_batch','unit_id',(select id from public.inventory_item_units where inventory_item_profile_id='$stock_profile'::uuid and is_base_unit and active),'channel','system','account_type','physical','location_id','$source','disposition','available','quantity_base',$quantity),
  jsonb_build_object('profile_id','$stock_profile','batch_id','$stock_batch','unit_id',(select id from public.inventory_item_units where inventory_item_profile_id='$stock_profile'::uuid and is_base_unit and active),'channel','system','account_type','external_control','quantity_base',-$quantity)
),'opening-$key','opening-$key-hash-00000001','concurrency fixture');
commit;
SQL
)"
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin; $auth_sql select public.submit_inventory_command('$command'::uuid); commit;
SQL
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin; $approver_auth_sql select public.approve_inventory_command('$command'::uuid); commit;
SQL
}
open_stock "$batch" 100 base

create_transfer() {
  local key="$1" qty="$2" stock_batch="${3:-$batch}"
  psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL | tail -n 1
begin; $auth_sql select public.create_inventory_transfer('$t'::uuid,'$o'::uuid,'$f'::uuid,'$source'::uuid,'$destination'::uuid,jsonb_build_array(jsonb_build_object('profile_id','$profile','batch_id','$stock_batch','quantity_base',$qty,'channel','system')),'$key','${key}-hash-00000001','concurrency'); commit;
SQL
}

# Each matrix scenario receives its own batch and ledger-backed opening stock.
# This makes reservations, projections, commands and idempotency keys isolated
# without relying on UUID ordering or the result of a previous scenario.
scenario_batch() {
  local key="$1" stock="$2" stock_profile="${3:-$profile}"
  scenario_batch_id="$(uuid)"
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
insert into public.inventory_batches(id,inventory_item_profile_id,lot_number,lot_status,expiry_date,expiry_status,created_by,updated_by)
values('$scenario_batch_id','$stock_profile','TRC-${key}-${scenario_batch_id:0:8}','known',current_date+30,'known_valid','$user_id','$user_id');
SQL
  open_stock "$scenario_batch_id" "$stock" "scenario-$key" "$stock_profile"
}

make_reserved_transfer() {
  local key="$1" quantity="$2" expiry="${3:-now()+interval '1 hour'}"
  scenario_transfer="$(create_transfer "$key-create" "$quantity" "$scenario_batch_id")"
  scenario_allocation="$(psql "$local_db_url" -qAtc "select a.id from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id='$scenario_transfer'::uuid")"
  scenario_line="$(psql "$local_db_url" -qAtc "select id from public.inventory_transfer_lines where transfer_id='$scenario_transfer'::uuid")"
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin; $auth_sql
select public.reserve_inventory_transfer('$scenario_transfer'::uuid,$expiry,'$key-reserve','$key-reserve-hash-00000001');
commit;
SQL
  scenario_reservation="$(psql "$local_db_url" -qAtc "select id from public.inventory_reservations where transfer_allocation_id='$scenario_allocation'::uuid")"
}

issue_fixture_quantity() {
  local transfer_id="$1" allocation_id="$2" quantity="$3" key="$4"
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin; $auth_sql
select public.issue_inventory_transfer('$transfer_id'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$allocation_id','quantity_base',$quantity)),'$key','$key-hash-00000001','concurrency fixture issue');
commit;
SQL
}

make_issued_resolution_transfer() {
  local key="$1" quantity="$2"
  scenario_batch "$key" "$quantity"
  make_reserved_transfer "$key" "$quantity"
  issue_fixture_quantity "$scenario_transfer" "$scenario_allocation" "$quantity" "$key-public-issue"
  local issued transit remaining status
  read -r issued transit remaining status <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select coalesce(sum(quantity_base),0) from public.inventory_transfer_operations where transfer_id='$scenario_transfer'::uuid and operation_type='issue'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$scenario_transfer'::uuid) and batch_id='$scenario_batch_id'::uuid and recording_channel='system' and disposition='transit'),public.inventory_transfer_reservation_remaining('$scenario_reservation'::uuid),(select status from public.inventory_transfers where id='$scenario_transfer'::uuid)")"
  [[ "$(psql "$local_db_url" -qAtc "select $issued=$quantity and $transit=$quantity and $remaining=0")" == t && "$status" == issued ]] || { echo "FAIL: $key issued resolution fixture is incomplete" >&2; exit 1; }
  assert_transfer_reconciles "$scenario_transfer"
}

make_rejected_resolution_transfer() {
  local key="$1" quantity="$2"
  make_issued_resolution_transfer "$key" "$quantity"
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin; $auth_sql
select public.reject_inventory_transfer('$scenario_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$scenario_allocation','quantity_base',$quantity)),'$key-setup-reject','$key-setup-reject-hash-0001','resolution fixture reject');
commit;
SQL
  local rejected transit
  read -r rejected transit <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$scenario_transfer'::uuid) and batch_id='$scenario_batch_id'::uuid and recording_channel='system' and disposition='returns_hold'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$scenario_transfer'::uuid) and batch_id='$scenario_batch_id'::uuid and recording_channel='system' and disposition='transit')")"
  [[ "$(psql "$local_db_url" -qAtc "select $rejected=$quantity and $transit=0")" == t ]] || { echo "FAIL: $key rejected resolution fixture is incomplete" >&2; exit 1; }
  assert_transfer_reconciles "$scenario_transfer"
}

assert_no_unhandled_db_error() {
  local name="$1"
  local pattern='deadlock detected|duplicate key value|unique_violation|could not serialize|current transaction is aborted|terminating connection|server closed the connection unexpectedly'
  if grep -Ein -- "$pattern" "$tmp_dir/${name}_"*.log >/dev/null 2>&1; then
    echo "FAIL: $name leaked an unhandled database/session error" >&2
    grep -Ein -- "$pattern" "$tmp_dir/${name}_"*.log >&2 || true
    exit 1
  fi
}

wait_for_workers() {
  local name="$1"; shift
  local deadline=$((SECONDS + scenario_timeout_seconds)) pid
  while :; do
    local alive=0
    for pid in "$@"; do kill -0 "$pid" 2>/dev/null && alive=1; done
    (( alive == 0 )) && break
    if (( SECONDS >= deadline )); then
      echo "FAIL: $name timed out after ${scenario_timeout_seconds}s" >&2
      cleanup
      exit 1
    fi
    sleep 0.05
  done
  for pid in "$@"; do wait "$pid" || true; unregister_pid "$pid"; done
}

# A held advisory lock is a deterministic start gate.  Workers run in distinct
# PostgreSQL sessions and must queue on the same transaction advisory lock;
# polling pg_locks confirms they are ready before the holder releases it.
run_pair() {
  local name="$1" left_auth="$2" left_sql="$3" right_auth="$4" right_sql="$5" barrier=$((700000 + RANDOM))
  local deadline=$((SECONDS + scenario_timeout_seconds))
  local fifo="$tmp_dir/${name}.barrier.fifo" holder_pid
  mkfifo "$fifo"
  PGAPPNAME="${matrix_application_prefix}-${name}-holder" psql "$local_db_url" -qAt <"$fifo" >"$tmp_dir/${name}.barrier.log" 2>&1 &
  holder_pid=$!
  register_pid "$holder_pid"
  # macOS ships Bash 3.2, so use a named pipe instead of coproc.
  exec 3>"$fifo"
  barrier_fd_open=1
  printf "begin; select pg_advisory_lock(%s); select 'READY';\n" "$barrier" >&3
  while (( SECONDS < deadline )); do
    grep -qx 'READY' "$tmp_dir/${name}.barrier.log" 2>/dev/null && break
    sleep 0.05
  done
  grep -qx 'READY' "$tmp_dir/${name}.barrier.log" 2>/dev/null || { echo "FAIL: $name barrier holder did not acquire lock before timeout" >&2; cleanup; exit 1; }
  (
    if PGAPPNAME="${matrix_application_prefix}-${name}-left" psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL >"$tmp_dir/${name}_left.log" 2>&1
begin; $left_auth select pg_advisory_xact_lock($barrier); $left_sql commit;
SQL
    then echo 0 >"$tmp_dir/${name}_left.status"; else echo $? >"$tmp_dir/${name}_left.status"; fi
  ) &
  local left_pid=$!
  register_pid "$left_pid"
  (
    if PGAPPNAME="${matrix_application_prefix}-${name}-right" psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL >"$tmp_dir/${name}_right.log" 2>&1
begin; $right_auth select pg_advisory_xact_lock($barrier); $right_sql commit;
SQL
    then echo 0 >"$tmp_dir/${name}_right.status"; else echo $? >"$tmp_dir/${name}_right.status"; fi
  ) &
  local right_pid=$!
  register_pid "$right_pid"
  local queued=0
  while (( SECONDS < deadline )); do
    local queued
    queued="$(psql "$local_db_url" -qAtc "select count(*) from pg_locks where locktype='advisory' and objid=$barrier and not granted")"
    [[ "$queued" == 2 ]] && break
    sleep 0.05
  done
  [[ "$queued" == 2 ]] || { echo "FAIL: $name workers did not reach the start barrier before timeout" >&2; cleanup; exit 1; }
  printf 'select pg_advisory_unlock(%s); commit;\n' "$barrier" >&3
  exec 3>&-
  barrier_fd_open=0
  wait "$holder_pid" || { echo "FAIL: $name barrier holder failed" >&2; cat "$tmp_dir/${name}.barrier.log" >&2; cleanup; exit 1; }
  unregister_pid "$holder_pid"
  wait_for_workers "$name" "$left_pid" "$right_pid"
  pair_left_status="$(<"$tmp_dir/${name}_left.status")"
  pair_right_status="$(<"$tmp_dir/${name}_right.status")"
  assert_no_unhandled_db_error "$name"
}

assert_automation_identity_deactivation_serializes() {
  local fifo="$tmp_dir/automation-identity-deactivation.fifo" holder_pid deactivate_pid deadline
  mkfifo "$fifo"
  PGAPPNAME="${matrix_application_prefix}-automation-identity-holder" psql "$local_db_url" -qAt <"$fifo" >"$tmp_dir/automation_identity_holder.log" 2>&1 &
  holder_pid=$!
  register_pid "$holder_pid"
  exec 4>"$fifo"
  identity_barrier_fd_open=1
  printf "begin; set local role service_role; select public.require_automation_identity('%s'::uuid,'inventory.reservation_expiry','%s'::uuid,'%s'::uuid,'%s'::uuid); select 'READY';\n" "$expiry_actor_id" "$t" "$o" "$f" >&4
  deadline=$((SECONDS + scenario_timeout_seconds))
  while (( SECONDS < deadline )); do
    grep -qx 'READY' "$tmp_dir/automation_identity_holder.log" 2>/dev/null && break
    sleep 0.05
  done
  grep -qx 'READY' "$tmp_dir/automation_identity_holder.log" 2>/dev/null || { echo "FAIL: automation identity holder did not resolve before timeout" >&2; cleanup; exit 1; }
  (
    if PGAPPNAME="${matrix_application_prefix}-automation-identity-deactivate" psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL >"$tmp_dir/automation_identity_deactivate.log" 2>&1
begin; set local role service_role;
select public.deactivate_automation_identity('$expiry_automation_identity_id'::uuid,'$user_id'::uuid,'matrix deactivation');
commit;
SQL
    then echo 0 >"$tmp_dir/automation_identity_deactivate.status"; else echo $? >"$tmp_dir/automation_identity_deactivate.status"; fi
  ) &
  deactivate_pid=$!
  register_pid "$deactivate_pid"
  sleep 0.3
  kill -0 "$deactivate_pid" 2>/dev/null || { cat "$tmp_dir/automation_identity_deactivate.log" >&2; echo "FAIL: automation identity deactivation did not wait for an active resolver" >&2; cleanup; exit 1; }
  printf 'commit;\n' >&4
  exec 4>&-
  identity_barrier_fd_open=0
  wait "$holder_pid" || { echo "FAIL: automation identity holder failed" >&2; cat "$tmp_dir/automation_identity_holder.log" >&2; cleanup; exit 1; }
  unregister_pid "$holder_pid"
  wait "$deactivate_pid" || true
  unregister_pid "$deactivate_pid"
  [[ "$(<"$tmp_dir/automation_identity_deactivate.status")" == 0 ]] || { cat "$tmp_dir/automation_identity_deactivate.log" >&2; echo "FAIL: automation identity deactivation failed after resolver released" >&2; exit 1; }
  [[ "$(psql "$local_db_url" -qAtc "select (select not active from public.automation_identities where id='$expiry_automation_identity_id'::uuid) and (select count(*)=1 from public.audit_events where action='automation_identity.deactivated' and entity_id='$expiry_automation_identity_id'::uuid and actor_id='$user_id'::uuid)")" == t ]] || { echo "FAIL: automation identity deactivation did not persist one audited terminal transition" >&2; exit 1; }
  echo "PASS: automation identity resolver versus deactivation -> deactivation waits, then audits one terminal transition"
}

# Registration and a concurrent attempt to grant ordinary membership share the
# same profile-row lock. Exactly one may commit; an active automation identity
# can never coexist with active interactive membership.
run_pair automation_identity_membership_race "" \
  "insert into public.automation_identities(principal_id,tenant_id,organization_id,facility_id,purpose,display_name,created_by) values('$automation_race_actor_id'::uuid,'$t'::uuid,'$o'::uuid,'$f'::uuid,'inventory.reservation_expiry','Automation identity race fixture','$user_id'::uuid); select pg_sleep(1);" \
  "" \
  "insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active) values('$automation_race_actor_id'::uuid,'$t'::uuid,'$o'::uuid,'$f'::uuid,true);"
[[ ( "$pair_left_status" == 0 && "$pair_right_status" != 0 ) || ( "$pair_left_status" != 0 && "$pair_right_status" == 0 ) ]] || { echo "FAIL: automation identity membership race did not yield one committed winner" >&2; exit 1; }
grep -Eq 'Automation identity principal (cannot receive interactive access|is not eligible)' "$tmp_dir/automation_identity_membership_race_"*.log || { echo "FAIL: automation identity membership race did not fail closed" >&2; exit 1; }
[[ "$(psql "$local_db_url" -qAtc "select not exists(select 1 from public.automation_identities ai join public.memberships m on m.user_id=ai.principal_id and m.active where ai.principal_id='$automation_race_actor_id'::uuid and ai.active)")" == t ]] || { echo "FAIL: active automation identity gained interactive membership" >&2; exit 1; }
echo "PASS: automation identity registration versus membership -> one committed winner, no mixed identity state"

# Transfer creation accepts a caller-supplied request hash.  The current public
# contract compares that value for idempotency; it does not re-hash or
# canonicalize the allocation JSON inside the RPC.
create_transfer_sql() {
  local allocations_sql="$1" key="$2" hash="$3" reason="${4:-create concurrency}"
  printf "select public.create_inventory_transfer('%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,%s,'%s','%s','%s');" \
    "$t" "$o" "$f" "$source" "$destination" "$allocations_sql" "$key" "$hash" "$reason"
}

uuid_from_worker_log() {
  grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$1" | tail -n 1
}

successful_pair_transfer_id() {
  if [[ "$pair_left_status" == 0 ]]; then
    uuid_from_worker_log "$tmp_dir/${1}_left.log"
  else
    uuid_from_worker_log "$tmp_dir/${1}_right.log"
  fi
}

assert_worker_error() {
  local name="$1" expected="$2" log
  if [[ "$pair_left_status" != 0 ]]; then log="$tmp_dir/${name}_left.log"; else log="$tmp_dir/${name}_right.log"; fi
  grep -Fq -- "$expected" "$log" || { echo "FAIL: $name did not return expected error: $expected" >&2; cat "$log" >&2; exit 1; }
}

assert_pair_one_winner() {
  local name="$1"
  local successes=0
  [[ "$pair_left_status" == 0 ]] && ((successes += 1))
  [[ "$pair_right_status" == 0 ]] && ((successes += 1))
  if [[ "$successes" != 1 ]]; then
    echo "FAIL: $name expected exactly one successful conflicting command (left=$pair_left_status right=$pair_right_status)" >&2
    cat "$tmp_dir/${name}_left.log" "$tmp_dir/${name}_right.log" >&2
    exit 1
  fi
}

assert_create_graph() {
  local transfer_id="$1" key="$2" expected_lines="$3" expected_allocations="$4"
  local commands transfers lines allocations events audits orphan_lines orphan_allocations cross_transfer duplicates
  read -r commands transfers lines allocations events audits orphan_lines orphan_allocations cross_transfer duplicates <<<"$(psql "$local_db_url" -qAtF ' ' <<SQL
select
  (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='$key' and status='posted'),
  (select count(*) from public.inventory_transfers where id='$transfer_id'::uuid),
  (select count(*) from public.inventory_transfer_lines where transfer_id='$transfer_id'::uuid),
  (select count(*) from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id='$transfer_id'::uuid),
  (select count(*) from public.inventory_transfer_events where transfer_id='$transfer_id'::uuid and action='inventory.transfer_created'),
  (select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$transfer_id'::uuid and action='inventory.transfer_created'),
  (select count(*) from public.inventory_transfer_lines l left join public.inventory_transfers tr on tr.id=l.transfer_id where tr.id is null),
  (select count(*) from public.inventory_transfer_allocations a left join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.id is null),
  (select count(*) from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id='$transfer_id'::uuid and not exists (select 1 from public.inventory_transfers tr where tr.id=l.transfer_id)),
  (select count(*) from (select a.transfer_line_id from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id='$transfer_id'::uuid group by a.transfer_line_id,a.source_location_id,a.batch_id,a.recording_channel,a.source_disposition having count(*)>1) duplicated_grains);
SQL
)"
  [[ "$commands" == 1 && "$transfers" == 1 && "$lines" == "$expected_lines" && "$allocations" == "$expected_allocations" && "$events" == 1 && "$audits" == 1 && "$orphan_lines" == 0 && "$orphan_allocations" == 0 && "$cross_transfer" == 0 && "$duplicates" == 0 ]] || {
    echo "FAIL: create graph integrity failed for key=$key transfer=$transfer_id values=$commands/$transfers/$lines/$allocations/$events/$audits/$orphan_lines/$orphan_allocations/$cross_transfer/$duplicates" >&2
    exit 1
  }
}

create_scope_counts() {
  psql "$local_db_url" -qAtF ' ' <<SQL
select
  (select count(*) from public.inventory_transfers where tenant_id='$t'::uuid),
  (select count(*) from public.inventory_transfer_lines l join public.inventory_transfers tr on tr.id=l.transfer_id where tr.tenant_id='$t'::uuid),
  (select count(*) from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id join public.inventory_transfers tr on tr.id=l.transfer_id where tr.tenant_id='$t'::uuid),
  (select count(*) from public.inventory_transfer_events e join public.inventory_transfers tr on tr.id=e.transfer_id where tr.tenant_id='$t'::uuid and e.action='inventory.transfer_created'),
  (select count(*) from public.audit_events where tenant_id='$t'::uuid and entity_type='inventory_transfer' and action='inventory.transfer_created');
SQL
}

create_payload_two_a="jsonb_build_array(jsonb_build_object('profile_id','$profile','batch_id','$batch','quantity_base',4,'channel','system'),jsonb_build_object('profile_id','$profile_two','batch_id','$batch_two','quantity_base',6,'channel','system'))"
create_payload_two_b="jsonb_build_array(jsonb_build_object('profile_id','$profile_two','batch_id','$batch_two','quantity_base',6,'channel','system'),jsonb_build_object('profile_id','$profile','batch_id','$batch','quantity_base',4,'channel','system'))"
create_payload_conflict_a="jsonb_build_array(jsonb_build_object('profile_id','$profile','batch_id','$batch','quantity_base',3,'channel','system'),jsonb_build_object('profile_id','$profile_two','batch_id','$batch_two','quantity_base',4,'channel','system'))"
create_payload_conflict_b="jsonb_build_array(jsonb_build_object('profile_id','$profile','batch_id','$batch','quantity_base',5,'channel','system'),jsonb_build_object('profile_id','$profile_two','batch_id','$batch_two','quantity_base',4,'channel','system'))"
create_payload_invalid="jsonb_build_array(jsonb_build_object('profile_id','$profile','batch_id','$batch','quantity_base',0,'channel','system'))"
create_payload_large="jsonb_build_array(jsonb_build_object('profile_id','$profile','batch_id','$batch','quantity_base',1,'channel','system'),jsonb_build_object('profile_id','$profile_two','batch_id','$batch_two','quantity_base',2,'channel','system'),jsonb_build_object('profile_id','$profile_three','batch_id','$batch_three','quantity_base',3,'channel','system'),jsonb_build_object('profile_id','$profile_four','batch_id','$batch_four','quantity_base',4,'channel','system'))"

# Create A: exact concurrent replay with two independent line grains.
run_pair create_exact_duplicate "$auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-exact-duplicate' 'create-exact-duplicate-hash-0001')" "$auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-exact-duplicate' 'create-exact-duplicate-hash-0001')"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: create exact duplicate did not replay to both callers" >&2; exit 1; }
create_a_left="$(uuid_from_worker_log "$tmp_dir/create_exact_duplicate_left.log")"; create_a_right="$(uuid_from_worker_log "$tmp_dir/create_exact_duplicate_right.log")"
[[ -n "$create_a_left" && "$create_a_left" == "$create_a_right" ]] || { echo "FAIL: create exact duplicate returned different transfer ids" >&2; exit 1; }
assert_create_graph "$create_a_left" create-exact-duplicate 2 2
echo "PASS: create exact duplicate replay -> 1 command, 1 transfer, 2 lines, 2 allocations"

# Create B: reordered caller JSON with a deliberately identical supplied hash
# must replay under the current caller-hash contract.
run_pair create_reordered_replay "$auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-reordered' 'create-reordered-shared-hash-0001')" "$auth_sql" "$(create_transfer_sql "$create_payload_two_b" 'create-reordered' 'create-reordered-shared-hash-0001')"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: reordered create did not follow current replay contract" >&2; exit 1; }
create_b_left="$(uuid_from_worker_log "$tmp_dir/create_reordered_replay_left.log")"; create_b_right="$(uuid_from_worker_log "$tmp_dir/create_reordered_replay_right.log")"
[[ -n "$create_b_left" && "$create_b_left" == "$create_b_right" ]] || { echo "FAIL: reordered create produced duplicate graphs" >&2; exit 1; }
assert_create_graph "$create_b_left" create-reordered 2 2
echo "PASS: create reordered replay -> caller-supplied identical hash returns one graph"

# Create C: a conflicting hash/payload may have one winner only; the loser
# must receive the public idempotency error and leave no child graph behind.
run_pair create_conflicting_key "$auth_sql" "$(create_transfer_sql "$create_payload_conflict_a" 'create-conflict' 'create-conflict-hash-a-0001')" "$auth_sql" "$(create_transfer_sql "$create_payload_conflict_b" 'create-conflict' 'create-conflict-hash-b-0001')"
assert_pair_one_winner create_conflicting_key
assert_worker_error create_conflicting_key 'Inventory idempotency key was reused with a different request'
create_c_transfer="$(successful_pair_transfer_id create_conflicting_key)"
assert_create_graph "$create_c_transfer" create-conflict 2 2
create_c_quantity="$(psql "$local_db_url" -qAtc "select sum(requested_quantity_base) from public.inventory_transfer_lines where transfer_id='$create_c_transfer'::uuid")"
[[ "$create_c_quantity" == 7.000000 || "$create_c_quantity" == 9.000000 ]] || { echo "FAIL: conflicting create persisted a partial payload" >&2; exit 1; }
echo "PASS: create conflicting key -> one complete winner graph and one public idempotency denial"

# Create D: current schema has no business-level de-duplication across two
# distinct create commands, so different keys intentionally create two graphs.
run_pair create_different_keys "$auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-different-key-a' 'create-different-key-a-hash-0001')" "$auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-different-key-b' 'create-different-key-b-hash-0001')"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: different-key creates did not both succeed" >&2; exit 1; }
create_d_left="$(uuid_from_worker_log "$tmp_dir/create_different_keys_left.log")"; create_d_right="$(uuid_from_worker_log "$tmp_dir/create_different_keys_right.log")"
[[ -n "$create_d_left" && -n "$create_d_right" && "$create_d_left" != "$create_d_right" ]] || { echo "FAIL: different-key creates unexpectedly shared a transfer" >&2; exit 1; }
assert_create_graph "$create_d_left" create-different-key-a 2 2
assert_create_graph "$create_d_right" create-different-key-b 2 2
echo "PASS: create different keys -> two isolated complete transfer graphs"

# Create E: an allocation validation failure rolls back its claimed command
# and all graph children, while an independent valid create completes.
read -r create_e_transfers_before create_e_lines_before create_e_allocations_before create_e_events_before create_e_audits_before <<<"$(create_scope_counts)"
run_pair create_valid_invalid "$auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-valid-race' 'create-valid-race-hash-0001')" "$auth_sql" "$(create_transfer_sql "$create_payload_invalid" 'create-invalid-race' 'create-invalid-race-hash-0001')"
assert_pair_one_winner create_valid_invalid
assert_worker_error create_valid_invalid 'Inventory transfer allocation denied'
create_e_transfer="$(successful_pair_transfer_id create_valid_invalid)"
assert_create_graph "$create_e_transfer" create-valid-race 2 2
[[ "$(psql "$local_db_url" -qAtc "select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='create-invalid-race'")" == 0 ]] || { echo "FAIL: invalid create retained a command" >&2; exit 1; }
read -r create_e_transfers_after create_e_lines_after create_e_allocations_after create_e_events_after create_e_audits_after <<<"$(create_scope_counts)"
(( create_e_transfers_after == create_e_transfers_before + 1 && create_e_lines_after == create_e_lines_before + 2 && create_e_allocations_after == create_e_allocations_before + 2 && create_e_events_after == create_e_events_before + 1 && create_e_audits_after == create_e_audits_before + 1 )) || { echo "FAIL: invalid create left a partial graph or audit effect" >&2; exit 1; }
echo "PASS: create valid versus invalid -> valid graph committed, invalid graph fully rolled back"

# Create F: authorization is checked before command ownership, so the denied
# caller cannot create or replay a command owned by an authorized user.
read -r create_f_transfers_before create_f_lines_before create_f_allocations_before create_f_events_before create_f_audits_before <<<"$(create_scope_counts)"
run_pair create_authorized_unauthorized "$auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-authorized-race' 'create-authorized-race-hash-0001')" "$unauthorized_auth_sql" "$(create_transfer_sql "$create_payload_two_a" 'create-unauthorized-race' 'create-unauthorized-race-hash-0001')"
assert_pair_one_winner create_authorized_unauthorized
assert_worker_error create_authorized_unauthorized 'Inventory transfer creation denied'
create_f_transfer="$(successful_pair_transfer_id create_authorized_unauthorized)"
assert_create_graph "$create_f_transfer" create-authorized-race 2 2
[[ "$(psql "$local_db_url" -qAtc "select count(*) from public.inventory_commands where requester_id='$unauthorized_id'::uuid and idempotency_key='create-unauthorized-race'")" == 0 ]] || { echo "FAIL: unauthorized create retained a command" >&2; exit 1; }
read -r create_f_transfers_after create_f_lines_after create_f_allocations_after create_f_events_after create_f_audits_after <<<"$(create_scope_counts)"
(( create_f_transfers_after == create_f_transfers_before + 1 && create_f_lines_after == create_f_lines_before + 2 && create_f_allocations_after == create_f_allocations_before + 2 && create_f_events_after == create_f_events_before + 1 && create_f_audits_after == create_f_audits_before + 1 )) || { echo "FAIL: unauthorized create left a partial graph or audit effect" >&2; exit 1; }
echo "PASS: create unauthorized versus authorized -> denied caller left no command or graph"

# Create G: a four-line aggregate must be all-or-nothing under concurrent replay.
run_pair create_large_atomic "$auth_sql" "$(create_transfer_sql "$create_payload_large" 'create-large-atomic' 'create-large-atomic-hash-0001')" "$auth_sql" "$(create_transfer_sql "$create_payload_large" 'create-large-atomic' 'create-large-atomic-hash-0001')"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: large create replay did not return to both callers" >&2; exit 1; }
create_g_left="$(uuid_from_worker_log "$tmp_dir/create_large_atomic_left.log")"; create_g_right="$(uuid_from_worker_log "$tmp_dir/create_large_atomic_right.log")"
[[ -n "$create_g_left" && "$create_g_left" == "$create_g_right" ]] || { echo "FAIL: large create produced incomplete or duplicate graphs" >&2; exit 1; }
assert_create_graph "$create_g_left" create-large-atomic 4 4
echo "PASS: create large multi-line atomicity -> 1 complete four-line graph"

make_expired_transfer() {
  local key="$1" quantity="$2"
  make_reserved_transfer "$key" "$quantity"
  # Reservation history is intentionally immutable.  The local harness uses
  # the narrowest trusted fixture exception: trigger bypass for one timestamp
  # update in one transaction, restoring normal trigger behavior at commit.
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin;
set local session_replication_role=replica;
update public.inventory_reservations
set created_at=now()-interval '2 hours', expires_at=now()-interval '1 hour'
where id='$scenario_reservation'::uuid;
commit;
SQL
}

make_expired_issued_transfer() {
  local key="$1" quantity="$2" issued="$3"
  make_reserved_transfer "$key" "$quantity"
  issue_fixture_quantity "$scenario_transfer" "$scenario_allocation" "$issued" "$key-public-issue"
  local issued_command_count issued_operation_count issued_remaining source_ledger transit_ledger
  read -r issued_command_count issued_operation_count issued_remaining source_ledger transit_ledger <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='$key-public-issue' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$scenario_transfer'::uuid and operation_type='issue'),public.inventory_transfer_reservation_remaining('$scenario_reservation'::uuid),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id where tx.command_id=(select id from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='$key-public-issue') and le.account_type='physical' and le.location_id='$source'::uuid and le.disposition='available'),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id where tx.command_id=(select id from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='$key-public-issue') and le.account_type='physical' and le.location_id=(select transit_location_id from public.inventory_transfers where id='$scenario_transfer'::uuid) and le.disposition='transit')")"
  [[ "$issued_command_count" == 1 && "$issued_operation_count" == 1 && "$(psql "$local_db_url" -qAtc "select $issued_remaining=($quantity-$issued) and $source_ledger=-$issued and $transit_ledger=$issued")" == t ]] || { echo "FAIL: $key public issued fixture is incomplete" >&2; exit 1; }
  assert_transfer_reconciles "$scenario_transfer"
  psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin;
set local session_replication_role=replica;
update public.inventory_reservations
set created_at=now()-interval '2 hours', expires_at=now()-interval '1 hour'
where id='$scenario_reservation'::uuid;
commit;
SQL
  assert_transfer_reconciles "$scenario_transfer"
}

assert_transfer_reconciles() {
  local transfer_id="$1"
  local mismatch
  mismatch="$(psql "$local_db_url" -qAtc "select count(*) from (select bp.id,bp.quantity_base,coalesce(sum(le.quantity_base),0) as ledger_quantity from public.inventory_balance_projections bp left join public.inventory_ledger_entries le on le.account_type='physical' and le.location_id=bp.location_id and le.inventory_item_profile_id=bp.inventory_item_profile_id and le.batch_id is not distinct from bp.batch_id and le.recording_channel=bp.recording_channel and le.disposition=bp.disposition where bp.tenant_id='$t'::uuid and bp.batch_id in (select a.batch_id from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id='$transfer_id'::uuid) group by bp.id) q where q.quantity_base is distinct from q.ledger_quantity")"
  [[ "$mismatch" == 0 ]] || { echo "FAIL: transfer $transfer_id ledger/projection mismatch=$mismatch" >&2; exit 1; }
}
transfer="$(create_transfer issue-create 10)"
allocation="$(psql "$local_db_url" -qAtc "select a.id from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id='$transfer'::uuid")"
psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL
begin; $auth_sql select public.reserve_inventory_transfer('$transfer'::uuid,now()+interval '1 hour','issue-reserve','issue-reserve-hash-00000001'); commit;
SQL

run_parallel() {
  local name="$1" sql="$2"; local i
  local pids=()
  for i in $(seq 1 "$workers"); do
    ( if PGAPPNAME="${matrix_application_prefix}-${name}-worker-${i}" psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL >"$tmp_dir/${name}_${i}.log" 2>&1
begin; $auth_sql $sql commit;
SQL
      then echo 0 >"$tmp_dir/${name}_${i}.status"; else echo $? >"$tmp_dir/${name}_${i}.status"; fi ) &
    pids+=("$!")
    register_pid "$!"
  done
  wait_for_workers "$name" "${pids[@]}"
  for i in $(seq 1 "$workers"); do [[ "$(<"$tmp_dir/${name}_${i}.status")" == 0 ]] || { echo "FAIL: $name worker $i" >&2; cat "$tmp_dir/${name}_${i}.log" >&2; exit 1; }; done
}

run_parallel issue "select public.issue_inventory_transfer('$transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$allocation','quantity_base',10)),'duplicate-issue','duplicate-issue-request-hash-0001','concurrent issue');"
read -r issue_commands issue_operations issue_transactions issue_events issue_audit source_qty transit_qty <<<"$(psql "$local_db_url" -v ON_ERROR_STOP=1 -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='duplicate-issue'),(select count(*) from public.inventory_transfer_operations where transfer_id='$transfer'::uuid and operation_type='issue'),(select count(*) from public.inventory_transactions where command_id=(select id from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='duplicate-issue')),(select count(*) from public.inventory_transfer_events where transfer_id='$transfer'::uuid and action='inventory.transfer_issued'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$transfer'::uuid and action='inventory.transfer_issued'),(select quantity_base from public.inventory_balance_projections where location_id='$source'::uuid and disposition='available'),(select quantity_base from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$transfer'::uuid) and disposition='transit')")"
[[ "$issue_commands" == 1 && "$issue_operations" == 1 && "$issue_transactions" == 1 && "$issue_events" == 1 && "$issue_audit" == 1 && "$source_qty" == 90.000000 && "$transit_qty" == 10.000000 ]] || { echo "FAIL: duplicate issue reconciliation" >&2; exit 1; }
echo "PASS: duplicate issue replay -> $workers/$workers, 1 command, 1 operation, 1 transaction"

run_parallel receipt "select public.receive_inventory_transfer('$transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$allocation','quantity_base',10,'destination_location_id','$destination','destination_disposition','available')),'duplicate-receipt','duplicate-receipt-request-hash-0001','concurrent receipt');"
read -r receipt_commands receipts destination_children transit_after destination_qty receipt_orphans receipt_wrong_grain receipt_wrong_scope receipt_ledger_mismatch <<<"$(psql "$local_db_url" -v ON_ERROR_STOP=1 -qAtF ' ' <<SQL
select
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='duplicate-receipt'),
 (select count(*) from public.inventory_transfer_operations where transfer_id='$transfer'::uuid and operation_type='receive'),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$transfer'::uuid and rd.quantity_base=op.quantity_base),
 (select quantity_base from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$transfer'::uuid) and disposition='transit'),
 (select quantity_base from public.inventory_balance_projections where location_id='$destination'::uuid and disposition='available'),
 (select count(*) from public.inventory_transfer_receipt_destinations rd left join public.inventory_transfer_operations op on op.id=rd.operation_id where op.id is null),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$transfer'::uuid and (rd.destination_location_id,rd.inventory_item_profile_id,rd.batch_id,rd.recording_channel,rd.quantity_base) is distinct from (op.destination_location_id,op.inventory_item_profile_id,op.batch_id,op.recording_channel,op.quantity_base)),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id join public.inventory_transfers tr on tr.id=op.transfer_id where op.transfer_id='$transfer'::uuid and not public.inventory_transfer_location_allowed(tr.destination_root_location_id,rd.destination_location_id)),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$transfer'::uuid and rd.quantity_base is distinct from coalesce((select sum(le.quantity_base) from public.inventory_ledger_entries le where le.transaction_id=op.transaction_id and le.account_type='physical' and le.location_id=rd.destination_location_id and le.inventory_item_profile_id=rd.inventory_item_profile_id and le.batch_id=rd.batch_id and le.recording_channel=rd.recording_channel and le.disposition=op.destination_disposition),0));
SQL
)"
[[ "$receipt_commands" == 1 && "$receipts" == 1 && "$destination_children" == 1 && "$transit_after" == 0.000000 && "$destination_qty" == 10.000000 && "$receipt_orphans" == 0 && "$receipt_wrong_grain" == 0 && "$receipt_wrong_scope" == 0 && "$receipt_ledger_mismatch" == 0 ]] || { echo "FAIL: duplicate receipt child or ledger integrity" >&2; exit 1; }
echo "PASS: duplicate receipt replay -> $workers/$workers, 1 receipt child with exact ledger-linked grain"

# Resolution requests all use the public wrappers over the shared
# post_inventory_transfer_resolution path.  The deterministic run_pair barrier
# releases two independent PostgreSQL sessions at the same time.
resolution_sql() {
  local type="$1" transfer_id="$2" allocation_id="$3" quantity="$4" key="$5" hash="$6"
  case "$type" in
    receive) printf "select public.receive_inventory_transfer('%s'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','%s','quantity_base',%s,'destination_location_id','%s','destination_disposition','available')),'%s','%s','resolution receive');" "$transfer_id" "$allocation_id" "$quantity" "$destination" "$key" "$hash" ;;
    reject) printf "select public.reject_inventory_transfer('%s'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','%s','quantity_base',%s)),'%s','%s','resolution reject');" "$transfer_id" "$allocation_id" "$quantity" "$key" "$hash" ;;
    return) printf "select public.return_rejected_inventory_transfer('%s'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','%s','quantity_base',%s)),'%s','%s','resolution return');" "$transfer_id" "$allocation_id" "$quantity" "$key" "$hash" ;;
    dispose) printf "select public.dispose_rejected_inventory_transfer('%s'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','%s','quantity_base',%s,'destination_disposition','quarantine')),'%s','%s','resolution dispose');" "$transfer_id" "$allocation_id" "$quantity" "$key" "$hash" ;;
    *) echo "FAIL: unsupported resolution fixture type=$type" >&2; exit 1 ;;
  esac
}

resolution_command_transaction_count() {
  local key="$1"
  psql "$local_db_url" -qAtc "select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key='$key'"
}

resolution_command_transaction_count_for_keys() {
  local key quoted_keys=""
  for key in "$@"; do
    [[ -z "$quoted_keys" ]] || quoted_keys+=","
    quoted_keys+="'$key'"
  done
  psql "$local_db_url" -qAtc "select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key in ($quoted_keys)"
}

# Resolution A: receive and reject compete for the same full transit balance.
make_issued_resolution_transfer resolution-a 10
res_a_transfer="$scenario_transfer"; res_a_allocation="$scenario_allocation"; res_a_batch="$scenario_batch_id"
run_pair resolution_receive_reject "$auth_sql" "$(resolution_sql receive "$res_a_transfer" "$res_a_allocation" 10 resolution-a-receive resolution-a-receive-hash-0001)" "$auth_sql" "$(resolution_sql reject "$res_a_transfer" "$res_a_allocation" 10 resolution-a-reject resolution-a-reject-hash-0001)"
assert_pair_one_winner resolution_receive_reject
assert_worker_error resolution_receive_reject 'Inventory transfer resolution exceeds outstanding quantity'
read -r res_a_receive_cmd res_a_reject_cmd res_a_receive_op res_a_reject_op res_a_receipt_child res_a_receive_tx res_a_reject_tx res_a_receive_event res_a_reject_event res_a_receive_audit res_a_reject_audit res_a_transit res_a_destination res_a_returns <<<"$(psql "$local_db_url" -qAtF ' ' <<SQL
select
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-a-receive' and status='posted'),
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-a-reject' and status='posted'),
 (select count(*) from public.inventory_transfer_operations where transfer_id='$res_a_transfer'::uuid and operation_type='receive'),
 (select count(*) from public.inventory_transfer_operations where transfer_id='$res_a_transfer'::uuid and operation_type='reject'),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_a_transfer'::uuid),
 (select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key='resolution-a-receive'),
 (select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key='resolution-a-reject'),
 (select count(*) from public.inventory_transfer_events where transfer_id='$res_a_transfer'::uuid and action='inventory.transfer_receive'),
 (select count(*) from public.inventory_transfer_events where transfer_id='$res_a_transfer'::uuid and action='inventory.transfer_reject'),
 (select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_a_transfer'::uuid and action='inventory.transfer_receive'),
 (select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_a_transfer'::uuid and action='inventory.transfer_reject'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_a_transfer'::uuid) and batch_id='$res_a_batch'::uuid and recording_channel='system' and disposition='transit'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$destination'::uuid and batch_id='$res_a_batch'::uuid and recording_channel='system' and disposition='available'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_a_transfer'::uuid) and batch_id='$res_a_batch'::uuid and recording_channel='system' and disposition='returns_hold');
SQL
)"
res_a_receive_tx="$(resolution_command_transaction_count resolution-a-receive)"
res_a_reject_tx="$(resolution_command_transaction_count resolution-a-reject)"
if [[ "$res_a_receive_cmd" == 1 ]]; then
  [[ "$res_a_reject_cmd" == 0 && "$res_a_receive_op" == 1 && "$res_a_reject_op" == 0 && "$res_a_receipt_child" == 1 && "$res_a_receive_tx" == 1 && "$res_a_reject_tx" == 0 && "$res_a_receive_event" == 1 && "$res_a_reject_event" == 0 && "$res_a_receive_audit" == 1 && "$res_a_reject_audit" == 0 && "$(psql "$local_db_url" -qAtc "select $res_a_transit=0 and $res_a_destination=10 and $res_a_returns=0")" == t ]] || { echo "FAIL: receive/reject receive-winner effects are incomplete values=$res_a_receive_cmd/$res_a_reject_cmd/$res_a_receive_op/$res_a_reject_op/$res_a_receipt_child/$res_a_receive_tx/$res_a_reject_tx/$res_a_receive_event/$res_a_reject_event/$res_a_receive_audit/$res_a_reject_audit/$res_a_transit/$res_a_destination/$res_a_returns" >&2; exit 1; }
else
  [[ "$res_a_reject_cmd" == 1 && "$res_a_receive_op" == 0 && "$res_a_reject_op" == 1 && "$res_a_receipt_child" == 0 && "$res_a_receive_tx" == 0 && "$res_a_reject_tx" == 1 && "$res_a_receive_event" == 0 && "$res_a_reject_event" == 1 && "$res_a_receive_audit" == 0 && "$res_a_reject_audit" == 1 && "$(psql "$local_db_url" -qAtc "select $res_a_transit=0 and $res_a_destination=0 and $res_a_returns=10")" == t ]] || { echo "FAIL: receive/reject reject-winner effects are incomplete" >&2; exit 1; }
fi
assert_transfer_reconciles "$res_a_transfer"
echo "PASS: resolution receive versus reject -> exactly one full-quantity winner"

# Resolution B: jointly valid partial receive/reject commands both post.
make_issued_resolution_transfer resolution-b 10
res_b_transfer="$scenario_transfer"; res_b_allocation="$scenario_allocation"; res_b_batch="$scenario_batch_id"
run_pair resolution_partial_receive_reject "$auth_sql" "$(resolution_sql receive "$res_b_transfer" "$res_b_allocation" 4 resolution-b-receive resolution-b-receive-hash-0001)" "$auth_sql" "$(resolution_sql reject "$res_b_transfer" "$res_b_allocation" 6 resolution-b-reject resolution-b-reject-hash-0001)"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: jointly valid partial resolution did not post both commands" >&2; exit 1; }
read -r res_b_commands res_b_ops res_b_txs res_b_events res_b_audits res_b_children res_b_transit res_b_destination res_b_returns <<<"$(psql "$local_db_url" -qAtF ' ' <<SQL
select
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key in ('resolution-b-receive','resolution-b-reject') and status='posted'),
 (select count(*) from public.inventory_transfer_operations where transfer_id='$res_b_transfer'::uuid and operation_type in ('receive','reject')),
 (select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key in ('resolution-b-receive','resolution-b-reject')),
 (select count(*) from public.inventory_transfer_events where transfer_id='$res_b_transfer'::uuid and action in ('inventory.transfer_receive','inventory.transfer_reject')),
 (select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_b_transfer'::uuid and action in ('inventory.transfer_receive','inventory.transfer_reject')),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_b_transfer'::uuid),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_b_transfer'::uuid) and batch_id='$res_b_batch'::uuid and recording_channel='system' and disposition='transit'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$destination'::uuid and batch_id='$res_b_batch'::uuid and recording_channel='system' and disposition='available'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_b_transfer'::uuid) and batch_id='$res_b_batch'::uuid and recording_channel='system' and disposition='returns_hold');
SQL
)"
res_b_txs="$(resolution_command_transaction_count_for_keys resolution-b-receive resolution-b-reject)"
[[ "$res_b_commands" == 2 && "$res_b_ops" == 2 && "$res_b_txs" == 2 && "$res_b_events" == 2 && "$res_b_audits" == 2 && "$res_b_children" == 1 && "$(psql "$local_db_url" -qAtc "select $res_b_transit=0 and $res_b_destination=4 and $res_b_returns=6")" == t ]] || { echo "FAIL: partial receive/reject did not produce the exact jointly valid state" >&2; exit 1; }
assert_transfer_reconciles "$res_b_transfer"
echo "PASS: resolution partial receive plus reject -> 4 received, 6 rejected"

# Resolution C: two seven-unit claims cannot over-resolve ten issued units.
make_issued_resolution_transfer resolution-c 10
res_c_transfer="$scenario_transfer"; res_c_allocation="$scenario_allocation"; res_c_batch="$scenario_batch_id"
run_pair resolution_over_receive_reject "$auth_sql" "$(resolution_sql receive "$res_c_transfer" "$res_c_allocation" 7 resolution-c-receive resolution-c-receive-hash-0001)" "$auth_sql" "$(resolution_sql reject "$res_c_transfer" "$res_c_allocation" 7 resolution-c-reject resolution-c-reject-hash-0001)"
assert_pair_one_winner resolution_over_receive_reject
assert_worker_error resolution_over_receive_reject 'Inventory transfer resolution exceeds outstanding quantity'
read -r res_c_receive_posted res_c_reject_posted res_c_receive_commands res_c_reject_commands res_c_receive_ops res_c_receive_qty res_c_reject_ops res_c_reject_qty res_c_receive_tx res_c_reject_tx res_c_receive_event res_c_reject_event res_c_receive_audit res_c_reject_audit res_c_receipt_children res_c_receipt_qty res_c_receipt_correct_grain res_c_receipt_wrong_grain res_c_receive_ledger res_c_reject_ledger res_c_transit res_c_destination res_c_returns <<<"$(psql "$local_db_url" -qAtF ' ' <<SQL
select
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-c-receive' and status='posted'),
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-c-reject' and status='posted'),
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-c-receive'),
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-c-reject'),
 (select count(*) from public.inventory_transfer_operations where transfer_id='$res_c_transfer'::uuid and operation_type='receive'),
 (select coalesce(sum(quantity_base),0) from public.inventory_transfer_operations where transfer_id='$res_c_transfer'::uuid and operation_type='receive'),
 (select count(*) from public.inventory_transfer_operations where transfer_id='$res_c_transfer'::uuid and operation_type='reject'),
 (select coalesce(sum(quantity_base),0) from public.inventory_transfer_operations where transfer_id='$res_c_transfer'::uuid and operation_type='reject'),
 (select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key='resolution-c-receive'),
 (select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key='resolution-c-reject'),
 (select count(*) from public.inventory_transfer_events where transfer_id='$res_c_transfer'::uuid and action='inventory.transfer_receive'),
 (select count(*) from public.inventory_transfer_events where transfer_id='$res_c_transfer'::uuid and action='inventory.transfer_reject'),
 (select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_c_transfer'::uuid and action='inventory.transfer_receive'),
 (select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_c_transfer'::uuid and action='inventory.transfer_reject'),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_c_transfer'::uuid and op.operation_type='receive'),
 (select coalesce(sum(rd.quantity_base),0) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_c_transfer'::uuid and op.operation_type='receive'),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_c_transfer'::uuid and op.operation_type='receive' and rd.destination_location_id='$destination'::uuid and (rd.destination_location_id,rd.inventory_item_profile_id,rd.batch_id,rd.recording_channel,rd.quantity_base) is not distinct from (op.destination_location_id,op.inventory_item_profile_id,op.batch_id,op.recording_channel,op.quantity_base)),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_c_transfer'::uuid and op.operation_type='receive' and (rd.destination_location_id,rd.inventory_item_profile_id,rd.batch_id,rd.recording_channel,rd.quantity_base) is distinct from (op.destination_location_id,op.inventory_item_profile_id,op.batch_id,op.recording_channel,op.quantity_base)),
 (select count(*) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key='resolution-c-receive' and le.account_type='physical'),
 (select count(*) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id join public.inventory_commands c on c.id=tx.command_id where c.requester_id='$user_id'::uuid and c.idempotency_key='resolution-c-reject' and le.account_type='physical'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_c_transfer'::uuid) and batch_id='$res_c_batch'::uuid and recording_channel='system' and disposition='transit'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$destination'::uuid and batch_id='$res_c_batch'::uuid and recording_channel='system' and disposition='available'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_c_transfer'::uuid) and batch_id='$res_c_batch'::uuid and recording_channel='system' and disposition='returns_hold');
SQL
)"
if [[ "$res_c_receive_posted" == 1 ]]; then
  [[ "$res_c_reject_posted" == 0 && "$res_c_receive_commands" == 1 && "$res_c_reject_commands" == 0 && "$res_c_receive_ops" == 1 && "$res_c_reject_ops" == 0 && "$res_c_receive_tx" == 1 && "$res_c_reject_tx" == 0 && "$res_c_receive_event" == 1 && "$res_c_reject_event" == 0 && "$res_c_receive_audit" == 1 && "$res_c_reject_audit" == 0 && "$res_c_receipt_children" == 1 && "$res_c_receipt_correct_grain" == 1 && "$res_c_receipt_wrong_grain" == 0 && "$res_c_receive_ledger" == 2 && "$res_c_reject_ledger" == 0 && "$(psql "$local_db_url" -qAtc "select $res_c_receive_qty=7 and $res_c_reject_qty=0 and $res_c_receipt_qty=7 and $res_c_transit=3 and $res_c_destination=7 and $res_c_returns=0")" == t ]] || { echo "FAIL: over-resolution receive winner effects are incomplete" >&2; exit 1; }
else
  [[ "$res_c_reject_posted" == 1 && "$res_c_receive_posted" == 0 && "$res_c_reject_commands" == 1 && "$res_c_receive_commands" == 0 && "$res_c_reject_ops" == 1 && "$res_c_receive_ops" == 0 && "$res_c_reject_tx" == 1 && "$res_c_receive_tx" == 0 && "$res_c_reject_event" == 1 && "$res_c_receive_event" == 0 && "$res_c_reject_audit" == 1 && "$res_c_receive_audit" == 0 && "$res_c_receipt_children" == 0 && "$res_c_receipt_correct_grain" == 0 && "$res_c_receipt_wrong_grain" == 0 && "$res_c_reject_ledger" == 2 && "$res_c_receive_ledger" == 0 && "$(psql "$local_db_url" -qAtc "select $res_c_reject_qty=7 and $res_c_receive_qty=0 and $res_c_receipt_qty=0 and $res_c_transit=3 and $res_c_destination=0 and $res_c_returns=7")" == t ]] || { echo "FAIL: over-resolution reject winner effects are incomplete" >&2; exit 1; }
fi
assert_transfer_reconciles "$res_c_transfer"
echo "PASS: resolution over-bound receive versus reject -> one seven-unit winner only"

# Resolution D: exact duplicate reject replays one physical reclassification.
make_issued_resolution_transfer resolution-d 10
res_d_transfer="$scenario_transfer"; res_d_allocation="$scenario_allocation"; res_d_batch="$scenario_batch_id"
run_pair resolution_duplicate_reject "$auth_sql" "$(resolution_sql reject "$res_d_transfer" "$res_d_allocation" 10 resolution-d-reject resolution-d-reject-hash-0001)" "$auth_sql" "$(resolution_sql reject "$res_d_transfer" "$res_d_allocation" 10 resolution-d-reject resolution-d-reject-hash-0001)"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: duplicate reject did not replay to both callers" >&2; exit 1; }
read -r res_d_cmd res_d_op res_d_tx res_d_event res_d_audit res_d_transit res_d_returns <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-d-reject' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$res_d_transfer'::uuid and operation_type='reject'),0,(select count(*) from public.inventory_transfer_events where transfer_id='$res_d_transfer'::uuid and action='inventory.transfer_reject'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_d_transfer'::uuid and action='inventory.transfer_reject'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_d_transfer'::uuid) and batch_id='$res_d_batch'::uuid and disposition='transit'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_d_transfer'::uuid) and batch_id='$res_d_batch'::uuid and disposition='returns_hold')")"
res_d_tx="$(resolution_command_transaction_count resolution-d-reject)"
[[ "$res_d_cmd" == 1 && "$res_d_op" == 1 && "$res_d_tx" == 1 && "$res_d_event" == 1 && "$res_d_audit" == 1 && "$(psql "$local_db_url" -qAtc "select $res_d_transit=0 and $res_d_returns=10")" == t ]] || { echo "FAIL: duplicate reject duplicated a physical effect" >&2; exit 1; }
assert_transfer_reconciles "$res_d_transfer"
echo "PASS: resolution duplicate reject replay -> one reject operation and transaction"

# Resolution E/F: return and disposal each replay once from real rejected stock.
make_rejected_resolution_transfer resolution-e 10
res_e_transfer="$scenario_transfer"; res_e_allocation="$scenario_allocation"; res_e_batch="$scenario_batch_id"
run_pair resolution_duplicate_return "$auth_sql" "$(resolution_sql return "$res_e_transfer" "$res_e_allocation" 10 resolution-e-return resolution-e-return-hash-0001)" "$auth_sql" "$(resolution_sql return "$res_e_transfer" "$res_e_allocation" 10 resolution-e-return resolution-e-return-hash-0001)"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: duplicate return did not replay to both callers" >&2; exit 1; }
read -r res_e_cmd res_e_op res_e_tx res_e_event res_e_audit res_e_source res_e_returns <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-e-return' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$res_e_transfer'::uuid and operation_type='return'),(select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.idempotency_key='resolution-e-return'),(select count(*) from public.inventory_transfer_events where transfer_id='$res_e_transfer'::uuid and action='inventory.transfer_return'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_e_transfer'::uuid and action='inventory.transfer_return'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$source'::uuid and batch_id='$res_e_batch'::uuid and disposition='available'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_e_transfer'::uuid) and batch_id='$res_e_batch'::uuid and disposition='returns_hold')")"
res_e_tx="$(resolution_command_transaction_count resolution-e-return)"
[[ "$res_e_cmd" == 1 && "$res_e_op" == 1 && "$res_e_tx" == 1 && "$res_e_event" == 1 && "$res_e_audit" == 1 && "$(psql "$local_db_url" -qAtc "select $res_e_source=10 and $res_e_returns=0")" == t ]] || { echo "FAIL: duplicate return duplicated a physical effect" >&2; exit 1; }
assert_transfer_reconciles "$res_e_transfer"
echo "PASS: resolution duplicate return replay -> one return operation and transaction"

make_rejected_resolution_transfer resolution-f 10
res_f_transfer="$scenario_transfer"; res_f_allocation="$scenario_allocation"; res_f_batch="$scenario_batch_id"
run_pair resolution_duplicate_dispose "$auth_sql" "$(resolution_sql dispose "$res_f_transfer" "$res_f_allocation" 10 resolution-f-dispose resolution-f-dispose-hash-0001)" "$auth_sql" "$(resolution_sql dispose "$res_f_transfer" "$res_f_allocation" 10 resolution-f-dispose resolution-f-dispose-hash-0001)"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: duplicate dispose did not replay to both callers" >&2; exit 1; }
read -r res_f_cmd res_f_op res_f_tx res_f_event res_f_audit res_f_returns res_f_quarantine <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-f-dispose' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$res_f_transfer'::uuid and operation_type='dispose_rejected'),(select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.idempotency_key='resolution-f-dispose'),(select count(*) from public.inventory_transfer_events where transfer_id='$res_f_transfer'::uuid and action='inventory.transfer_dispose_rejected'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_f_transfer'::uuid and action='inventory.transfer_dispose_rejected'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_f_transfer'::uuid) and batch_id='$res_f_batch'::uuid and disposition='returns_hold'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_f_transfer'::uuid) and batch_id='$res_f_batch'::uuid and disposition='quarantine')")"
res_f_tx="$(resolution_command_transaction_count resolution-f-dispose)"
[[ "$res_f_cmd" == 1 && "$res_f_op" == 1 && "$res_f_tx" == 1 && "$res_f_event" == 1 && "$res_f_audit" == 1 && "$(psql "$local_db_url" -qAtc "select $res_f_returns=0 and $res_f_quarantine=10")" == t ]] || { echo "FAIL: duplicate disposal duplicated a physical effect" >&2; exit 1; }
assert_transfer_reconciles "$res_f_transfer"
echo "PASS: resolution duplicate dispose replay -> one disposal operation and transaction"

# Resolution G/H: rejected stock is consumed once when full requests conflict,
# and can be split when the partial quantities are jointly valid.
make_rejected_resolution_transfer resolution-g 10
res_g_transfer="$scenario_transfer"; res_g_allocation="$scenario_allocation"; res_g_batch="$scenario_batch_id"
run_pair resolution_return_dispose "$auth_sql" "$(resolution_sql return "$res_g_transfer" "$res_g_allocation" 10 resolution-g-return resolution-g-return-hash-0001)" "$auth_sql" "$(resolution_sql dispose "$res_g_transfer" "$res_g_allocation" 10 resolution-g-dispose resolution-g-dispose-hash-0001)"
assert_pair_one_winner resolution_return_dispose
assert_worker_error resolution_return_dispose 'Inventory transfer resolution exceeds outstanding quantity'
read -r res_g_return_cmd res_g_dispose_cmd res_g_return_op res_g_dispose_op res_g_txs res_g_events res_g_audits res_g_source res_g_quarantine res_g_returns <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-g-return' and status='posted'),(select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='resolution-g-dispose' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$res_g_transfer'::uuid and operation_type='return'),(select count(*) from public.inventory_transfer_operations where transfer_id='$res_g_transfer'::uuid and operation_type='dispose_rejected'),(select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.idempotency_key in ('resolution-g-return','resolution-g-dispose')),(select count(*) from public.inventory_transfer_events where transfer_id='$res_g_transfer'::uuid and action in ('inventory.transfer_return','inventory.transfer_dispose_rejected')),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_g_transfer'::uuid and action in ('inventory.transfer_return','inventory.transfer_dispose_rejected')),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$source'::uuid and batch_id='$res_g_batch'::uuid and disposition='available'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_g_transfer'::uuid) and batch_id='$res_g_batch'::uuid and disposition='quarantine'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_g_transfer'::uuid) and batch_id='$res_g_batch'::uuid and disposition='returns_hold')")"
res_g_txs="$(resolution_command_transaction_count_for_keys resolution-g-return resolution-g-dispose)"
[[ "$(psql "$local_db_url" -qAtc "select ($res_g_return_cmd+$res_g_dispose_cmd)=1 and ($res_g_return_op+$res_g_dispose_op)=1 and $res_g_txs=1 and $res_g_events=1 and $res_g_audits=1 and $res_g_returns=0 and (($res_g_source=10 and $res_g_quarantine=0) or ($res_g_source=0 and $res_g_quarantine=10))")" == t ]] || { echo "FAIL: return/dispose conflict produced a mixed state" >&2; exit 1; }
assert_transfer_reconciles "$res_g_transfer"
echo "PASS: resolution return versus dispose -> exactly one rejected-stock consumer"

make_rejected_resolution_transfer resolution-h 10
res_h_transfer="$scenario_transfer"; res_h_allocation="$scenario_allocation"; res_h_batch="$scenario_batch_id"
run_pair resolution_partial_return_dispose "$auth_sql" "$(resolution_sql return "$res_h_transfer" "$res_h_allocation" 4 resolution-h-return resolution-h-return-hash-0001)" "$auth_sql" "$(resolution_sql dispose "$res_h_transfer" "$res_h_allocation" 6 resolution-h-dispose resolution-h-dispose-hash-0001)"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: jointly valid return/dispose did not post both commands" >&2; exit 1; }
read -r res_h_cmds res_h_ops res_h_txs res_h_events res_h_audits res_h_source res_h_quarantine res_h_returns <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key in ('resolution-h-return','resolution-h-dispose') and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$res_h_transfer'::uuid and operation_type in ('return','dispose_rejected')),(select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.idempotency_key in ('resolution-h-return','resolution-h-dispose')),(select count(*) from public.inventory_transfer_events where transfer_id='$res_h_transfer'::uuid and action in ('inventory.transfer_return','inventory.transfer_dispose_rejected')),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_h_transfer'::uuid and action in ('inventory.transfer_return','inventory.transfer_dispose_rejected')),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$source'::uuid and batch_id='$res_h_batch'::uuid and disposition='available'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_h_transfer'::uuid) and batch_id='$res_h_batch'::uuid and disposition='quarantine'),(select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_h_transfer'::uuid) and batch_id='$res_h_batch'::uuid and disposition='returns_hold')")"
res_h_txs="$(resolution_command_transaction_count_for_keys resolution-h-return resolution-h-dispose)"
[[ "$res_h_cmds" == 2 && "$res_h_ops" == 2 && "$res_h_txs" == 2 && "$res_h_events" == 2 && "$res_h_audits" == 2 && "$(psql "$local_db_url" -qAtc "select $res_h_source=4 and $res_h_quarantine=6 and $res_h_returns=0")" == t ]] || { echo "FAIL: partial return/dispose did not preserve exact rejected quantities" >&2; exit 1; }
assert_transfer_reconciles "$res_h_transfer"
echo "PASS: resolution partial return plus dispose -> 4 returned, 6 quarantined"

# Resolution J: two issued allocations are received in opposite caller JSON
# orders.  Both commands are jointly valid and must lock the shared graph in
# the database's canonical order, not the caller's array order.
scenario_batch resolution-j-a 10 "$profile"
res_j_batch_a="$scenario_batch_id"
scenario_batch resolution-j-b 10 "$profile_two"
res_j_batch_b="$scenario_batch_id"
res_j_transfer="$(psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL | tail -n 1
begin; $auth_sql
select public.create_inventory_transfer('$t'::uuid,'$o'::uuid,'$f'::uuid,'$source'::uuid,'$destination'::uuid,
  jsonb_build_array(
    jsonb_build_object('profile_id','$profile','batch_id','$res_j_batch_a','quantity_base',5,'channel','system'),
    jsonb_build_object('profile_id','$profile_two','batch_id','$res_j_batch_b','quantity_base',5,'channel','system')
  ),'resolution-j-create','resolution-j-create-hash-0001','multi-allocation resolution fixture');
commit;
SQL
)"
res_j_allocation_a="$(psql "$local_db_url" -qAtc "select a.id from public.inventory_transfer_allocations a where a.batch_id='$res_j_batch_a'::uuid")"
res_j_allocation_b="$(psql "$local_db_url" -qAtc "select a.id from public.inventory_transfer_allocations a where a.batch_id='$res_j_batch_b'::uuid")"
psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >/dev/null
begin; $auth_sql
select public.reserve_inventory_transfer('$res_j_transfer'::uuid,now()+interval '1 hour','resolution-j-reserve','resolution-j-reserve-hash-0001');
select public.issue_inventory_transfer('$res_j_transfer'::uuid,jsonb_build_array(
  jsonb_build_object('transfer_allocation_id','$res_j_allocation_a','quantity_base',5),
  jsonb_build_object('transfer_allocation_id','$res_j_allocation_b','quantity_base',5)
),'resolution-j-issue','resolution-j-issue-hash-0001','multi-allocation resolution issue');
commit;
SQL
assert_transfer_reconciles "$res_j_transfer"
resolution_j_moves_a="jsonb_build_array(jsonb_build_object('transfer_allocation_id','$res_j_allocation_a','quantity_base',2,'destination_location_id','$destination','destination_disposition','available'),jsonb_build_object('transfer_allocation_id','$res_j_allocation_b','quantity_base',2,'destination_location_id','$destination','destination_disposition','available'))"
resolution_j_moves_b="jsonb_build_array(jsonb_build_object('transfer_allocation_id','$res_j_allocation_b','quantity_base',2,'destination_location_id','$destination','destination_disposition','available'),jsonb_build_object('transfer_allocation_id','$res_j_allocation_a','quantity_base',2,'destination_location_id','$destination','destination_disposition','available'))"
run_pair resolution_multi_allocation_order "$auth_sql" "select public.receive_inventory_transfer('$res_j_transfer'::uuid,$resolution_j_moves_a,'resolution-j-receive-a','resolution-j-receive-a-hash-0001','multi-order receive');" "$auth_sql" "select public.receive_inventory_transfer('$res_j_transfer'::uuid,$resolution_j_moves_b,'resolution-j-receive-b','resolution-j-receive-b-hash-0001','multi-order receive');"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: opposite-order multi-allocation receives did not both succeed" >&2; exit 1; }
read -r res_j_commands res_j_ops res_j_txs res_j_events res_j_audits res_j_children res_j_orphan_children res_j_cross_grain res_j_a_received res_j_b_received res_j_a_transit res_j_b_transit res_j_a_destination res_j_b_destination <<<"$(psql "$local_db_url" -qAtF ' ' <<SQL
select
 (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key in ('resolution-j-receive-a','resolution-j-receive-b') and status='posted'),
 (select count(*) from public.inventory_transfer_operations where transfer_id='$res_j_transfer'::uuid and operation_type='receive'),
 (select count(*) from public.inventory_transactions tx join public.inventory_commands c on c.id=tx.command_id where c.idempotency_key in ('resolution-j-receive-a','resolution-j-receive-b')),
 (select count(*) from public.inventory_transfer_events where transfer_id='$res_j_transfer'::uuid and action='inventory.transfer_receive'),
 (select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$res_j_transfer'::uuid and action='inventory.transfer_receive'),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_j_transfer'::uuid),
 (select count(*) from public.inventory_transfer_receipt_destinations rd left join public.inventory_transfer_operations op on op.id=rd.operation_id where op.id is null),
 (select count(*) from public.inventory_transfer_receipt_destinations rd join public.inventory_transfer_operations op on op.id=rd.operation_id where op.transfer_id='$res_j_transfer'::uuid and (rd.inventory_item_profile_id,rd.batch_id,rd.recording_channel,rd.destination_location_id,rd.quantity_base) is distinct from (op.inventory_item_profile_id,op.batch_id,op.recording_channel,op.destination_location_id,op.quantity_base)),
 (select coalesce(sum(quantity_base),0) from public.inventory_transfer_operations where transfer_allocation_id='$res_j_allocation_a'::uuid and operation_type='receive'),
 (select coalesce(sum(quantity_base),0) from public.inventory_transfer_operations where transfer_allocation_id='$res_j_allocation_b'::uuid and operation_type='receive'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_j_transfer'::uuid) and batch_id='$res_j_batch_a'::uuid and disposition='transit'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id=(select transit_location_id from public.inventory_transfers where id='$res_j_transfer'::uuid) and batch_id='$res_j_batch_b'::uuid and disposition='transit'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$destination'::uuid and batch_id='$res_j_batch_a'::uuid and disposition='available'),
 (select coalesce(sum(quantity_base),0) from public.inventory_balance_projections where location_id='$destination'::uuid and batch_id='$res_j_batch_b'::uuid and disposition='available');
SQL
)"
res_j_txs="$(resolution_command_transaction_count_for_keys resolution-j-receive-a resolution-j-receive-b)"
[[ "$res_j_commands" == 2 && "$res_j_ops" == 4 && "$res_j_txs" == 2 && "$res_j_events" == 4 && "$res_j_audits" == 4 && "$res_j_children" == 4 && "$res_j_orphan_children" == 0 && "$res_j_cross_grain" == 0 && "$(psql "$local_db_url" -qAtc "select $res_j_a_received=4 and $res_j_b_received=4 and $res_j_a_transit=1 and $res_j_b_transit=1 and $res_j_a_destination=4 and $res_j_b_destination=4")" == t ]] || { echo "FAIL: opposite-order multi-allocation resolution effects are incomplete or crossed" >&2; exit 1; }
assert_transfer_reconciles "$res_j_transfer"
echo "PASS: resolution multi-allocation opposite order -> deterministic locks, four correct receipt children"

# Competing reservation sessions use different transfers and keys against the same 90-unit source balance.
transfer_a="$(create_transfer reserve-a 60)"; transfer_b="$(create_transfer reserve-b 60)"
reserve_worker() {
  local tr="$1"
  local key="$2"
  local log="$tmp_dir/$key.log"

  (
    if PGAPPNAME="${matrix_application_prefix}-competing-reserve-${key}" psql "$local_db_url" -v ON_ERROR_STOP=1 -qAt <<SQL >"$log" 2>&1
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
register_pid "$pid_a"

reserve_worker "$transfer_b" reserve-b-command
pid_b=$!
register_pid "$pid_b"

wait_for_workers competing_reservations "$pid_a" "$pid_b"

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
echo "PASS: competing reservations -> 1 succeeded, 1 rejected, active remaining=$reserved_total"

# Scenario A: cancel and issue contend for the same reservation.  The barrier
# releases two independent sessions only after both are waiting.
scenario_batch cancel-issue 20
make_reserved_transfer cancel-issue 10
cancel_issue_transfer="$scenario_transfer"; cancel_issue_allocation="$scenario_allocation"; cancel_issue_reservation="$scenario_reservation"
run_pair cancel_vs_issue "$auth_sql" \
  "select public.cancel_inventory_transfer('$cancel_issue_transfer'::uuid,'matrix-cancel-issue-cancel','matrix-cancel-issue-cancel-hash-0001','matrix cancel');" \
  "$auth_sql" \
  "select public.issue_inventory_transfer('$cancel_issue_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$cancel_issue_allocation','quantity_base',10)),'matrix-cancel-issue-issue','matrix-cancel-issue-issue-hash-0001','matrix issue');"
assert_pair_one_winner cancel_vs_issue
read -r cancel_cmd cancel_count cancel_event cancel_audit issue_cmd issue_count issue_tx issue_event issue_audit manual_release issue_consumed reservation_remaining source_ledger transit_ledger <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-cancel-issue-cancel' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$cancel_issue_transfer'::uuid and operation_type='cancel'),(select count(*) from public.inventory_transfer_events where transfer_id='$cancel_issue_transfer'::uuid and action='inventory.transfer_cancelled'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$cancel_issue_transfer'::uuid and action='inventory.transfer_cancelled'),(select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-cancel-issue-issue' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$cancel_issue_transfer'::uuid and operation_type='issue'),(select count(*) from public.inventory_transactions where command_id=(select id from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-cancel-issue-issue')),(select count(*) from public.inventory_transfer_events where transfer_id='$cancel_issue_transfer'::uuid and action='inventory.transfer_issued'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$cancel_issue_transfer'::uuid and action='inventory.transfer_issued'),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$cancel_issue_reservation'::uuid and adjustment_type='manually_released'),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$cancel_issue_reservation'::uuid and adjustment_type='issue_consumed'),public.inventory_transfer_reservation_remaining('$cancel_issue_reservation'::uuid),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id where tx.command_id=(select id from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-cancel-issue-issue') and le.account_type='physical' and le.location_id='$source'::uuid and le.disposition='available'),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id where tx.command_id=(select id from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-cancel-issue-issue') and le.account_type='physical' and le.location_id=(select transit_location_id from public.inventory_transfers where id='$cancel_issue_transfer'::uuid) and le.disposition='transit')")"
if [[ "$cancel_count" == 1 ]]; then
  [[ "$cancel_cmd" == 1 && "$cancel_event" == 1 && "$cancel_audit" == 1 && "$issue_cmd" == 0 && "$issue_count" == 0 && "$issue_tx" == 0 && "$issue_event" == 0 && "$issue_audit" == 0 && "$(psql "$local_db_url" -qAtc "select $manual_release=10 and $issue_consumed=0 and $reservation_remaining=0 and $source_ledger=0 and $transit_ledger=0")" == t ]] || { echo "FAIL: cancel_vs_issue invalid cancel winner state" >&2; exit 1; }
else
  [[ "$cancel_cmd" == 0 && "$cancel_count" == 0 && "$cancel_event" == 0 && "$cancel_audit" == 0 && "$issue_cmd" == 1 && "$issue_count" == 1 && "$issue_tx" == 1 && "$issue_event" == 1 && "$issue_audit" == 1 && "$(psql "$local_db_url" -qAtc "select $manual_release=0 and $issue_consumed=10 and $reservation_remaining=0 and $source_ledger=-10 and $transit_ledger=10")" == t ]] || { echo "FAIL: cancel_vs_issue invalid issue winner state" >&2; exit 1; }
fi
assert_transfer_reconciles "$cancel_issue_transfer"
echo "PASS: cancel versus issue -> one valid winner, no mixed reservation release/issue state"

# Scenario B: an allocation-backed closure and a final issue contend for the
# same seven-unit remainder after a real public three-unit issue.
scenario_batch close-issue 20
make_reserved_transfer close-issue 10
close_issue_transfer="$scenario_transfer"; close_issue_allocation="$scenario_allocation"; close_issue_line="$scenario_line"; close_issue_reservation="$scenario_reservation"
issue_fixture_quantity "$close_issue_transfer" "$close_issue_allocation" 3 matrix-close-issue-prior
run_pair close_vs_issue "$auth_sql" \
  "select public.close_inventory_transfer_remainder('$close_issue_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_line_id','$close_issue_line','transfer_allocation_id','$close_issue_allocation','inventory_item_profile_id','$profile','quantity_base',7)),'matrix-close-issue-close','matrix close');" \
  "$auth_sql" \
  "select public.issue_inventory_transfer('$close_issue_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$close_issue_allocation','quantity_base',7)),'matrix-close-issue-issue','matrix-close-issue-issue-hash-0001','matrix issue');"
assert_pair_one_winner close_vs_issue
read -r close_cmd close_rows close_event close_audit close_release issue_cmd_new issue_ops_new issue_tx_new issue_event_new issue_audit_new issue_consumed_new close_issued close_closed close_adjusted close_remaining source_ledger_new transit_ledger_new <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-close-issue-close' and status='posted'),(select count(*) from public.inventory_transfer_remainder_closures c join public.inventory_commands cmd on cmd.id=c.command_id where c.transfer_id='$close_issue_transfer'::uuid and cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-close'),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$close_issue_transfer'::uuid and cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-close' and e.action='inventory.transfer_remainder_closed'),(select count(*) from public.audit_events a where a.entity_type='inventory_transfer' and a.entity_id='$close_issue_transfer'::uuid and a.action='inventory.transfer_remainder_closed'),(select coalesce(sum(ra.quantity_base),0) from public.inventory_reservation_adjustments ra join public.inventory_commands cmd on cmd.id=ra.command_id where ra.reservation_id='$close_issue_reservation'::uuid and cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-close' and ra.adjustment_type='closure_released'),(select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-close-issue-issue' and status='posted'),(select count(*) from public.inventory_transfer_operations o join public.inventory_commands cmd on cmd.id=o.command_id where o.transfer_id='$close_issue_transfer'::uuid and cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-issue' and o.operation_type='issue'),(select count(*) from public.inventory_transactions tx join public.inventory_commands cmd on cmd.id=tx.command_id where cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-issue'),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$close_issue_transfer'::uuid and cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-issue' and e.action='inventory.transfer_issued'),(select count(*) from public.audit_events a where a.entity_type='inventory_transfer' and a.entity_id='$close_issue_transfer'::uuid and a.action='inventory.transfer_issued'),(select coalesce(sum(ra.quantity_base),0) from public.inventory_reservation_adjustments ra join public.inventory_commands cmd on cmd.id=ra.command_id where ra.reservation_id='$close_issue_reservation'::uuid and cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-issue' and ra.adjustment_type='issue_consumed'),(select coalesce(sum(quantity_base),0) from public.inventory_transfer_operations where transfer_allocation_id='$close_issue_allocation'::uuid and operation_type='issue'),(select coalesce(sum(quantity_base),0) from public.inventory_transfer_remainder_closures where transfer_allocation_id='$close_issue_allocation'::uuid),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$close_issue_reservation'::uuid),public.inventory_transfer_reservation_remaining('$close_issue_reservation'::uuid),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id join public.inventory_commands cmd on cmd.id=tx.command_id where cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-issue' and le.account_type='physical' and le.location_id='$source'::uuid and le.disposition='available'),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id join public.inventory_commands cmd on cmd.id=tx.command_id where cmd.requester_id='$user_id'::uuid and cmd.idempotency_key='matrix-close-issue-issue' and le.account_type='physical' and le.location_id=(select transit_location_id from public.inventory_transfers where id='$close_issue_transfer'::uuid) and le.disposition='transit')")"
[[ "$(psql "$local_db_url" -qAtc "select ($close_issued+$close_closed)=10 and $close_adjusted=10 and $close_remaining=0")" == t ]] || { echo "FAIL: close_vs_issue overflow or reservation mismatch" >&2; exit 1; }
if [[ "$close_cmd" == 1 ]]; then
  [[ "$close_rows" == 1 && "$close_event" == 1 && "$close_audit" == 1 && "$issue_cmd_new" == 0 && "$issue_ops_new" == 0 && "$issue_tx_new" == 0 && "$issue_event_new" == 0 && "$issue_audit_new" == 1 && "$(psql "$local_db_url" -qAtc "select $close_release=7 and $issue_consumed_new=0 and $source_ledger_new=0 and $transit_ledger_new=0")" == t ]] || { echo "FAIL: close_vs_issue partial close winner effects" >&2; exit 1; }
else
  [[ "$close_rows" == 0 && "$close_event" == 0 && "$close_audit" == 0 && "$issue_cmd_new" == 1 && "$issue_ops_new" == 1 && "$issue_tx_new" == 1 && "$issue_event_new" == 1 && "$issue_audit_new" == 2 && "$(psql "$local_db_url" -qAtc "select $close_release=0 and $issue_consumed_new=7 and $source_ledger_new=-7 and $transit_ledger_new=7")" == t ]] || { echo "FAIL: close_vs_issue partial issue winner effects" >&2; exit 1; }
fi
assert_transfer_reconciles "$close_issue_transfer"
echo "PASS: close remainder versus issue -> issued+closed=$(( ${close_issued%.*} + ${close_closed%.*} )) within allocation and line bounds"

# A service-role worker cannot substitute an ordinary, unregistered principal
# before entering any expiry race or creating a command/adjustment effect.
scenario_batch expiry-unregistered 20
make_expired_transfer expiry-unregistered 10
expiry_unregistered_transfer="$scenario_transfer"; expiry_unregistered_reservation="$scenario_reservation"
if psql "$local_db_url" -qv ON_ERROR_STOP=1 <<SQL >"$tmp_dir/expiry_unregistered.log" 2>&1
begin; set local role service_role;
select public.expire_inventory_transfer_reservations('$unauthorized_id'::uuid,100);
commit;
SQL
then
  echo "FAIL: unregistered expiry actor was accepted" >&2
  exit 1
fi
grep -q 'Automation identity is not registered for purpose' "$tmp_dir/expiry_unregistered.log" || { cat "$tmp_dir/expiry_unregistered.log" >&2; echo "FAIL: unregistered expiry actor did not fail closed" >&2; exit 1; }
read -r expiry_unregistered_command expiry_unregistered_adjustment expiry_unregistered_event expiry_unregistered_remaining <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$unauthorized_id'::uuid and idempotency_key='reservation-expiry:$expiry_unregistered_reservation'),(select count(*) from public.inventory_reservation_adjustments where reservation_id='$expiry_unregistered_reservation'::uuid),(select count(*) from public.inventory_transfer_events where transfer_id='$expiry_unregistered_transfer'::uuid and action='inventory.transfer_reservation_expired'),(select public.inventory_transfer_reservation_remaining('$expiry_unregistered_reservation'::uuid))")"
[[ "$expiry_unregistered_command" == 0 && "$expiry_unregistered_adjustment" == 0 && "$expiry_unregistered_event" == 0 && "$(psql "$local_db_url" -qAtc "select $expiry_unregistered_remaining=10")" == t ]] || { echo "FAIL: unregistered expiry actor left a partial effect" >&2; exit 1; }
assert_transfer_reconciles "$expiry_unregistered_transfer"
echo "PASS: unregistered expiry actor -> denied before command, adjustment, or physical effect"

# Scenario C: an expiry worker and cancellation may both complete only when
# one release is a no-op; the append-only adjustment total must remain exact.
scenario_batch expiry-cancel 20
make_expired_transfer expiry-cancel 10
expiry_cancel_transfer="$scenario_transfer"; expiry_cancel_reservation="$scenario_reservation"
run_pair expiry_vs_cancel "set local role service_role;" \
  "select public.expire_inventory_transfer_reservations('$expiry_actor_id'::uuid,100);" \
  "$auth_sql" \
  "select public.cancel_inventory_transfer('$expiry_cancel_transfer'::uuid,'matrix-expiry-cancel','matrix-expiry-cancel-hash-0001','matrix cancel');"
read -r expiry_cmd expiry_event expiry_release cancel_cmd cancel_op cancel_event manual_release_total expiry_remaining cancel_status <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$expiry_actor_id'::uuid and idempotency_key='reservation-expiry:$expiry_cancel_reservation' and status='posted'),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$expiry_cancel_transfer'::uuid and cmd.idempotency_key='reservation-expiry:$expiry_cancel_reservation' and e.action='inventory.transfer_reservation_expired'),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$expiry_cancel_reservation'::uuid and adjustment_type='expiry_released'),(select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-expiry-cancel' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$expiry_cancel_transfer'::uuid and operation_type='cancel'),(select count(*) from public.inventory_transfer_events where transfer_id='$expiry_cancel_transfer'::uuid and action='inventory.transfer_cancelled'),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$expiry_cancel_reservation'::uuid and adjustment_type='manually_released'),public.inventory_transfer_reservation_remaining('$expiry_cancel_reservation'::uuid),(select status from public.inventory_transfers where id='$expiry_cancel_transfer'::uuid)")"
if [[ "$expiry_cmd" == 1 ]]; then
  [[ "$expiry_event" == 1 && "$cancel_cmd" == 1 && "$cancel_op" == 1 && "$cancel_event" == 1 && "$(psql "$local_db_url" -qAtc "select $expiry_release=10 and $manual_release_total=0 and $expiry_remaining=0")" == t && "$cancel_status" == cancelled ]] || { echo "FAIL: expiry_vs_cancel partial expiry winner effects" >&2; exit 1; }
else
  [[ "$expiry_event" == 0 && "$cancel_cmd" == 1 && "$cancel_op" == 1 && "$cancel_event" == 1 && "$(psql "$local_db_url" -qAtc "select $expiry_release=0 and $manual_release_total=10 and $expiry_remaining=0")" == t && "$cancel_status" == cancelled ]] || { echo "FAIL: expiry_vs_cancel partial cancel winner effects" >&2; exit 1; }
fi
assert_transfer_reconciles "$expiry_cancel_transfer"
echo "PASS: expiry versus cancel -> exactly one ten-unit release across expiry/manual adjustments"

# Scenario D: expiry and allocation-backed closure contend for the same
# historical remaining reservation on an issued transfer.
scenario_batch expiry-close 20
make_expired_issued_transfer expiry-close 10 3
expiry_close_transfer="$scenario_transfer"; expiry_close_allocation="$scenario_allocation"; expiry_close_line="$scenario_line"; expiry_close_reservation="$scenario_reservation"
run_pair expiry_vs_close "set local role service_role;" \
  "select public.expire_inventory_transfer_reservations('$expiry_actor_id'::uuid,100);" \
  "$auth_sql" \
  "select public.close_inventory_transfer_remainder('$expiry_close_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_line_id','$expiry_close_line','transfer_allocation_id','$expiry_close_allocation','inventory_item_profile_id','$profile','quantity_base',7)),'matrix-expiry-close','matrix close');"
read -r expiry_close_cmd expiry_close_event expiry_close_released close_cmd close_event closure_count closure_released close_remaining <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$expiry_actor_id'::uuid and idempotency_key='reservation-expiry:$expiry_close_reservation' and status='posted'),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$expiry_close_transfer'::uuid and cmd.idempotency_key='reservation-expiry:$expiry_close_reservation' and e.action='inventory.transfer_reservation_expired'),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$expiry_close_reservation'::uuid and adjustment_type='expiry_released'),(select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-expiry-close' and status='posted'),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$expiry_close_transfer'::uuid and cmd.idempotency_key='matrix-expiry-close' and e.action='inventory.transfer_remainder_closed'),(select count(*) from public.inventory_transfer_remainder_closures where transfer_id='$expiry_close_transfer'::uuid),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$expiry_close_reservation'::uuid and adjustment_type='closure_released'),public.inventory_transfer_reservation_remaining('$expiry_close_reservation'::uuid)")"
if [[ "$expiry_close_cmd" == 1 ]]; then
  [[ "$expiry_close_event" == 1 && "$close_cmd" == 0 && "$close_event" == 0 && "$closure_count" == 0 && "$(psql "$local_db_url" -qAtc "select $expiry_close_released=7 and $closure_released=0 and $close_remaining=0")" == t ]] || { echo "FAIL: expiry_vs_close partial expiry effects" >&2; exit 1; }
else
  [[ "$expiry_close_event" == 0 && "$close_cmd" == 1 && "$close_event" == 1 && "$closure_count" == 1 && "$(psql "$local_db_url" -qAtc "select $expiry_close_released=0 and $closure_released=7 and $close_remaining=0")" == t ]] || { echo "FAIL: expiry_vs_close partial closure effects" >&2; exit 1; }
fi
assert_transfer_reconciles "$expiry_close_transfer"
echo "PASS: expiry versus close remainder -> remaining reservation released once"

# Scenario E: an expired reservation cannot be consumed by issue while the
# trusted worker releases it.  The public issue must leave physical state
# untouched even if it reaches the transfer first.
scenario_batch expiry-issue 20
make_expired_transfer expiry-issue 10
expiry_issue_transfer="$scenario_transfer"; expiry_issue_allocation="$scenario_allocation"; expiry_issue_reservation="$scenario_reservation"
run_pair expiry_vs_issue "set local role service_role;" \
  "select public.expire_inventory_transfer_reservations('$expiry_actor_id'::uuid,100);" \
  "$auth_sql" \
  "select public.issue_inventory_transfer('$expiry_issue_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_allocation_id','$expiry_issue_allocation','quantity_base',10)),'matrix-expiry-issue','matrix-expiry-issue-hash-0001','matrix issue');"
[[ "$pair_left_status" == 0 ]] || { echo "FAIL: expiry_vs_issue worker failed" >&2; cat "$tmp_dir/expiry_vs_issue_left.log" >&2; exit 1; }
[[ "$pair_right_status" != 0 ]] || { echo "FAIL: expiry_vs_issue consumed an expired reservation" >&2; exit 1; }
read -r expiry_issue_cmd expiry_issue_expiry_event expiry_issue_release issue_cmd_attempt expiry_issue_ops expiry_issue_tx expiry_issue_operation_event expiry_issue_consumed source_issue_ledger transit_issue_ledger <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$expiry_actor_id'::uuid and idempotency_key='reservation-expiry:$expiry_issue_reservation' and status='posted'),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$expiry_issue_transfer'::uuid and cmd.idempotency_key='reservation-expiry:$expiry_issue_reservation' and e.action='inventory.transfer_reservation_expired'),(select coalesce(sum(quantity_base),0) from public.inventory_reservation_adjustments where reservation_id='$expiry_issue_reservation'::uuid and adjustment_type='expiry_released'),(select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-expiry-issue'),(select count(*) from public.inventory_transfer_operations o join public.inventory_commands cmd on cmd.id=o.command_id where o.transfer_id='$expiry_issue_transfer'::uuid and cmd.idempotency_key='matrix-expiry-issue' and o.operation_type='issue'),(select count(*) from public.inventory_transactions tx join public.inventory_commands cmd on cmd.id=tx.command_id where cmd.idempotency_key='matrix-expiry-issue'),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$expiry_issue_transfer'::uuid and cmd.idempotency_key='matrix-expiry-issue' and e.action='inventory.transfer_issued'),(select coalesce(sum(ra.quantity_base),0) from public.inventory_reservation_adjustments ra join public.inventory_commands cmd on cmd.id=ra.command_id where ra.reservation_id='$expiry_issue_reservation'::uuid and cmd.idempotency_key='matrix-expiry-issue' and ra.adjustment_type='issue_consumed'),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id join public.inventory_commands cmd on cmd.id=tx.command_id where cmd.idempotency_key='matrix-expiry-issue' and le.account_type='physical' and le.location_id='$source'::uuid),(select coalesce(sum(le.quantity_base),0) from public.inventory_ledger_entries le join public.inventory_transactions tx on tx.id=le.transaction_id join public.inventory_commands cmd on cmd.id=tx.command_id where cmd.id=tx.command_id and cmd.idempotency_key='matrix-expiry-issue' and le.account_type='physical' and le.disposition='transit')")"
[[ "$expiry_issue_cmd" == 1 && "$expiry_issue_expiry_event" == 1 && "$issue_cmd_attempt" == 0 && "$expiry_issue_ops" == 0 && "$expiry_issue_tx" == 0 && "$expiry_issue_operation_event" == 0 && "$(psql "$local_db_url" -qAtc "select $expiry_issue_release=10 and $expiry_issue_consumed=0 and $source_issue_ledger=0 and $transit_issue_ledger=0")" == t ]] || { echo "FAIL: expiry_vs_issue invalid final state" >&2; exit 1; }
assert_transfer_reconciles "$expiry_issue_transfer"
echo "PASS: expiry versus issue -> expired reservation released and no issue posted"

# Scenario F: identical cancellation calls are true replay, not a race that
# leaks a unique violation or duplicates a manual release.
scenario_batch duplicate-cancel 20
make_reserved_transfer duplicate-cancel 10
duplicate_cancel_transfer="$scenario_transfer"; duplicate_cancel_reservation="$scenario_reservation"
run_pair duplicate_cancel "$auth_sql" \
  "select public.cancel_inventory_transfer('$duplicate_cancel_transfer'::uuid,'matrix-duplicate-cancel','matrix-duplicate-cancel-hash-0001','matrix cancel replay');" \
  "$auth_sql" \
  "select public.cancel_inventory_transfer('$duplicate_cancel_transfer'::uuid,'matrix-duplicate-cancel','matrix-duplicate-cancel-hash-0001','matrix cancel replay');"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: duplicate_cancel replay did not return to both callers" >&2; exit 1; }
read -r duplicate_cancel_commands duplicate_cancel_ops duplicate_cancel_events duplicate_cancel_audit duplicate_cancel_releases <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-duplicate-cancel' and status='posted'),(select count(*) from public.inventory_transfer_operations where transfer_id='$duplicate_cancel_transfer'::uuid and operation_type='cancel'),(select count(*) from public.inventory_transfer_events where transfer_id='$duplicate_cancel_transfer'::uuid and action='inventory.transfer_cancelled'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$duplicate_cancel_transfer'::uuid and action='inventory.transfer_cancelled'),(select count(*) from public.inventory_reservation_adjustments where reservation_id='$duplicate_cancel_reservation'::uuid and adjustment_type='manually_released')")"
[[ "$duplicate_cancel_commands" == 1 && "$duplicate_cancel_ops" == 1 && "$duplicate_cancel_events" == 1 && "$duplicate_cancel_audit" == 1 && "$duplicate_cancel_releases" == 1 ]] || { echo "FAIL: duplicate_cancel duplicated an effect" >&2; exit 1; }
echo "PASS: duplicate cancel replay -> both sessions returned one posted cancel effect"

# Scenario G: identical closure calls replay even when the first closure moves
# the transfer to its terminal status.
scenario_batch duplicate-close 20
make_reserved_transfer duplicate-close 10
duplicate_close_transfer="$scenario_transfer"; duplicate_close_allocation="$scenario_allocation"; duplicate_close_line="$scenario_line"; duplicate_close_reservation="$scenario_reservation"
issue_fixture_quantity "$duplicate_close_transfer" "$duplicate_close_allocation" 3 matrix-duplicate-close-prior
run_pair duplicate_close "$auth_sql" \
  "select public.close_inventory_transfer_remainder('$duplicate_close_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_line_id','$duplicate_close_line','transfer_allocation_id','$duplicate_close_allocation','inventory_item_profile_id','$profile','quantity_base',7)),'matrix-duplicate-close','matrix close replay');" \
  "$auth_sql" \
  "select public.close_inventory_transfer_remainder('$duplicate_close_transfer'::uuid,jsonb_build_array(jsonb_build_object('transfer_line_id','$duplicate_close_line','transfer_allocation_id','$duplicate_close_allocation','inventory_item_profile_id','$profile','quantity_base',7)),'matrix-duplicate-close','matrix close replay');"
[[ "$pair_left_status" == 0 && "$pair_right_status" == 0 ]] || { echo "FAIL: duplicate_close replay did not return to both callers" >&2; exit 1; }
read -r duplicate_close_commands duplicate_close_rows duplicate_close_events duplicate_close_audit duplicate_close_adjustments <<<"$(psql "$local_db_url" -qAtF ' ' -c "select (select count(*) from public.inventory_commands where requester_id='$user_id'::uuid and idempotency_key='matrix-duplicate-close' and status='posted'),(select count(*) from public.inventory_transfer_remainder_closures where transfer_id='$duplicate_close_transfer'::uuid),(select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where e.transfer_id='$duplicate_close_transfer'::uuid and cmd.idempotency_key='matrix-duplicate-close' and e.action='inventory.transfer_remainder_closed'),(select count(*) from public.audit_events where entity_type='inventory_transfer' and entity_id='$duplicate_close_transfer'::uuid and action='inventory.transfer_remainder_closed'),(select count(*) from public.inventory_reservation_adjustments where reservation_id='$duplicate_close_reservation'::uuid and adjustment_type='closure_released')")"
[[ "$duplicate_close_commands" == 1 && "$duplicate_close_rows" == 1 && "$duplicate_close_events" == 1 && "$duplicate_close_audit" == 1 && "$duplicate_close_adjustments" == 1 ]] || { echo "FAIL: duplicate_close duplicated an effect" >&2; exit 1; }
assert_transfer_reconciles "$duplicate_close_transfer"
echo "PASS: duplicate close-remainder replay -> both sessions returned one closure and release"

# Scenario H: two trusted expiry workers contend for the same candidate set.
# A final pass proves no eligible row was lost by SKIP LOCKED scheduling.
scenario_batch expiry-workers-a 20
make_expired_transfer expiry-workers-a 10
expiry_worker_a_reservation="$scenario_reservation"
scenario_batch expiry-workers-b 20
make_expired_transfer expiry-workers-b 10
expiry_worker_b_reservation="$scenario_reservation"
run_pair two_expiry_workers "set local role service_role;" \
  "select public.expire_inventory_transfer_reservations('$expiry_actor_id'::uuid,100);" \
  "set local role service_role;" \
  "select public.expire_inventory_transfer_reservations('$expiry_actor_id'::uuid,100);"
expiry_worker_left_count="$(grep -E '^[0-9]+$' "$tmp_dir/two_expiry_workers_left.log" | tail -n 1)"
expiry_worker_right_count="$(grep -E '^[0-9]+$' "$tmp_dir/two_expiry_workers_right.log" | tail -n 1)"
[[ -n "$expiry_worker_left_count" && -n "$expiry_worker_right_count" ]] || { echo "FAIL: two_expiry_workers did not return worker counts" >&2; exit 1; }
final_expiry_pass="$(psql "$local_db_url" -qAtv ON_ERROR_STOP=1 <<SQL | tail -n 1
begin; set local role service_role; select public.expire_inventory_transfer_reservations('$expiry_actor_id'::uuid,100); commit;
SQL
)"
read -r expiry_worker_releases expiry_worker_duplicates expiry_worker_commands expiry_worker_events <<<"$(psql "$local_db_url" -qAtF ' ' <<SQL
select
  (select count(*) from public.inventory_reservation_adjustments where reservation_id in ('$expiry_worker_a_reservation'::uuid,'$expiry_worker_b_reservation'::uuid) and adjustment_type='expiry_released'),
  (select count(*) from (select reservation_id from public.inventory_reservation_adjustments where reservation_id in ('$expiry_worker_a_reservation'::uuid,'$expiry_worker_b_reservation'::uuid) and adjustment_type='expiry_released' group by reservation_id having count(*)>1) duplicates),
  (select count(*) from public.inventory_commands where requester_id='$expiry_actor_id'::uuid and idempotency_key in ('reservation-expiry:$expiry_worker_a_reservation','reservation-expiry:$expiry_worker_b_reservation') and status='posted'),
  (select count(*) from public.inventory_transfer_events e join public.inventory_commands cmd on cmd.id=e.command_id where cmd.idempotency_key in ('reservation-expiry:$expiry_worker_a_reservation','reservation-expiry:$expiry_worker_b_reservation') and e.action='inventory.transfer_reservation_expired');
SQL
)"
[[ "$(psql "$local_db_url" -qAtc "select ($expiry_worker_left_count+$expiry_worker_right_count)=2")" == t && "$expiry_worker_releases" == 2 && "$expiry_worker_duplicates" == 0 && "$expiry_worker_commands" == 2 && "$expiry_worker_events" == 2 && "$final_expiry_pass" == 0 ]] || { echo "FAIL: two_expiry_workers skipped or duplicated expiry work" >&2; exit 1; }
echo "PASS: two expiry workers -> returned $expiry_worker_left_count+$expiry_worker_right_count, two candidates released once, final pass=0"

assert_automation_identity_deactivation_serializes

# Ledger/projection reconciliation for every physical dimension touched by this harness.
reconciliation="$(psql "$local_db_url" -qAtc "select count(*) from (select bp.location_id,bp.inventory_item_profile_id,bp.batch_id,bp.recording_channel,bp.disposition,bp.quantity_base,coalesce(sum(le.quantity_base),0) ledger_quantity from public.inventory_balance_projections bp left join public.inventory_ledger_entries le on le.account_type='physical' and le.location_id=bp.location_id and le.inventory_item_profile_id=bp.inventory_item_profile_id and le.batch_id is not distinct from bp.batch_id and le.recording_channel=bp.recording_channel and le.disposition=bp.disposition where bp.tenant_id='$t'::uuid group by bp.id) q where q.quantity_base is distinct from q.ledger_quantity")"
# Opening stock is posted through the Phase One workflow, so every physical
# grain used by this harness must reconcile with the immutable ledger.
[[ "$reconciliation" == 0 ]] || { echo "FAIL: unexpected projection reconciliation result=$reconciliation" >&2; exit 1; }
echo "PASS: ledger/projection reconciliation -> all fixture and Phase Two physical grains reconcile"
echo "PASS: full transfer concurrency matrix (create duplicate/reordered/conflict/different-key/invalid/authorization/large-atomicity; duplicate issue/receipt; resolution receive/reject, partial/over-bound, duplicate reject/return/dispose, return/dispose, multi-allocation order; competing reservations, cancel/issue, close/issue, expiry/cancel, expiry/close, expiry/issue, duplicate cancel, duplicate close, two expiry workers)"
