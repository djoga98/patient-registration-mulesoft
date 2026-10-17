#!/bin/bash
# Runs once, on first start of an empty data volume (docker-entrypoint-initdb.d).
# Creates the least-privilege runtime role and applies db/grants.sql.
set -euo pipefail

: "${APP_DB_PASSWORD:?APP_DB_PASSWORD must be set (see infrastructure/.env.example)}"

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" \
     -v app_password="$APP_DB_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE patient_app LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'patient_app') \gexec
ALTER ROLE patient_app WITH LOGIN PASSWORD :'app_password';
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -f /docker-entrypoint-initdb.d/grants.sql.inc
