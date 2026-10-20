/*
  LASUTH Clinic Management System
  Portfolio 3: Transactions and Concurrency
  File: 01_setup.sql

  1. sp_dispense_prescription: the pharmacy's most important transaction.
     Stock, prescription status and the bill must change together or not at all.
  2. duty_rota: the Children Emergency Ward rule that at least one doctor is
     on duty at all times, used to demonstrate write skew.
  3. A dedicated test drug and prescription so the demonstrations never
     disturb the Portfolio 2 data.
*/
SET search_path TO clinic;

CREATE OR REPLACE PROCEDURE sp_dispense_prescription(p_prescription_id BIGINT, p_pharmacist_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_item       RECORD;
    v_stock      INTEGER;
    v_patient    INTEGER;
    v_cons       BIGINT;
    v_invoice    BIGINT;
    v_line       SMALLINT;
BEGIN
    /* Lock the prescription first so two pharmacists cannot dispense it twice. */
    SELECT pr.consultation_id INTO v_cons
    FROM prescription pr
    WHERE pr.prescription_id = p_prescription_id AND pr.status = 'PENDING'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Prescription % is not pending', p_prescription_id USING ERRCODE = 'P0001';
    END IF;

    SELECT a.patient_id INTO v_patient
    FROM consultation c JOIN appointment a ON a.appointment_id = c.appointment_id
    WHERE c.consultation_id = v_cons;

    /* Lock drug rows in ascending drug_id order. Every session that follows this
       order requests locks in the same sequence, so two dispensing sessions
       can wait for each other but can never deadlock. */
    FOR v_item IN
        SELECT pi.drug_id, pi.quantity, d.name, d.unit_price
        FROM prescription_item pi JOIN drug d ON d.drug_id = pi.drug_id
        WHERE pi.prescription_id = p_prescription_id
        ORDER BY pi.drug_id
    LOOP
        SELECT stock_qty INTO v_stock FROM drug WHERE drug_id = v_item.drug_id FOR UPDATE;
        IF v_stock < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for %: need %, have %', v_item.name, v_item.quantity, v_stock
                  USING ERRCODE = 'P0002';
        END IF;
        UPDATE drug SET stock_qty = stock_qty - v_item.quantity WHERE drug_id = v_item.drug_id;
    END LOOP;

    UPDATE prescription
    SET status = 'DISPENSED', dispensed_by = p_pharmacist_id, dispensed_at = now()
    WHERE prescription_id = p_prescription_id;

    /* Add the drugs to the patient's open invoice for this visit, creating one if needed. */
    SELECT invoice_id INTO v_invoice FROM invoice
    WHERE consultation_id = v_cons AND status = 'OPEN' FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO invoice (patient_id, consultation_id) VALUES (v_patient, v_cons)
        RETURNING invoice_id INTO v_invoice;
    END IF;

    SELECT COALESCE(MAX(line_no), 0) INTO v_line FROM invoice_line WHERE invoice_id = v_invoice;
    INSERT INTO invoice_line (invoice_id, line_no, description, amount)
    SELECT v_invoice, v_line + row_number() OVER (ORDER BY pi.drug_id),
           'Drug: ' || d.name || ' x' || pi.quantity, d.unit_price * pi.quantity
    FROM prescription_item pi JOIN drug d ON d.drug_id = pi.drug_id
    WHERE pi.prescription_id = p_prescription_id;
END $$;

/* Ward duty rota used for the write skew demonstration */
DROP TABLE IF EXISTS duty_rota;
CREATE TABLE duty_rota (
    ward        VARCHAR(40) NOT NULL,
    doctor_id   INTEGER     NOT NULL REFERENCES doctor (staff_id),
    on_duty     BOOLEAN     NOT NULL,
    PRIMARY KEY (ward, doctor_id)
);
INSERT INTO duty_rota VALUES ('Children Emergency Ward', 3, TRUE), ('Children Emergency Ward', 2, TRUE);

/* Test drugs with known stock levels. Upsert so the script can be rerun. */
INSERT INTO drug (name, form, strength, unit_price, stock_qty, reorder_level) VALUES
 ('Demo Coartem',     'TABLET', '80/480 mg', 350, 100, 10),
 ('Demo Ceftriaxone', 'INJECTION', '1 g',   1500,   2,  1)
ON CONFLICT (name, form, strength) DO UPDATE SET stock_qty = EXCLUDED.stock_qty;
