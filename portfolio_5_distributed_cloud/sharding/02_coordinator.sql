/*
  LASUTH Clinic Management System
  Portfolio 5: hash sharding with declarative partitioning and postgres_fdw
  File: sharding/02_coordinator.sql   (run on the coordinator, port 5432, database lasuth)

  The coordinator holds no encounter rows itself. dist.encounter is a
  partitioned table whose two partitions are foreign tables living on two
  separate PostgreSQL servers. Rows are routed by hash(patient_id), so every
  visit of one patient lands on the same shard and a folder lookup touches
  one server only.
*/
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

DROP SCHEMA IF EXISTS dist CASCADE;
DROP SERVER IF EXISTS shard_a CASCADE;
DROP SERVER IF EXISTS shard_b CASCADE;

CREATE SERVER shard_a FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5434', dbname 'lasuth_shard', async_capable 'true', fetch_size '10000', batch_size '1000');
CREATE SERVER shard_b FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5435', dbname 'lasuth_shard', async_capable 'true', fetch_size '10000', batch_size '1000');
CREATE USER MAPPING FOR CURRENT_USER SERVER shard_a OPTIONS (user 'postgres');
CREATE USER MAPPING FOR CURRENT_USER SERVER shard_b OPTIONS (user 'postgres');

CREATE SCHEMA dist;
CREATE TABLE dist.encounter (
    encounter_id   BIGINT       NOT NULL,
    patient_id     INTEGER      NOT NULL,
    hospital_no    VARCHAR(20)  NOT NULL,
    visit_date     TIMESTAMPTZ  NOT NULL,
    doctor_id      INTEGER      NOT NULL,
    primary_icd10  VARCHAR(8),
    total_billed   NUMERIC(12,2)
) PARTITION BY HASH (patient_id);

CREATE FOREIGN TABLE dist.encounter_shard_a PARTITION OF dist.encounter
    FOR VALUES WITH (MODULUS 2, REMAINDER 0)
    SERVER shard_a OPTIONS (schema_name 'clinic_shard', table_name 'encounter');
CREATE FOREIGN TABLE dist.encounter_shard_b PARTITION OF dist.encounter
    FOR VALUES WITH (MODULUS 2, REMAINDER 1)
    SERVER shard_b OPTIONS (schema_name 'clinic_shard', table_name 'encounter');

/* Load: the coordinator routes each row to its shard automatically */
INSERT INTO dist.encounter
SELECT c.consultation_id, a.patient_id, p.hospital_no, a.scheduled_at, a.doctor_id,
       d.icd10_code, COALESCE(b.total_billed, 0)
FROM clinic.consultation c
JOIN clinic.appointment a ON a.appointment_id = c.appointment_id
JOIN clinic.patient p     ON p.patient_id = a.patient_id
LEFT JOIN clinic.diagnosis d ON d.consultation_id = c.consultation_id AND d.is_primary
LEFT JOIN (SELECT i.consultation_id, sum(il.amount) AS total_billed      /* one grouped pass, not a lookup per row */
           FROM clinic.invoice i JOIN clinic.invoice_line il USING (invoice_id)
           GROUP BY i.consultation_id) b ON b.consultation_id = c.consultation_id;

ANALYZE dist.encounter_shard_a;
ANALYZE dist.encounter_shard_b;
