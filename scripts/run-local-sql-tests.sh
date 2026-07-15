#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v supabase >/dev/null || { echo "FAIL: Supabase CLI is required" >&2; exit 1; }
command -v docker >/dev/null || { echo "FAIL: Docker is required for a disposable local database" >&2; exit 1; }
command -v psql >/dev/null || { echo "FAIL: PostgreSQL client (psql) is required" >&2; exit 1; }

supabase start >/dev/null
supabase db reset >/dev/null
status_json=""
for _ in $(seq 1 20); do
  if status_json="$(supabase status --output json 2>/dev/null)"; then
    break
  fi
  sleep 2
done
[[ -n "$status_json" ]] || { echo "FAIL: local Supabase services did not become ready" >&2; exit 1; }
local_db_url="$(printf '%s' "$status_json" | node -e 'let body=""; process.stdin.on("data", chunk => body += chunk).on("end", () => { const value = JSON.parse(body).DB_URL; if (typeof value !== "string" || value === "") process.exit(1); process.stdout.write(value); });')" || { echo "FAIL: local DB_URL was not reported by Supabase" >&2; exit 1; }
if ! node - "$local_db_url" <<'NODE'
const value = new URL(process.argv[2]);
if (!['postgres:', 'postgresql:'].includes(value.protocol) || !['127.0.0.1', 'localhost', 'host.docker.internal'].includes(value.hostname)) process.exit(1);
NODE
then
  echo "FAIL: refusing a non-local database target" >&2
  exit 1
fi

files=()
while IFS= read -r file; do files+=("$file"); done < <(find supabase/tests -maxdepth 1 -name '*.executable.sql' -print | LC_ALL=C sort)
(( ${#files[@]} > 0 )) || { echo "FAIL: 0 executable SQL tests discovered" >&2; exit 1; }
for file in "${files[@]}"; do
  node scripts/staging-sql-test-validation.mjs "$file"
  echo "RUN: $file"
  psql "$local_db_url" -v ON_ERROR_STOP=1 -f "$file"
done
concurrency_tests=()
while IFS= read -r file; do concurrency_tests+=("$file"); done < <(find supabase/tests -maxdepth 1 -name '*_concurrency.sh' -print | LC_ALL=C sort)
(( ${#concurrency_tests[@]} > 0 )) || { echo "FAIL: 0 concurrency SQL tests discovered" >&2; exit 1; }
for concurrency_test in "${concurrency_tests[@]}"; do
  [[ -x "$concurrency_test" ]] || { echo "FAIL: concurrency test is not executable: $concurrency_test" >&2; exit 1; }
  echo "RUN: $concurrency_test"
  "$concurrency_test" "$local_db_url"
done
echo "PASS: ${#files[@]} executable local SQL test(s); each test rolls back its own transaction"
echo "INFO: Supabase local services remain running; use 'supabase stop' when finished."
