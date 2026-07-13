#!/usr/bin/env bash
set -euo pipefail
[[ "${SUPABASE_ENV:-}" == staging ]] || { echo "FAIL: SUPABASE_ENV must equal staging" >&2; exit 1; }
[[ -n "${DATABASE_URL:-}" ]] || { echo "FAIL: DATABASE_URL is required" >&2; exit 1; }
[[ ! "$DATABASE_URL" =~ (prod|production) ]] || { echo "FAIL: production-looking target refused" >&2; exit 1; }
npm run supabase:target:sql-tests-check >/dev/null
files=()
while IFS= read -r file; do files+=("$file"); done < <(find supabase/tests -maxdepth 1 -name '*.executable.sql' -print | LC_ALL=C sort)
(( ${#files[@]} > 0 )) || { echo "FAIL: 0 executable SQL tests discovered" >&2; exit 1; }
echo "Discovered ${#files[@]} executable SQL test(s)"
for file in "${files[@]}"; do node scripts/staging-sql-test-validation.mjs "$file"; echo "RUN: $file"; psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file" >/dev/null; done
echo "PASS: ${#files[@]} executable staging SQL test(s)"
