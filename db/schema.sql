-- Acme Clinic patient registration: record store owned by patient-sys-api.
--
-- Idempotent: safe to run repeatedly against an existing database. It never
-- drops or truncates data. A destructive reset is a separate, explicit step
-- (see scripts/reset-local-db.sh).
--
-- Business rules (future birth dates, consent, name normalisation, category
-- calculation) live in patient-prc-api. The constraints below protect record
-- integrity only: identity uniqueness, closed code lists and the ID format.

CREATE SEQUENCE IF NOT EXISTS patient_id_seq
    AS INTEGER
    START WITH 1
    MINVALUE 1
    MAXVALUE 999999   -- PAT- plus six digits; exhaustion fails loudly instead of widening the ID
    NO CYCLE;

CREATE TABLE IF NOT EXISTS patient (
    patient_id              VARCHAR(10)  NOT NULL
                            DEFAULT ('PAT-' || lpad(nextval('patient_id_seq')::text, 6, '0')),
    given_name              VARCHAR(100) NOT NULL,
    family_name             VARCHAR(100) NOT NULL,
    birth_date              DATE         NOT NULL,
    sex                     CHAR(1)      NOT NULL,
    category                VARCHAR(10)  NOT NULL,
    email                   VARCHAR(254) NOT NULL,
    phone                   VARCHAR(32),
    consent_data_processing BOOLEAN      NOT NULL,
    consent_sms             BOOLEAN      NOT NULL DEFAULT FALSE,
    source                  VARCHAR(20)  NOT NULL,
    status                  VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    registered_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT pk_patient           PRIMARY KEY (patient_id),
    -- The duplicate check. patient-sys-api inserts with
    -- ON CONFLICT ON CONSTRAINT uq_patient_identity DO NOTHING and returns 409
    -- when no row was inserted.
    CONSTRAINT uq_patient_identity  UNIQUE (given_name, family_name, birth_date),
    CONSTRAINT ck_patient_id_format CHECK (patient_id ~ '^PAT-[0-9]{6}$'),
    CONSTRAINT ck_patient_sex       CHECK (sex IN ('F', 'M', 'O')),
    CONSTRAINT ck_patient_category  CHECK (category IN ('MINOR', 'ADULT', 'SENIOR')),
    CONSTRAINT ck_patient_status    CHECK (status IN ('ACTIVE', 'INACTIVE'))
);

ALTER SEQUENCE patient_id_seq OWNED BY patient.patient_id;

COMMENT ON TABLE  patient                IS 'Registered clinic patients (record format of patient-sys-api).';
COMMENT ON COLUMN patient.registered_at  IS 'Registration instant; stored as timestamptz, served in UTC.';
COMMENT ON COLUMN patient.source         IS 'Registration channel, e.g. PORTAL.';
