#!/usr/bin/env bash
# End-to-end check of the three locally running APIs against the Docker database.
#
#   scripts/e2e-local.sh
#
# Preconditions: infrastructure/docker-compose.yml is up, the three apps run
# (scripts/run-mule-local.sh) and the patient table is EMPTY. The sample cases only
# give the documented results in order on an empty table (case 4 duplicates case 1),
# so the script refuses to run otherwise. It never deletes data itself; use
# scripts/reset-local-db.sh explicitly.
#
# Checks:
#   1. The nine sample cases (Postman collection, run with Newman).
#   2. What was persisted: three normalised rows, NULL phone for case 2.
#   3. The application logs written during this run: every line is JSON, every
#      application event carries the correlation ID, no line contains patient data.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
log_dir="${MULE_LOG_DIR:-${MULE_HOME:?set MULE_HOME (or MULE_LOG_DIR)}/logs}"
psql() { docker exec -i patient-registration-postgres psql -U patient_owner -d patients -At "$@"; }

for port in 8081 8082 8083; do
    curl -s -o /dev/null --max-time 5 "http://localhost:$port/api/patients/PAT-000000" \
        || { echo "nothing answers on port $port; start the apps first" >&2; exit 1; }
done

# Log lines written from here on are this run's (earlier runs may have used another format).
declare -A log_start
for app in patient-exp-api patient-prc-api patient-sys-api; do
    log_start[$app]=$(( $( (cat "$log_dir/$app.log" 2>/dev/null || true) | wc -l) + 1 ))
done

rows=$(psql -c "SELECT count(*) FROM patient")
if [[ "$rows" != "0" ]]; then
    echo "patient table holds $rows rows; the sample cases need an empty table." >&2
    echo "Run scripts/reset-local-db.sh (destructive, asks for confirmation) and retry." >&2
    exit 1
fi

echo "== 1. sample cases (Newman)"
npx --yes newman@6.2.1 run postman/patient-registration.postman_collection.json \
    -e postman/patient-registration.local.postman_environment.json --disable-unicode

echo "== 2. persisted rows"
psql -F ' | ' -c "SELECT patient_id, given_name, family_name, sex, category, email,
                         coalesce(phone, '<null>'), consent_sms, source, status
                    FROM patient ORDER BY patient_id"
expected=$'PAT-000001 | Ana | Kovač | F | ADULT | ana.kovac@example.com | +38761111222 | f | PORTAL | ACTIVE
PAT-000002 | Luka | Petrović | M | MINOR | luka.petrovic@example.com | <null> | f | PORTAL | ACTIVE
PAT-000003 | Milena | Jović | F | SENIOR | milena.jovic@example.com | 065222333 | t | PORTAL | ACTIVE'
actual=$(psql -F ' | ' -c "SELECT patient_id, given_name, family_name, sex, category, email,
                                  coalesce(phone, '<null>'), consent_sms, source, status
                             FROM patient ORDER BY patient_id")
[[ "$actual" == "$expected" ]] || { echo "FAIL: persisted rows differ from the expected records" >&2; exit 1; }
echo "PASS: rows match the expected normalised records"

echo "== 3. logs"
pii='Ana|Kova|Luka|Petrovi|Milena|Jovi|Ivan|Mari|Sara|Ili|Petar|Babi|@example\.com|@Example\.com|111-222|61111222|222 333|222333|444 555|1985-04-12|2012-09-03|1950-01-20|1978-11-30|2030-05-01|1992-06-15'
status=0
sleep 2   # application loggers are asynchronous
for app in patient-exp-api patient-prc-api patient-sys-api; do
    f="$log_dir/$app.log"
    echo -n "$app: "
    node scripts/log-events.js check "$f" "${log_start[$app]}" || status=1
    leaks=$(tail -n +"${log_start[$app]}" "$f" | grep -cE "$pii" || true)
    echo "$app: $leaks lines with patient data"
    [[ "$leaks" == "0" ]] || status=1
done
[[ $status == 0 ]] && echo "PASS: JSON log lines, correlation IDs on every application event, no patient data" \
    || { echo "FAIL: log checks" >&2; exit 1; }
