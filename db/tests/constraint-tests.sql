-- Integration test of the patient table constraints, run as the application role.
-- Everything happens in one transaction that is rolled back: no data is left behind
-- (sequence values consumed by nextval are not returned; IDs may show gaps).
--
--   scripts/db-integration-test.sh
\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE results (check_name text, passed boolean) ON COMMIT DROP;

-- 1. The statement used by patient-sys-api inserts a new identity ...
WITH ins AS (
    INSERT INTO patient (given_name, family_name, birth_date, sex, category, email, phone,
                         consent_data_processing, consent_sms, source)
    VALUES ('Zz-test', 'Constraint', CAST('1990-02-03' AS DATE), 'O', 'ADULT', 'c@test.invalid',
            CAST(NULL AS VARCHAR), true, false, 'PORTAL')
    ON CONFLICT ON CONSTRAINT uq_patient_identity DO NOTHING
    RETURNING patient_id, status, registered_at
)
INSERT INTO results
SELECT 'insert returns generated PAT-###### ID, ACTIVE status, timestamp',
       count(*) = 1 AND bool_and(patient_id ~ '^PAT-[0-9]{6}$' AND status = 'ACTIVE' AND registered_at IS NOT NULL)
  FROM ins;

-- 2. ... and inserts nothing for the same normalised identity (-> 409 in the API).
WITH ins AS (
    INSERT INTO patient (given_name, family_name, birth_date, sex, category, email,
                         consent_data_processing, consent_sms, source)
    VALUES ('Zz-test', 'Constraint', CAST('1990-02-03' AS DATE), 'F', 'ADULT', 'other@test.invalid',
            true, false, 'PORTAL')
    ON CONFLICT ON CONSTRAINT uq_patient_identity DO NOTHING
    RETURNING patient_id
)
INSERT INTO results SELECT 'same name + birth date inserts no row', count(*) = 0 FROM ins;

-- 3. A different birth date is a different patient.
WITH ins AS (
    INSERT INTO patient (given_name, family_name, birth_date, sex, category, email,
                         consent_data_processing, consent_sms, source)
    VALUES ('Zz-test', 'Constraint', CAST('1990-02-04' AS DATE), 'F', 'ADULT', 'c@test.invalid',
            true, false, 'PORTAL')
    ON CONFLICT ON CONSTRAINT uq_patient_identity DO NOTHING
    RETURNING patient_id
)
INSERT INTO results SELECT 'different birth date inserts a row', count(*) = 1 FROM ins;

-- 4. Without ON CONFLICT the unique constraint itself rejects the duplicate.
DO $$
BEGIN
    INSERT INTO patient (given_name, family_name, birth_date, sex, category, email,
                         consent_data_processing, consent_sms, source)
    VALUES ('Zz-test', 'Constraint', DATE '1990-02-03', 'M', 'ADULT', 'x@test.invalid', true, false, 'PORTAL');
    INSERT INTO results VALUES ('unique constraint rejects duplicate identity', false);
EXCEPTION WHEN unique_violation THEN
    INSERT INTO results VALUES ('unique constraint rejects duplicate identity', true);
END $$;

-- 5. Closed code lists are enforced.
DO $$
BEGIN
    INSERT INTO patient (given_name, family_name, birth_date, sex, category, email,
                         consent_data_processing, consent_sms, source)
    VALUES ('Zz-test', 'Codes', DATE '1990-01-01', 'X', 'ADULT', 'x@test.invalid', true, false, 'PORTAL');
    INSERT INTO results VALUES ('sex outside F/M/O rejected', false);
EXCEPTION WHEN check_violation THEN
    INSERT INTO results VALUES ('sex outside F/M/O rejected', true);
END $$;

-- 6. The application role cannot delete or change records.
DO $$
BEGIN
    DELETE FROM patient WHERE given_name = 'Zz-test';
    INSERT INTO results VALUES ('application role cannot delete', false);
EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO results VALUES ('application role cannot delete', true);
END $$;

DO $$
BEGIN
    UPDATE patient SET status = 'INACTIVE' WHERE given_name = 'Zz-test';
    INSERT INTO results VALUES ('application role cannot update', false);
EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO results VALUES ('application role cannot update', true);
END $$;

SELECT CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result, check_name FROM results;
SELECT CASE WHEN bool_and(passed) THEN 'ALL PASSED' ELSE 'FAILURES' END AS summary FROM results;

ROLLBACK;
