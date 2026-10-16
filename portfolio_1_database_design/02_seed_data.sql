/*
  LASUTH Clinic Management System
  Portfolio 1: reference data and a small hand written sample
  File: 02_seed_data.sql

  All names, phone numbers and card numbers are invented for coursework.
*/
SET search_path TO clinic;

INSERT INTO department (name, block_location, extension_no) VALUES
 ('General Outpatient Clinic',        'GOPD Block, Ground Floor', '2101'),
 ('Internal Medicine',                'Medical Block A',          '2210'),
 ('Paediatrics',                      'Ayinke House',             '2305'),
 ('Obstetrics and Gynaecology',       'Ayinke House',             '2340'),
 ('Surgery',                          'Surgical Block',           '2402'),
 ('Haematology and Chemical Pathology','Central Laboratory',      '2501'),
 ('Pharmacy',                         'Main Pharmacy',            '2601'),
 ('Health Records',                   'Records Block',            '2701'),
 ('Accounts',                         'Administrative Block',     '2801');

INSERT INTO specialty (name) VALUES
 ('Family Medicine'), ('Internal Medicine'), ('Paediatrics'),
 ('Obstetrics and Gynaecology'), ('General Surgery'), ('Cardiology'), ('Endocrinology');

INSERT INTO staff (staff_no, department_id, first_name, last_name, role, phone, email, hire_date) VALUES
 ('LS/MD/0001', 1, 'Adebayo',   'Ogunleye',  'DOCTOR',        '08031110001', 'a.ogunleye@lasuth.example',  '2014-03-01'),
 ('LS/MD/0002', 2, 'Funmilayo', 'Adeyemi',   'DOCTOR',        '08031110002', 'f.adeyemi@lasuth.example',   '2016-07-11'),
 ('LS/MD/0003', 3, 'Chinedu',   'Okafor',    'DOCTOR',        '08031110003', 'c.okafor@lasuth.example',    '2018-01-15'),
 ('LS/MD/0004', 4, 'Halima',    'Bello',     'DOCTOR',        '08031110004', 'h.bello@lasuth.example',     '2015-09-21'),
 ('LS/MD/0005', 2, 'Olumide',   'Bakare',    'DOCTOR',        '08031110005', 'o.bakare@lasuth.example',    '2019-02-04'),
 ('LS/NS/0101', 1, 'Grace',     'Eze',       'NURSE',         '08031110101', 'g.eze@lasuth.example',       '2017-05-02'),
 ('LS/LB/0201', 6, 'Tunde',     'Alabi',     'LAB_SCIENTIST', '08031110201', 't.alabi@lasuth.example',     '2013-11-18'),
 ('LS/PH/0301', 7, 'Kemi',      'Oladipo',   'PHARMACIST',    '08031110301', 'k.oladipo@lasuth.example',   '2020-08-10'),
 ('LS/RC/0401', 8, 'Sola',      'Ajayi',     'RECORDS',       '08031110401', 's.ajayi@lasuth.example',     '2012-04-23'),
 ('LS/AC/0501', 9, 'Ifeoma',    'Nwosu',     'CASHIER',       '08031110501', 'i.nwosu@lasuth.example',     '2021-06-14');

INSERT INTO doctor (staff_id, specialty_id, mdcn_licence_no, consultation_fee) VALUES
 (1, 1, 'MDCN/R/31120', 5000),
 (2, 2, 'MDCN/R/38841', 8000),
 (3, 3, 'MDCN/R/45210', 7000),
 (4, 4, 'MDCN/R/35567', 8000),
 (5, 6, 'MDCN/R/50112', 10000);

INSERT INTO icd10_code (code, description) VALUES
 ('B50.9', 'Plasmodium falciparum malaria, unspecified'),
 ('B54',   'Unspecified malaria'),
 ('A01.0', 'Typhoid fever'),
 ('I10',   'Essential (primary) hypertension'),
 ('E11.9', 'Type 2 diabetes mellitus without complications'),
 ('D57.1', 'Sickle cell disease without crisis'),
 ('J06.9', 'Acute upper respiratory infection, unspecified'),
 ('J18.9', 'Pneumonia, unspecified organism'),
 ('A09',   'Infectious gastroenteritis and colitis, unspecified'),
 ('D64.9', 'Anaemia, unspecified'),
 ('N39.0', 'Urinary tract infection, site not specified'),
 ('O14.9', 'Pre eclampsia, unspecified');

INSERT INTO drug (name, form, strength, unit_price, stock_qty, reorder_level) VALUES
 ('Artemether/Lumefantrine', 'TABLET',    '80/480 mg', 350,  1200, 200),
 ('Paracetamol',             'TABLET',    '500 mg',     20,  8000, 1000),
 ('Amlodipine',              'TABLET',    '5 mg',       60,  3000, 300),
 ('Metformin',               'TABLET',    '500 mg',     45,  4000, 400),
 ('Amoxicillin',             'CAPSULE',   '500 mg',     70,  2500, 300),
 ('Ciprofloxacin',           'TABLET',    '500 mg',     90,  1500, 200),
 ('Folic Acid',              'TABLET',    '5 mg',       10,  6000, 500),
 ('Oral Rehydration Salts',  'SYRUP',     '20.5 g/L',  150,   600, 100),
 ('Ceftriaxone',             'INJECTION', '1 g',      1500,   400,  80),
 ('Lisinopril',              'TABLET',    '10 mg',      80,  2000, 250);

INSERT INTO lab_test (name, sample_type, price, turnaround_hours) VALUES
 ('Malaria Parasite (MP)',      'BLOOD', 1500,  2),
 ('Full Blood Count',           'BLOOD', 4000,  6),
 ('Fasting Blood Sugar',        'BLOOD', 1500,  2),
 ('Widal Test',                 'BLOOD', 2000,  4),
 ('Urinalysis',                 'URINE', 1500,  2),
 ('Haemoglobin Genotype',       'BLOOD', 3000, 24),
 ('HbA1c',                      'BLOOD', 7000, 24),
 ('Electrolytes, Urea, Creatinine','BLOOD', 6000, 12);

/* Three hand entered patients so the design can be read before bulk data arrives. */
INSERT INTO patient (hospital_no, first_name, last_name, sex, date_of_birth, phone, address, lga, blood_group, genotype, nhis_no) VALUES
 ('LASUTH/2026/000001', 'Bisola',  'Adewale', 'F', '1988-04-12', '08055501001', '14 Obafemi Awolowo Way, Ikeja', 'Ikeja',  'O+', 'AS', 'NHIS/LA/778120'),
 ('LASUTH/2026/000002', 'Emeka',   'Nwankwo', 'M', '1961-10-30', '08055501002', '7 Allen Avenue, Ikeja',          'Ikeja',  'B+', 'AA', NULL),
 ('LASUTH/2026/000003', 'Tobiloba','Salami',  'M', '2019-02-08', '08055501003', '22 Agege Motor Road, Mushin',    'Mushin', 'O+', 'SS', NULL);

INSERT INTO next_of_kin (patient_id, full_name, relationship, phone) VALUES
 (1, 'Kunle Adewale',  'Husband', '08055502001'),
 (2, 'Ngozi Nwankwo',  'Wife',    '08055502002'),
 (3, 'Yetunde Salami', 'Mother',  '08055502003');

INSERT INTO allergy (patient_id, allergen, severity) VALUES
 (2, 'Sulphonamides', 'SEVERE');

INSERT INTO appointment (patient_id, doctor_id, scheduled_at, status, reason) VALUES
 (1, 1, '2026-09-21 09:00+01', 'COMPLETED', 'Fever and headache for 3 days'),
 (2, 5, '2026-09-21 10:00+01', 'COMPLETED', 'Hypertension review'),
 (3, 3, '2026-09-22 09:30+01', 'COMPLETED', 'Sickle cell clinic follow up');

INSERT INTO consultation (appointment_id, temperature_c, bp_systolic, bp_diastolic, weight_kg, clinical_notes) VALUES
 (1, 38.9, 118, 76, 64.0, 'Febrile, no neck stiffness. Rapid test requested.'),
 (2, 36.7, 162, 98, 88.5, 'BP poorly controlled on Amlodipine alone.'),
 (3, 36.9,  98, 60, 17.2, 'Stable, no crisis in last 3 months.');

INSERT INTO diagnosis (consultation_id, icd10_code, is_primary) VALUES
 (1, 'B50.9', TRUE),
 (2, 'I10',   TRUE),
 (3, 'D57.1', TRUE);

INSERT INTO lab_request (consultation_id, test_id, status, result_value, result_unit, is_abnormal, reported_by, reported_at) VALUES
 (1, 1, 'REPORTED', 'Positive (++)', NULL, TRUE, 7, '2026-09-21 10:40+01');

INSERT INTO prescription (consultation_id, status) VALUES (1, 'PENDING'), (2, 'PENDING'), (3, 'PENDING');
INSERT INTO prescription_item (prescription_id, drug_id, dose, frequency, duration_days, quantity) VALUES
 (1, 1, '4 tablets', 'twice daily',  3, 24),
 (1, 2, '1 g',       'three times daily', 3, 18),
 (2, 3, '10 mg',     'once daily',  30, 60),
 (2, 10,'10 mg',     'once daily',  30, 30),
 (3, 7, '5 mg',      'once daily',  30, 30);

INSERT INTO invoice (patient_id, consultation_id) VALUES (1, 1), (2, 2), (3, 3);
INSERT INTO invoice_line (invoice_id, line_no, description, amount) VALUES
 (1, 1, 'Consultation, Family Medicine', 5000),
 (1, 2, 'Malaria Parasite (MP)',         1500),
 (2, 1, 'Consultation, Cardiology',     10000),
 (3, 1, 'Consultation, Paediatrics',     7000);

INSERT INTO payment (invoice_id, amount, method, cashier_id) VALUES
 (1, 6500, 'POS', 10),
 (2, 5000, 'CASH', 10);
UPDATE invoice SET status = 'PAID' WHERE invoice_id = 1;
