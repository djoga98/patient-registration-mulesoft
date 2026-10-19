#!/usr/bin/env bash
# Runs db/tests/constraint-tests.sql against the local Docker database as the
# least-privilege application role. The SQL rolls back everything it does.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$root/infrastructure/.env"; set +a

out=$(docker exec -i -e PGPASSWORD="$APP_DB_PASSWORD" patient-registration-postgres \
        psql -h 127.0.0.1 -U patient_app -d patients -q -A -F ' ' -t < "$root/db/tests/constraint-tests.sql")
echo "$out"
grep -q '^ALL PASSED$' <<<"$out"
