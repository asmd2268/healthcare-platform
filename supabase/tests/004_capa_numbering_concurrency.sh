#!/usr/bin/env bash
set -euo pipefail

local_db_url="${1:?local database URL is required}"
node - "$local_db_url" <<'NODE'
const url = new URL(process.argv[2]);
if (!['postgres:', 'postgresql:'].includes(url.protocol) || !['127.0.0.1', 'localhost', 'host.docker.internal'].includes(url.hostname)) process.exit(1);
NODE

command -v psql >/dev/null || { echo "FAIL: psql is required" >&2; exit 1; }
command -v uuidgen >/dev/null || { echo "FAIL: uuidgen is required" >&2; exit 1; }

workers=10
t1="$(uuidgen | tr '[:upper:]' '[:lower:]')"; o1="$(uuidgen | tr '[:upper:]' '[:lower:]')"; f1="$(uuidgen | tr '[:upper:]' '[:lower:]')"
t2="$(uuidgen | tr '[:upper:]' '[:lower:]')"; o2="$(uuidgen | tr '[:upper:]' '[:lower:]')"; f2="$(uuidgen | tr '[:upper:]' '[:lower:]')"
actor="$(uuidgen | tr '[:upper:]' '[:lower:]')"; role="$(uuidgen | tr '[:upper:]' '[:lower:]')"; action_capa="$(uuidgen | tr '[:upper:]' '[:lower:]')"
prefix="concurrency-${t1:0:8}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/capa-concurrency.XXXXXX")"

cleanup() {
  psql "$local_db_url" -v ON_ERROR_STOP=1 -q <<SQL >/dev/null 2>&1 || true
delete from public.audit_events where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_events where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_evidence where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_due_date_extensions where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_effectiveness_reviews where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_root_cause_analyses where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_comments where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_assignments where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_actions where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_action_counters where capa_id='$action_capa'::uuid;
delete from public.capa_sources where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_records where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.capa_number_counters where tenant_id in ('$t1'::uuid,'$t2'::uuid);
delete from public.user_role_assignments where user_id='$actor'::uuid;
delete from public.memberships where user_id='$actor'::uuid;
delete from public.role_permissions where role_id='$role'::uuid;
delete from public.roles where id='$role'::uuid;
delete from public.facilities where id in ('$f1'::uuid,'$f2'::uuid);
delete from public.organizations where id in ('$o1'::uuid,'$o2'::uuid);
delete from public.tenants where id in ('$t1'::uuid,'$t2'::uuid);
delete from auth.users where id='$actor'::uuid;
SQL
}
trap cleanup EXIT

psql "$local_db_url" -v ON_ERROR_STOP=1 -q <<SQL
insert into public.tenants(id,key,name_en) values ('$t1','$prefix-a','Concurrency A'),('$t2','$prefix-b','Concurrency B');
insert into public.organizations(id,tenant_id,code,name_en) values ('$o1','$t1','CON-A','Concurrency A'),('$o2','$t2','CON-B','Concurrency B');
insert into public.facilities(id,tenant_id,organization_id,code,name_en) values ('$f1','$t1','$o1','CON-A','Concurrency A'),('$f2','$t2','$o2','CON-B','Concurrency B');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values ('$actor','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$prefix@example.test','not-used',now(),'{}','{}',now(),now());
insert into public.memberships(user_id,tenant_id,organization_id,facility_id,active) values ('$actor','$t1','$o1','$f1',true),('$actor','$t2','$o2','$f2',true);
insert into public.roles(id,key,name_ar,name_en,scope_level) values ('$role','$prefix','اختبار تزامن','Concurrency test','facility');
insert into public.role_permissions(role_id,permission_id) select '$role'::uuid,id from public.permissions where key in ('capa.create','capa.add_actions');
insert into public.user_role_assignments(user_id,role_id,tenant_id,organization_id,facility_id) values ('$actor','$role','$t1','$o1','$f1'),('$actor','$role','$t2','$o2','$f2');
select set_config('app.capa_controlled','on',true);
insert into public.capa_records(id,tenant_id,organization_id,facility_id,capa_number,title_en,description_en,status,owner_id,created_by,updated_by) values ('$action_capa','$t1','$o1','$f1','CAPA-ACTION-CONCURRENCY','Action concurrency','Action concurrency','approved','$actor','$actor','$actor');
SQL

create_capa() {
  local tenant="$1" org="$2" facility="$3" label="$4"
  psql "$local_db_url" -v ON_ERROR_STOP=1 -qAt <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','$actor',true);
select public.create_capa('$tenant'::uuid,'$org'::uuid,'$facility'::uuid,'','${label}','description','description','$actor'::uuid,'manual','manual',null);
commit;
SQL
}
create_action() {
  psql "$local_db_url" -v ON_ERROR_STOP=1 -qAt <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub','$actor',true);
select public.create_capa_action('$action_capa'::uuid,'','Concurrent action','$actor'::uuid,current_date+7,false);
commit;
SQL
}

names=(); pids=()
run_worker() {
  local name="$1" kind="$2" log_file status_file
  log_file="$tmp_dir/$name.log"
  status_file="$tmp_dir/$name.status"
  (
    if [[ "$kind" == "capa-a" ]]; then create_capa "$t1" "$o1" "$f1" "$name" >"$log_file" 2>&1
    elif [[ "$kind" == "capa-b" ]]; then create_capa "$t2" "$o2" "$f2" "$name" >"$log_file" 2>&1
    else create_action >"$log_file" 2>&1
    fi
    code=$?
    printf '%s\n' "$code" >"$status_file"
  ) &
  names+=("$name"); pids+=("$!")
}
for i in $(seq 1 "$workers"); do run_worker "capa_scope_a_$i" capa-a; done
for i in $(seq 1 "$workers"); do run_worker "capa_scope_b_$i" capa-b; done
for i in $(seq 1 "$workers"); do run_worker "action_$i" action; done
for pid in "${pids[@]}"; do wait "$pid"; done
failed=0
for name in "${names[@]}"; do
  code="$(<"$tmp_dir/$name.status")"
  if [[ "$code" != 0 ]]; then
    failed=1
    echo "FAIL: worker=$name exit_code=$code" >&2
    sed -E 's#(postgres(ql)?://)[^@/]+@#\1***@#g' "$tmp_dir/$name.log" >&2
  fi
done
[[ "$failed" == 0 ]] || { echo "FAIL: one or more concurrent psql workers failed" >&2; exit 1; }

result="$(psql "$local_db_url" -v ON_ERROR_STOP=1 -At <<SQL
select (select count(*) from public.capa_records where tenant_id='$t1'::uuid and capa_number ~ ('^CAPA-'||to_char(current_date,'YYYY')||'-[0-9]{6}$')),
       (select count(distinct capa_number) from public.capa_records where tenant_id='$t1'::uuid and capa_number ~ ('^CAPA-'||to_char(current_date,'YYYY')||'-[0-9]{6}$')),
       (select count(*) from public.capa_records where tenant_id='$t2'::uuid and capa_number ~ ('^CAPA-'||to_char(current_date,'YYYY')||'-[0-9]{6}$')),
       (select count(distinct capa_number) from public.capa_records where tenant_id='$t2'::uuid and capa_number ~ ('^CAPA-'||to_char(current_date,'YYYY')||'-[0-9]{6}$')),
       (select count(*) from public.capa_actions where capa_id='$action_capa'::uuid),
       (select count(distinct sequence) from public.capa_actions where capa_id='$action_capa'::uuid);
SQL
)"
IFS='|' read -r c1 u1 c2 u2 ca ua <<< "$result"
if [[ "$c1" != "$workers" || "$u1" != "$workers" || "$c2" != "$workers" || "$u2" != "$workers" || "$ca" != "$workers" || "$ua" != "$workers" ]]; then
  echo "DIAG: expected_capa_per_scope=$workers actual_scope_a=$c1 unique_scope_a=$u1 actual_scope_b=$c2 unique_scope_b=$u2" >&2
  echo "DIAG: expected_actions=$workers actual_actions=$ca unique_actions=$ua" >&2
  psql "$local_db_url" -v ON_ERROR_STOP=1 -Atc "select 'scope_a|'||coalesce(string_agg(capa_number,',' order by capa_number),'') from public.capa_records where tenant_id='$t1'::uuid union all select 'scope_b|'||coalesce(string_agg(capa_number,',' order by capa_number),'') from public.capa_records where tenant_id='$t2'::uuid union all select 'actions|'||coalesce(string_agg(sequence::text,',' order by sequence),'') from public.capa_actions where capa_id='$action_capa'::uuid;" >&2
  echo "FAIL: concurrency numbering assertion failed" >&2
  exit 1
fi
echo "CAPA concurrency: $((workers * 2))/$((workers * 2)) unique"
echo "Action concurrency: $workers/$workers unique"
echo "Rollback behavior: counter updates are transactional; a rolled-back creation does not consume a number."
