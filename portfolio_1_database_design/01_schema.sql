/*
  LASUTH Clinic Management System
  Portfolio 1: Database Design and Modelling
  File: 01_schema.sql
  Target: PostgreSQL 16

  The schema is in Third Normal Form. Business rules that must never be
  broken (no negative drug stock, no double booked doctor, valid blood
  groups and genotypes) are enforced inside the database with constraints
  rather than left to the application.
*/

DROP SCHEMA IF EXISTS clinic CASCADE;
CREATE SCHEMA clinic;
SET search_path TO clinic;

/* btree_gist lets an exclusion constraint combine an equality column
   (doctor) with a range overlap test (appointment time). */
CREATE EXTENSION IF NOT EXISTS btree_gist;

/* ============ Organisation ============ */

CREATE TABLE department (
    department_id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(80)  NOT NULL UNIQUE,
    block_location  VARCHAR(80)  NOT NULL,
    extension_no    VARCHAR(10)
);

CREATE TABLE specialty (
    specialty_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE staff (
    staff_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    staff_no        VARCHAR(12)  NOT NULL UNIQUE,
    department_id   SMALLINT     NOT NULL REFERENCES department (department_id),
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    role            VARCHAR(20)  NOT NULL
                    CHECK (role IN ('DOCTOR','NURSE','LAB_SCIENTIST','PHARMACIST','RECORDS','CASHIER','ADMIN')),
    phone           VARCHAR(15),
    email           VARCHAR(120) UNIQUE,
    hire_date       DATE         NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

/* Subtype of staff. Shares the primary key so a doctor is always a staff
   member and doctor specific attributes are not repeated for nurses. */
CREATE TABLE doctor (
    staff_id          INTEGER PRIMARY KEY REFERENCES staff (staff_id),
    specialty_id      SMALLINT NOT NULL REFERENCES specialty (specialty_id),
    mdcn_licence_no   VARCHAR(20) NOT NULL UNIQUE,
    consultation_fee  NUMERIC(10,2) NOT NULL CHECK (consultation_fee >= 0),
    on_duty           BOOLEAN NOT NULL DEFAULT TRUE
);

/* ============ Patients ============ */

CREATE TABLE patient (
    patient_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hospital_no     VARCHAR(20)  NOT NULL UNIQUE,         /* card number, format LASUTH/2026/000123 */
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    sex             CHAR(1)      NOT NULL CHECK (sex IN ('M','F')),
    date_of_birth   DATE         NOT NULL CHECK (date_of_birth > DATE '1900-01-01'),
    phone           VARCHAR(15),
    address         VARCHAR(200),
    lga             VARCHAR(40),                           /* Local Government Area */
    blood_group     VARCHAR(3)   CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    genotype        VARCHAR(2)   CHECK (genotype IN ('AA','AS','AC','SS','SC')),
    nhis_no         VARCHAR(20)  UNIQUE,                   /* health insurance number, optional */
    registered_on   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE next_of_kin (
    nok_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      INTEGER     NOT NULL REFERENCES patient (patient_id) ON DELETE CASCADE,
    full_name       VARCHAR(100) NOT NULL,
    relationship    VARCHAR(30)  NOT NULL,
    phone           VARCHAR(15)  NOT NULL
);

CREATE TABLE allergy (
    patient_id      INTEGER     NOT NULL REFERENCES patient (patient_id) ON DELETE CASCADE,
    allergen        VARCHAR(60) NOT NULL,
    severity        VARCHAR(10) NOT NULL CHECK (severity IN ('MILD','MODERATE','SEVERE')),
    PRIMARY KEY (patient_id, allergen)
);

/* ============ Appointments and consultations ============ */

CREATE TABLE appointment (
    appointment_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      INTEGER     NOT NULL REFERENCES patient (patient_id),
    doctor_id       INTEGER     NOT NULL REFERENCES doctor (staff_id),
    scheduled_at    TIMESTAMPTZ NOT NULL,
    slot_minutes    SMALLINT    NOT NULL DEFAULT 15 CHECK (slot_minutes BETWEEN 5 AND 120),
    status          VARCHAR(12) NOT NULL DEFAULT 'BOOKED'
                    CHECK (status IN ('BOOKED','CHECKED_IN','COMPLETED','CANCELLED','NO_SHOW')),
    reason          VARCHAR(200),
    ends_at         TIMESTAMPTZ NOT NULL,    /* filled by trigger from slot_minutes */
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (ends_at > scheduled_at),

    /* A doctor cannot hold two live appointments whose time ranges overlap.
       Cancelled and no show slots are ignored so the slot can be reused.
       ends_at is stored because timestamptz plus interval is not immutable
       and therefore cannot be used inside an index expression. */
    CONSTRAINT no_double_booking EXCLUDE USING gist (
        doctor_id WITH =,
        tstzrange(scheduled_at, ends_at) WITH &&
    ) WHERE (status NOT IN ('CANCELLED','NO_SHOW'))
);

CREATE OR REPLACE FUNCTION fn_set_appointment_end() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.ends_at := NEW.scheduled_at + make_interval(mins => NEW.slot_minutes);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_appointment_end
    BEFORE INSERT OR UPDATE OF scheduled_at, slot_minutes ON appointment
    FOR EACH ROW EXECUTE FUNCTION fn_set_appointment_end();

CREATE TABLE consultation (
    consultation_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id  BIGINT      NOT NULL UNIQUE REFERENCES appointment (appointment_id),
    temperature_c   NUMERIC(4,1) CHECK (temperature_c BETWEEN 30 AND 45),
    bp_systolic     SMALLINT     CHECK (bp_systolic BETWEEN 50 AND 260),
    bp_diastolic    SMALLINT     CHECK (bp_diastolic BETWEEN 30 AND 160),
    weight_kg       NUMERIC(5,1) CHECK (weight_kg BETWEEN 0.5 AND 400),
    clinical_notes  TEXT,
    consulted_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE icd10_code (
    code            VARCHAR(8) PRIMARY KEY,
    description     VARCHAR(200) NOT NULL
);

CREATE TABLE diagnosis (
    consultation_id BIGINT     NOT NULL REFERENCES consultation (consultation_id) ON DELETE CASCADE,
    icd10_code      VARCHAR(8) NOT NULL REFERENCES icd10_code (code),
    is_primary      BOOLEAN    NOT NULL DEFAULT FALSE,
    PRIMARY KEY (consultation_id, icd10_code)
);
/* Only one primary diagnosis per consultation */
CREATE UNIQUE INDEX ux_diagnosis_one_primary ON diagnosis (consultation_id) WHERE is_primary;

/* ============ Pharmacy ============ */

CREATE TABLE drug (
    drug_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(80)  NOT NULL,
    form            VARCHAR(20)  NOT NULL CHECK (form IN ('TABLET','CAPSULE','SYRUP','INJECTION','CREAM','INFUSION')),
    strength        VARCHAR(30)  NOT NULL,
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    stock_qty       INTEGER      NOT NULL CHECK (stock_qty >= 0),   /* stock can never go negative */
    reorder_level   INTEGER      NOT NULL DEFAULT 50,
    UNIQUE (name, form, strength)
);

CREATE TABLE prescription (
    prescription_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    consultation_id BIGINT      NOT NULL REFERENCES consultation (consultation_id),
    prescribed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          VARCHAR(12) NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','DISPENSED','CANCELLED')),
    dispensed_by    INTEGER     REFERENCES staff (staff_id),
    dispensed_at    TIMESTAMPTZ
);

CREATE TABLE prescription_item (
    prescription_id BIGINT      NOT NULL REFERENCES prescription (prescription_id) ON DELETE CASCADE,
    drug_id         INTEGER     NOT NULL REFERENCES drug (drug_id),
    dose            VARCHAR(30) NOT NULL,
    frequency       VARCHAR(30) NOT NULL,
    duration_days   SMALLINT    NOT NULL CHECK (duration_days > 0),
    quantity        INTEGER     NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (prescription_id, drug_id)
);

/* ============ Laboratory ============ */

CREATE TABLE lab_test (
    test_id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name             VARCHAR(80)  NOT NULL UNIQUE,
    sample_type      VARCHAR(20)  NOT NULL,
    price            NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    turnaround_hours SMALLINT     NOT NULL
);

CREATE TABLE lab_request (
    request_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    consultation_id BIGINT      NOT NULL REFERENCES consultation (consultation_id),
    test_id         SMALLINT    NOT NULL REFERENCES lab_test (test_id),
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          VARCHAR(12) NOT NULL DEFAULT 'REQUESTED'
                    CHECK (status IN ('REQUESTED','COLLECTED','REPORTED','CANCELLED')),
    result_value    VARCHAR(40),
    result_unit     VARCHAR(20),
    is_abnormal     BOOLEAN,
    reported_by     INTEGER     REFERENCES staff (staff_id),
    reported_at     TIMESTAMPTZ,
    CHECK (status <> 'REPORTED' OR (result_value IS NOT NULL AND reported_at IS NOT NULL))
);

/* ============ Billing ============ */

CREATE TABLE invoice (
    invoice_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      INTEGER     NOT NULL REFERENCES patient (patient_id),
    consultation_id BIGINT      REFERENCES consultation (consultation_id),
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          VARCHAR(10) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','PAID','VOID'))
);

CREATE TABLE invoice_line (
    invoice_id      BIGINT       NOT NULL REFERENCES invoice (invoice_id) ON DELETE CASCADE,
    line_no         SMALLINT     NOT NULL,
    description     VARCHAR(120) NOT NULL,
    amount          NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    PRIMARY KEY (invoice_id, line_no)
);

CREATE TABLE payment (
    payment_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id      BIGINT       NOT NULL REFERENCES invoice (invoice_id),
    amount          NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method          VARCHAR(10)  NOT NULL CHECK (method IN ('CASH','POS','TRANSFER','NHIS')),
    cashier_id      INTEGER      NOT NULL REFERENCES staff (staff_id),
    paid_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

/* ============ Audit trail ============ */

CREATE TABLE audit_log (
    audit_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name      VARCHAR(40) NOT NULL,
    record_id       BIGINT      NOT NULL,
    action          VARCHAR(6)  NOT NULL,
    changed_by      TEXT        NOT NULL DEFAULT current_user,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    old_data        JSONB,
    new_data        JSONB
);

CREATE OR REPLACE FUNCTION fn_audit() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_row JSONB := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
BEGIN
    /* TG_ARGV[0] names the key column, so one function serves every audited table. */
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data)
    VALUES (TG_TABLE_NAME,
            (v_row ->> TG_ARGV[0])::BIGINT,
            TG_OP,
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
    RETURN COALESCE(NEW, OLD);
END $$;

/* Clinical results and diagnoses are medico legal records, so every change is kept. */
CREATE TRIGGER trg_audit_lab_result
    AFTER UPDATE OF result_value, is_abnormal, status ON lab_request
    FOR EACH ROW EXECUTE FUNCTION fn_audit('request_id');

CREATE TRIGGER trg_audit_diagnosis
    AFTER INSERT OR UPDATE OR DELETE ON diagnosis
    FOR EACH ROW EXECUTE FUNCTION fn_audit('consultation_id');

/* ============ Views ============ */

/* One row per diagnosis event: what a doctor sees when opening a folder. */
CREATE VIEW v_patient_history AS
SELECT p.hospital_no,
       p.first_name || ' ' || p.last_name           AS patient_name,
       a.scheduled_at::date                          AS visit_date,
       s.first_name || ' ' || s.last_name            AS doctor_name,
       sp.name                                       AS specialty,
       d.icd10_code,
       i.description                                 AS diagnosis,
       d.is_primary
FROM patient p
JOIN appointment  a  ON a.patient_id = p.patient_id
JOIN consultation c  ON c.appointment_id = a.appointment_id
JOIN doctor       dr ON dr.staff_id = a.doctor_id
JOIN staff        s  ON s.staff_id = dr.staff_id
JOIN specialty    sp ON sp.specialty_id = dr.specialty_id
LEFT JOIN diagnosis  d ON d.consultation_id = c.consultation_id
LEFT JOIN icd10_code i ON i.code = d.icd10_code;

/* Invoice balance computed, never stored, so it cannot drift from the payments. */
CREATE VIEW v_invoice_balance AS
SELECT inv.invoice_id,
       inv.patient_id,
       inv.status,
       COALESCE(l.total, 0)                       AS total_billed,
       COALESCE(pm.paid, 0)                       AS total_paid,
       COALESCE(l.total, 0) - COALESCE(pm.paid, 0) AS balance
FROM invoice inv
LEFT JOIN (SELECT invoice_id, SUM(amount) total FROM invoice_line GROUP BY invoice_id) l  ON l.invoice_id = inv.invoice_id
LEFT JOIN (SELECT invoice_id, SUM(amount) paid  FROM payment      GROUP BY invoice_id) pm ON pm.invoice_id = inv.invoice_id;

/* ============ Role based access ============ */

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_doctor')     THEN CREATE ROLE role_doctor;     END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_pharmacist') THEN CREATE ROLE role_pharmacist; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_cashier')    THEN CREATE ROLE role_cashier;    END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_records')    THEN CREATE ROLE role_records;    END IF;
END $$;

GRANT USAGE ON SCHEMA clinic TO role_doctor, role_pharmacist, role_cashier, role_records;
GRANT SELECT ON ALL TABLES IN SCHEMA clinic TO role_doctor;
GRANT INSERT, UPDATE ON consultation, diagnosis, prescription, prescription_item, lab_request TO role_doctor;
GRANT SELECT ON drug, prescription, prescription_item, patient TO role_pharmacist;
GRANT UPDATE (stock_qty) ON drug TO role_pharmacist;
GRANT UPDATE (status, dispensed_by, dispensed_at) ON prescription TO role_pharmacist;
GRANT SELECT ON invoice, invoice_line, payment, v_invoice_balance, patient TO role_cashier;
GRANT INSERT ON payment TO role_cashier;
GRANT SELECT, INSERT, UPDATE ON patient, next_of_kin, allergy, appointment TO role_records;
/* Cashiers and records officers get no access to diagnosis or clinical notes. */
