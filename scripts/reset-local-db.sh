#!/usr/bin/env bash
# DESTRUCTIVE: removes every patient from the LOCAL Docker database and
# restarts the ID sequence. Never run automatically; asks for confirmation
# unless --yes is given.
set -euo pipefail

if [[ "${1:-}" != "--yes" ]]; then
    read -r -p "Delete ALL rows in the local patient table? Type 'reset' to continue: " answer
    [[ "$answer" == "reset" ]] || { echo "aborted"; exit 1; }
fi

docker exec -i patient-registration-postgres \
    psql -v ON_ERROR_STOP=1 -U patient_owner -d patients \
    -c "TRUNCATE TABLE patient; ALTER SEQUENCE patient_id_seq RESTART WITH 1;"

echo "local patient table reset"
