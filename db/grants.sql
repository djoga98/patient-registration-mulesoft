-- Least-privilege grants for the runtime account used by patient-sys-api.
-- The application only inserts and reads patients; it cannot update, delete
-- or change the schema. Run after schema.sql, as the schema owner.
--
-- The role itself (with its password) is created outside version control:
-- locally by infrastructure/postgres-init/20-app-role.sh from the
-- APP_DB_PASSWORD environment variable, on a hosted database by the DBA.

GRANT CONNECT ON DATABASE patients TO patient_app;
GRANT USAGE ON SCHEMA public TO patient_app;
GRANT SELECT, INSERT ON TABLE patient TO patient_app;
GRANT USAGE ON SEQUENCE patient_id_seq TO patient_app;
