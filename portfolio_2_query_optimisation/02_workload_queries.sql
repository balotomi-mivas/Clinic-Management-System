/*
  LASUTH Clinic Management System
  Portfolio 2: the six queries that carry most of the daily load
  File: 02_workload_queries.sql

  These are written the way they first appeared in the application,
  before any tuning. 04_optimisation.sql holds the indexes and rewrites,
  and the benchmark harness (03_benchmark.py) runs both versions.
*/
SET search_path TO clinic;

/* Q1. Folder retrieval: full history of one patient at the consulting room */
SELECT *
FROM v_patient_history
WHERE hospital_no = 'LASUTH/2015/025017'
ORDER BY visit_date DESC;

/* Q2. Doctor's clinic list for a day (written with a cast on the column) */
SELECT a.appointment_id, a.scheduled_at, p.hospital_no, p.first_name, p.last_name, a.reason, a.status
FROM appointment a
JOIN patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 14
  AND a.scheduled_at::date = DATE '2026-10-14'
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

/* Q6. Management report: monthly disease burden for 2026 by department */
SELECT date_trunc('month', c.consulted_at) AS month,
       dep.name AS department,
       d.icd10_code,
       count(*) AS cases
FROM diagnosis d
JOIN consultation c ON c.consultation_id = d.consultation_id
JOIN appointment a  ON a.appointment_id = c.appointment_id
JOIN staff s        ON s.staff_id = a.doctor_id
JOIN department dep ON dep.department_id = s.department_id
WHERE c.consulted_at >= TIMESTAMPTZ '2026-01-01' AND c.consulted_at < TIMESTAMPTZ '2027-01-01'
GROUP BY 1, 2, 3
ORDER BY 1, 2, cases DESC;
