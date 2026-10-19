/*
  LASUTH Clinic Management System
  Portfolio 2: the same six queries after tuning
  File: 05_optimised_queries.sql

  Run after 04_optimisation.sql. Q1, Q3, Q4 and Q5 keep their text and
  benefit from the new indexes and the rewritten balance view. Q2 is
  rewritten to be sargable and Q6 reads the materialised view.
*/
SET search_path TO clinic;

/* Q1. Folder retrieval: full history of one patient at the consulting room */
SELECT *
FROM v_patient_history
WHERE hospital_no = 'LASUTH/2015/025017'
ORDER BY visit_date DESC;

/* Q2. Doctor's clinic list for a day. The cast on scheduled_at is replaced by
   a half open range so the composite index can be used directly. */
SELECT a.appointment_id, a.scheduled_at, p.hospital_no, p.first_name, p.last_name, a.reason, a.status
FROM appointment a
JOIN patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 14
  AND a.scheduled_at >= TIMESTAMPTZ '2026-10-14 00:00+01'
  AND a.scheduled_at <  TIMESTAMPTZ '2026-10-15 00:00+01'
ORDER BY a.scheduled_at;

/* Q3. Front desk search: patient forgot the card, search by surname and date of birth */
SELECT patient_id, hospital_no, first_name, last_name, date_of_birth, phone
FROM patient
WHERE lower(last_name) = 'okonkwo'
  AND date_of_birth = DATE '1954-03-29';

/* Q4. Laboratory worklist: oldest 50 outstanding requests */
SELECT r.request_id, r.requested_at, t.name AS test, p.hospital_no, p.last_name
FROM lab_request r
JOIN lab_test t      ON t.test_id = r.test_id
JOIN consultation c  ON c.consultation_id = r.consultation_id
JOIN appointment a   ON a.appointment_id = c.appointment_id
JOIN patient p       ON p.patient_id = a.patient_id
WHERE r.status = 'REQUESTED'
ORDER BY r.requested_at
LIMIT 50;

/* Q5. Cashier: outstanding balance for one patient */
SELECT invoice_id, total_billed, total_paid, balance
FROM v_invoice_balance
WHERE patient_id = 25018 AND balance > 0;

/* Q6. Management report, read from the precomputed materialised view */
SELECT month, department, icd10_code, cases
FROM mv_monthly_disease_burden
WHERE month >= TIMESTAMPTZ '2026-01-01' AND month < TIMESTAMPTZ '2027-01-01'
ORDER BY 1, 2, cases DESC;
