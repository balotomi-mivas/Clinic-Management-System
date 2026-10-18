/*
  LASUTH Clinic Management System
  Portfolio 2: Query Processing and Optimisation
  File: 01_generate_volume_data.sql

  Loads a volume close to two years of LASUTH outpatient activity so that
  execution plans reflect real data sizes. setseed() makes the run
  repeatable: the same rows are produced every time.

  Run after portfolio_1_database_design/02_seed_data.sql.
*/
SET search_path TO clinic;
SELECT setseed(0.2026);

/* 115 more doctors, giving 120 in total across the clinical departments */
INSERT INTO staff (staff_no, department_id, first_name, last_name, role, hire_date)
SELECT 'LS/MD/' || lpad((g + 5)::text, 4, '0'),
       (ARRAY[1,2,3,4,5])[1 + (g % 5)],
       (ARRAY['Ade','Bola','Chika','Damilola','Emeka','Folake','Gbenga','Hauwa','Ibukun','Jide','Kelechi','Lola','Musa','Nkechi','Ope','Rotimi','Segun','Temitope','Uche','Yinka'])[1 + (g % 20)],
       (ARRAY['Adebisi','Bankole','Coker','Danjuma','Eze','Fashola','Giwa','Idowu','Jegede','Kolawole','Lawal','Mbah','Nwachukwu','Ojo','Popoola','Quadri','Raji','Sanni','Tijani','Usman'])[1 + ((g * 7) % 20)],
       'DOCTOR',
       DATE '2010-01-01' + (g * 37)
FROM generate_series(1, 115) g;

INSERT INTO doctor (staff_id, specialty_id, mdcn_licence_no, consultation_fee)
SELECT s.staff_id, 1 + (s.staff_id % 7), 'MDCN/R/' || (60000 + s.staff_id), 5000 + (s.staff_id % 4) * 1500
FROM staff s
WHERE s.role = 'DOCTOR' AND NOT EXISTS (SELECT 1 FROM doctor d WHERE d.staff_id = s.staff_id);

/* 60,000 patients */
INSERT INTO patient (hospital_no, first_name, last_name, sex, date_of_birth, phone, lga, blood_group, genotype, nhis_no, registered_on)
SELECT 'LASUTH/' || (2015 + g % 11) || '/' || lpad((g + 3)::text, 6, '0'),
       (ARRAY['Aisha','Bisi','Chiamaka','Dayo','Ebun','Femi','Ganiyu','Hadiza','Ifeanyi','Joke','Kunle','Lami','Mojisola','Ngozi','Olu','Peju','Rasheed','Sade','Tobi','Wale','Yemi','Zainab'])[1 + (g % 22)],
       (ARRAY['Abiodun','Adeleke','Akande','Balogun','Chukwu','Dada','Egwu','Falana','Hassan','Ibrahim','Johnson','Kalu','Lawson','Mohammed','Nnamdi','Odunsi','Okonkwo','Olatunji','Onuoha','Salako','Thomas','Williams','Yusuf','Zubair'])[1 + ((g * 13) % 24)],
       CASE WHEN random() < 0.54 THEN 'F' ELSE 'M' END,
       DATE '1940-01-01' + (random() * 30000)::int,
       '080' || lpad((random() * 99999999)::bigint::text, 8, '0'),
       (ARRAY['Ikeja','Agege','Alimosho','Mushin','Oshodi Isolo','Kosofe','Ikorodu','Surulere','Ifako Ijaiye','Somolu'])[1 + (g % 10)],
       (ARRAY['O+','O+','O+','A+','B+','B+','AB+','O-','A-','B-'])[1 + (g % 10)],
       (ARRAY['AA','AA','AA','AA','AA','AA','AS','AS','AC','SS'])[1 + ((g * 3) % 10)],
       CASE WHEN g % 4 = 0 THEN 'NHIS/LA/' || (100000 + g) END,
       TIMESTAMPTZ '2015-01-01' + (random() * 3800) * INTERVAL '1 day'
FROM generate_series(1, 60000) g;

/* 400,000 appointments. Each doctor runs a 16 slot afternoon clinic every third
   day, so no two live slots for the same doctor overlap and the exclusion
   constraint is satisfied by construction. */
WITH docs AS (
    SELECT staff_id, row_number() OVER (ORDER BY staff_id) - 1 AS dn FROM doctor
), pts AS (
    SELECT patient_id, row_number() OVER (ORDER BY patient_id) - 1 AS pn FROM patient
), slots AS (
    SELECT g, (g % 120) AS dn, (g / 120) AS slot_no,
           abs(hashint4(g)) % (SELECT count(*) FROM patient) AS pn
    FROM generate_series(0, 399999) g
)
INSERT INTO appointment (patient_id, doctor_id, scheduled_at, slot_minutes, status, reason, created_at)
SELECT pt.patient_id,
       d.staff_id,
       TIMESTAMPTZ '2025-02-01 12:00+01'
           + ((s.slot_no / 16) * 3 + (s.dn % 3)) * INTERVAL '1 day'
           + (s.slot_no % 16) * INTERVAL '15 minutes',
       15,
       CASE WHEN TIMESTAMPTZ '2025-02-01 12:00+01'
                 + ((s.slot_no / 16) * 3 + (s.dn % 3)) * INTERVAL '1 day' > TIMESTAMPTZ '2026-10-16' THEN 'BOOKED'
            WHEN random() < 0.86 THEN 'COMPLETED'
            WHEN random() < 0.5  THEN 'CANCELLED'
            ELSE 'NO_SHOW' END,
       (ARRAY['Fever','Follow up','Cough','Headache','Antenatal visit','BP review','Abdominal pain','Body pains','Diabetes review','Immunisation'])[1 + (s.g % 10)],
       TIMESTAMPTZ '2025-01-15'
FROM slots s JOIN docs d ON d.dn = s.dn JOIN pts pt ON pt.pn = s.pn;

/* Consultation for every completed appointment */
INSERT INTO consultation (appointment_id, temperature_c, bp_systolic, bp_diastolic, weight_kg, clinical_notes, consulted_at)
SELECT a.appointment_id,
       round((36 + random() * 3.5)::numeric, 1),
       100 + (random() * 70)::int,
       60 + (random() * 40)::int,
       round((15 + random() * 85)::numeric, 1),
       'Seen and reviewed.',
       a.scheduled_at + INTERVAL '10 minutes'
FROM appointment a
WHERE a.status = 'COMPLETED' AND NOT EXISTS (SELECT 1 FROM consultation c WHERE c.appointment_id = a.appointment_id);

/* Diagnoses: malaria and hypertension dominate, as in Lagos outpatient practice */
ALTER TABLE diagnosis DISABLE TRIGGER trg_audit_diagnosis;   /* bulk history load, not a clinical edit */
INSERT INTO diagnosis (consultation_id, icd10_code, is_primary)
SELECT c.consultation_id,
       (ARRAY['B50.9','B50.9','B50.9','B54','I10','I10','E11.9','A01.0','J06.9','J06.9','A09','N39.0','D64.9','J18.9','D57.1','O14.9'])[1 + (abs(hashint8(c.consultation_id)) % 16)],
       TRUE
FROM consultation c
WHERE NOT EXISTS (SELECT 1 FROM diagnosis d WHERE d.consultation_id = c.consultation_id);
ALTER TABLE diagnosis ENABLE TRIGGER trg_audit_diagnosis;

/* Lab requests for roughly 70 percent of consultations; the last 10 days are still pending */
INSERT INTO lab_request (consultation_id, test_id, requested_at, status, result_value, is_abnormal, reported_by, reported_at)
SELECT c.consultation_id,
       1 + (abs(hashint8(c.consultation_id * 7)) % 8),
       c.consulted_at + INTERVAL '5 minutes',
       CASE WHEN c.consulted_at > TIMESTAMPTZ '2026-10-06' THEN 'REQUESTED' ELSE 'REPORTED' END,
       CASE WHEN c.consulted_at > TIMESTAMPTZ '2026-10-06' THEN NULL ELSE 'See report' END,
       CASE WHEN c.consulted_at > TIMESTAMPTZ '2026-10-06' THEN NULL ELSE random() < 0.3 END,
       CASE WHEN c.consulted_at > TIMESTAMPTZ '2026-10-06' THEN NULL ELSE 7 END,
       CASE WHEN c.consulted_at > TIMESTAMPTZ '2026-10-06' THEN NULL ELSE c.consulted_at + INTERVAL '3 hours' END
FROM consultation c
WHERE c.consultation_id > 3 AND random() < 0.7;

/* Prescriptions and items */
INSERT INTO prescription (consultation_id, prescribed_at, status)
SELECT consultation_id, consulted_at + INTERVAL '15 minutes',
       CASE WHEN consulted_at > TIMESTAMPTZ '2026-10-11' THEN 'PENDING' ELSE 'DISPENSED' END
FROM consultation WHERE consultation_id > 3;

INSERT INTO prescription_item (prescription_id, drug_id, dose, frequency, duration_days, quantity)
SELECT p.prescription_id, 1 + (abs(hashint8(p.prescription_id)) % 10), '1 unit', 'twice daily', 5, 10
FROM prescription p WHERE p.prescription_id > 3;

/* Invoices with one line each, about 80 percent paid */
INSERT INTO invoice (patient_id, consultation_id, issued_at, status)
SELECT a.patient_id, c.consultation_id, c.consulted_at, CASE WHEN random() < 0.8 THEN 'PAID' ELSE 'OPEN' END
FROM consultation c JOIN appointment a ON a.appointment_id = c.appointment_id
WHERE c.consultation_id > 3;

INSERT INTO invoice_line (invoice_id, line_no, description, amount)
SELECT i.invoice_id, 1, 'Consultation', 5000 + (i.invoice_id % 4) * 1500
FROM invoice i WHERE i.invoice_id > 3;

INSERT INTO payment (invoice_id, amount, method, cashier_id, paid_at)
SELECT i.invoice_id, 5000 + (i.invoice_id % 4) * 1500,
       (ARRAY['CASH','POS','TRANSFER','NHIS'])[1 + (i.invoice_id % 4)::int], 10, i.issued_at + INTERVAL '30 minutes'
FROM invoice i WHERE i.invoice_id > 3 AND i.status = 'PAID';

/* Fresh statistics so the planner sees the real distribution */
VACUUM ANALYZE;

SELECT 'patient' AS table_name, count(*) FROM patient
UNION ALL SELECT 'doctor', count(*) FROM doctor
UNION ALL SELECT 'appointment', count(*) FROM appointment
UNION ALL SELECT 'consultation', count(*) FROM consultation
UNION ALL SELECT 'diagnosis', count(*) FROM diagnosis
UNION ALL SELECT 'lab_request', count(*) FROM lab_request
UNION ALL SELECT 'prescription', count(*) FROM prescription
UNION ALL SELECT 'prescription_item', count(*) FROM prescription_item
UNION ALL SELECT 'invoice', count(*) FROM invoice
UNION ALL SELECT 'payment', count(*) FROM payment;
