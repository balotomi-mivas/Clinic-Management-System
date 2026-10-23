/*
  LASUTH Clinic Management System
  Portfolio 5: Distributed and Cloud Database
  File: sharding/01_shard_node.sql
  Run on EACH shard server (ports 5434 and 5435 in the test setup):
      psql -p 5434 -U postgres -f 01_shard_node.sql
      psql -p 5435 -U postgres -f 01_shard_node.sql
*/
DROP DATABASE IF EXISTS lasuth_shard;
CREATE DATABASE lasuth_shard;
\connect lasuth_shard
CREATE SCHEMA clinic_shard;
CREATE TABLE clinic_shard.encounter (
    encounter_id   BIGINT       PRIMARY KEY,
    patient_id     INTEGER      NOT NULL,
    hospital_no    VARCHAR(20)  NOT NULL,
    visit_date     TIMESTAMPTZ  NOT NULL,
    doctor_id      INTEGER      NOT NULL,
    primary_icd10  VARCHAR(8),
    total_billed   NUMERIC(12,2)
);
/* The shard key is also the leading index column, so a patient's visits are one index range on one node. */
CREATE INDEX ix_shard_encounter_patient ON clinic_shard.encounter (patient_id, visit_date);
