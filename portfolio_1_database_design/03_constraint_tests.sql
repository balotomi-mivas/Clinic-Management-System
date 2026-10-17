/*
  LASUTH Clinic Management System
  Portfolio 1: proof that the integrity rules hold
  File: 03_constraint_tests.sql
  Each statement below is meant to FAIL. The error text is the evidence.
*/
SET search_path TO clinic;

\echo '>>> Test 1: book Dr Ogunleye at 09:05 on 21 Sep 2026 while his 09:00 slot (15 min) is live'
INSERT INTO appointment (patient_id, doctor_id, scheduled_at, reason)
VALUES (2, 1, '2026-09-21 09:05+01', 'Walk in');

\echo '>>> Test 2: cancelled slot can be reused, so this one SUCCEEDS'
UPDATE appointment SET status = 'CANCELLED' WHERE appointment_id = 3;
INSERT INTO appointment (patient_id, doctor_id, scheduled_at, reason)
VALUES (1, 3, '2026-09-22 09:30+01', 'Reuses a cancelled slot') RETURNING appointment_id, status;
DELETE FROM appointment WHERE reason = 'Reuses a cancelled slot';
UPDATE appointment SET status = 'COMPLETED' WHERE appointment_id = 3;

\echo '>>> Test 3: drug stock cannot go negative'
UPDATE drug SET stock_qty = stock_qty - 5000 WHERE drug_id = 1;

\echo '>>> Test 4: invalid genotype is rejected'
INSERT INTO patient (hospital_no, first_name, last_name, sex, date_of_birth, genotype)
VALUES ('LASUTH/2026/999999', 'Test', 'Patient', 'F', '1990-01-01', 'XY');

\echo '>>> Test 5: a consultation can have only one primary diagnosis'
INSERT INTO diagnosis (consultation_id, icd10_code, is_primary) VALUES (1, 'A01.0', TRUE);

\echo '>>> Test 6: diagnosis must use a known ICD 10 code'
INSERT INTO diagnosis (consultation_id, icd10_code) VALUES (1, 'ZZZ.9');

\echo '>>> Test 7: a lab result cannot be marked REPORTED without a value'
UPDATE lab_request SET status = 'REPORTED', result_value = NULL WHERE request_id = 1;

\echo '>>> Test 8: audit trail captured the diagnosis inserts'
SELECT audit_id, table_name, record_id, action, new_data->>'icd10_code' AS icd10
FROM audit_log ORDER BY audit_id;

\echo '>>> Test 9: patient history view'
SELECT * FROM v_patient_history ORDER BY visit_date;

\echo '>>> Test 10: invoice balances are derived, not stored'
SELECT * FROM v_invoice_balance ORDER BY invoice_id;
