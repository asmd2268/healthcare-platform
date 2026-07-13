#!/usr/bin/env bash
set -euo pipefail
[[ "${SUPABASE_ENV:-}" == staging ]] || { echo "FAIL: SUPABASE_ENV must equal staging" >&2; exit 1; }
[[ -n "${DATABASE_URL:-}" ]] || { echo "FAIL: DATABASE_URL is required" >&2; exit 1; }
[[ ! "$DATABASE_URL" =~ (prod|production) ]] || { echo "FAIL: production-looking target refused" >&2; exit 1; }
npm run supabase:target:sql-tests-check >/dev/null
for file in $(find supabase/tests -maxdepth 1 -name '*.executable.sql' -print | sort); do psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file" >/dev/null; done
echo "PASS: executable staging SQL tests"
