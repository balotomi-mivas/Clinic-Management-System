"""
LASUTH Clinic Management System
Portfolio 4: NoSQL and Advanced Data Models
File: 02_migrate_and_query.py

1. Extracts 5,000 patients and every visit they made from the PostgreSQL
   database built in Portfolios 1 and 2.
2. Reshapes the rows into the two document types (patients, encounters).
3. Validates every document against schema/*.json, the same rules the
   MongoDB server enforces through $jsonSchema in 01_mongodb_collections.js.
4. Loads them and runs the document workload, then checks each answer
   against the equivalent SQL so the two models are proven to agree.

Target selection:
    MONGO_URI set      -> a real MongoDB server (for example MongoDB Atlas)
    MONGO_URI not set  -> mongomock, an in process emulator of the pymongo API
The evidence in evidence/mongodb_workload_log.txt states which one was used.
"""
import json, os, statistics, time
from collections import Counter
from datetime import datetime

import bson, jsonschema, psycopg2

N_PATIENTS = 5000
HERE = os.path.dirname(os.path.abspath(__file__))
LOG = open(os.path.join(HERE, "evidence", "mongodb_workload_log.txt"), "w")

def log(msg=""):
    print(msg); LOG.write(msg + "\n"); LOG.flush()

def to_jsonschema(node):
    """Translate MongoDB bsonType keywords into standard JSON Schema types."""
    m = {"object": "object", "array": "array", "string": "string", "int": "integer",
         "double": "number", "bool": "boolean", "null": "null", "date": "string"}
    if isinstance(node, dict):
        out = {}
        for k, v in node.items():
            if k == "bsonType":
                out["type"] = [m[t] for t in v] if isinstance(v, list) else m[v]
            else:
                out[k] = to_jsonschema(v)
        return out
    if isinstance(node, list):
        return [to_jsonschema(x) for x in node]
    return node

SCHEMAS = {n: to_jsonschema(json.load(open(os.path.join(HERE, "schema", f"{n}.schema.json"))))
           for n in ("patient", "encounter")}
VALIDATORS = {n: jsonschema.Draft7Validator(s) for n, s in SCHEMAS.items()}   # compiled once

if os.getenv("MONGO_URI"):
    from pymongo import MongoClient
    client, engine = MongoClient(os.environ["MONGO_URI"]), "MongoDB server at MONGO_URI"
else:
    import mongomock
    client, engine = mongomock.MongoClient(), f"mongomock {mongomock.__version__} (pymongo API emulator)"
mdb = client["lasuth"]
mdb.patients.drop(); mdb.encounters.drop()

pg = psycopg2.connect(os.getenv("LASUTH_DSN", "host=localhost user=postgres dbname=lasuth"))
cur = pg.cursor()
cur.execute("SET search_path TO clinic")

log("LASUTH Portfolio 4: relational to document migration and workload")
log(f"Run at {datetime.now().isoformat(timespec='seconds')}")
log(f"Document store: {engine}")
log("")

# 1. Extract
t = time.time()
cur.execute("""SELECT patient_id, hospital_no, first_name, last_name, sex, date_of_birth::text,
                      phone, lga, blood_group, genotype, nhis_no
               FROM patient ORDER BY patient_id LIMIT %s""", (N_PATIENTS,))
pcols = [d[0] for d in cur.description]
patients = {r[0]: dict(zip(pcols, r)) for r in cur.fetchall()}
ids = tuple(patients)

cur.execute("SELECT patient_id, full_name, relationship, phone FROM next_of_kin WHERE patient_id IN %s", (ids,))
for pid, n, rel, ph in cur.fetchall():
    patients[pid].setdefault("next_of_kin", []).append({"full_name": n, "relationship": rel, "phone": ph})
cur.execute("SELECT patient_id, allergen, severity FROM allergy WHERE patient_id IN %s", (ids,))
for pid, a, s in cur.fetchall():
    patients[pid].setdefault("allergies", []).append({"allergen": a, "severity": s})

cur.execute("""
SELECT c.consultation_id, a.patient_id, p.hospital_no, to_char(a.scheduled_at, 'YYYY-MM-DD"T"HH24:MI:SSOF'),
       s.staff_id, s.first_name || ' ' || s.last_name, sp.name, dep.name,
       c.temperature_c::float, c.bp_systolic || '/' || c.bp_diastolic, c.weight_kg::float, a.reason
FROM consultation c
JOIN appointment a  ON a.appointment_id = c.appointment_id
JOIN patient p      ON p.patient_id = a.patient_id
JOIN doctor d       ON d.staff_id = a.doctor_id
JOIN staff s        ON s.staff_id = d.staff_id
JOIN specialty sp   ON sp.specialty_id = d.specialty_id
JOIN department dep ON dep.department_id = s.department_id
WHERE a.patient_id IN %s""", (ids,))
enc = {}
for (cid, pid, hn, vd, sid, dname, spec, dept, temp, bp, wt, reason) in cur.fetchall():
    enc[cid] = {"encounter_id": cid, "patient_id": pid, "hospital_no": hn, "visit_date": vd,
                "reason": reason,
                "doctor": {"staff_id": sid, "name": dname, "specialty": spec, "department": dept},
                "vitals": {"temperature_c": temp, "bp": bp, "weight_kg": wt},
                "diagnoses": [], "prescriptions": [], "lab_results": [], "bill": {"total": 0.0, "paid": 0.0}}
cids = tuple(enc)

cur.execute("""SELECT d.consultation_id, d.icd10_code, i.description, d.is_primary
               FROM diagnosis d JOIN icd10_code i ON i.code = d.icd10_code WHERE d.consultation_id IN %s""", (cids,))
for cid, code, desc, prim in cur.fetchall():
    enc[cid]["diagnoses"].append({"code": code, "description": desc, "primary": prim})

cur.execute("""SELECT pr.consultation_id, dr.name || ' ' || dr.strength, pi.dose, pi.frequency, pi.duration_days, pi.quantity, pr.status
               FROM prescription pr JOIN prescription_item pi ON pi.prescription_id = pr.prescription_id
               JOIN drug dr ON dr.drug_id = pi.drug_id WHERE pr.consultation_id IN %s""", (cids,))
for cid, drug, dose, freq, days, qty, st in cur.fetchall():
    enc[cid]["prescriptions"].append({"drug": drug, "dose": dose, "frequency": freq,
                                      "duration_days": days, "quantity": qty, "status": st})

cur.execute("""SELECT r.consultation_id, r.request_id, t.name, r.status, r.result_value, r.is_abnormal,
                      to_char(r.requested_at, 'YYYY-MM-DD"T"HH24:MI:SSOF')
               FROM lab_request r JOIN lab_test t ON t.test_id = r.test_id WHERE r.consultation_id IN %s""", (cids,))
for cid, rid, test, st, val, ab, req in cur.fetchall():
    enc[cid]["lab_results"].append({"request_id": rid, "test": test, "status": st, "result": val,
                                    "abnormal": ab, "requested_at": req})

cur.execute("""SELECT consultation_id, total_billed::float, total_paid::float
               FROM invoice i JOIN v_invoice_balance b USING (invoice_id) WHERE i.consultation_id IN %s""", (cids,))
for cid, tot, paid in cur.fetchall():
    enc[cid]["bill"]["total"] += tot; enc[cid]["bill"]["paid"] += paid

# Subset pattern: copy a summary of the five most recent visits into the patient document
by_patient = {}
for e in enc.values():
    by_patient.setdefault(e["patient_id"], []).append(e)
for pid, p in patients.items():
    p["last_name_lower"] = p["last_name"].lower()
    p.setdefault("next_of_kin", []); p.setdefault("allergies", [])
    recent = sorted(by_patient.get(pid, []), key=lambda e: e["visit_date"], reverse=True)[:5]
    p["recent_encounters"] = [{"encounter_id": e["encounter_id"], "visit_date": e["visit_date"],
                               "doctor": e["doctor"]["name"],
                               "primary_diagnosis": next((d["description"] for d in e["diagnoses"] if d["primary"]), None)}
                              for e in recent]
log(f"[1] Extracted {len(patients):,} patients and {len(enc):,} encounters from PostgreSQL in {time.time() - t:.2f} s")

# 2. Validate
t = time.time()
bad = 0
bad += sum(1 for p in patients.values() if not VALIDATORS["patient"].is_valid(p))
bad += sum(1 for e in enc.values() if not VALIDATORS["encounter"].is_valid(e))
log(f"[2] Validated {len(patients) + len(enc):,} documents against schema/*.json: {bad} failures ({time.time() - t:.2f} s)")

log("    Negative test, an encounter with no diagnosis and an impossible temperature:")
broken = dict(next(iter(enc.values())), diagnoses=[], vitals={"temperature_c": 52.0, "bp": "120/80", "weight_kg": 70})
errs = sorted(VALIDATORS["encounter"].iter_errors(broken), key=lambda e: list(e.path))
log("    accepted (unexpected)" if not errs else "    rejected:")
for err in errs:
    log(f"      {'/'.join(map(str, err.path)) or '(root)'}: {err.message}")

# 3. Load
t = time.time()
mdb.patients.insert_many(list(patients.values()))
mdb.encounters.insert_many(list(enc.values()))
mdb.patients.create_index("hospital_no", unique=True)
mdb.patients.create_index([("last_name_lower", 1), ("date_of_birth", 1)])
mdb.encounters.create_index([("patient_id", 1), ("visit_date", -1)])
mdb.encounters.create_index([("diagnoses.code", 1), ("visit_date", 1)])
log(f"[3] Loaded into collections patients ({mdb.patients.count_documents({}):,}) "
    f"and encounters ({mdb.encounters.count_documents({}):,}) in {time.time() - t:.2f} s")

sizes = [len(bson.encode({k: v for k, v in e.items() if k != "_id"})) for e in enc.values()]
psizes = [len(bson.encode({k: v for k, v in p.items() if k != "_id"})) for p in patients.values()]
log(f"    Encounter BSON size: median {statistics.median(sizes):,.0f} bytes, max {max(sizes):,} bytes (limit 16,777,216)")
log(f"    Patient BSON size:   median {statistics.median(psizes):,.0f} bytes, max {max(psizes):,} bytes")
log("")

def agree(label, doc_answer, sql_answer):
    log(f"    Document answer: {doc_answer}")
    log(f"    SQL answer:      {sql_answer}")
    log(f"    {'MATCH' if doc_answer == sql_answer else 'MISMATCH'}")
    log("")

# 4. Workload
target = max(by_patient, key=lambda k: len(by_patient[k]))
hn = patients[target]["hospital_no"]

log(f"[M1] Folder retrieval for {hn}: one query, no joins")
docs = list(mdb.encounters.find({"hospital_no": hn}, {"_id": 0}).sort("visit_date", -1))
log(f"    db.encounters.find({{hospital_no: '{hn}'}}).sort({{visit_date: -1}})  -> {len(docs)} documents")
cur.execute("SELECT count(DISTINCT c.consultation_id) FROM consultation c JOIN appointment a USING (appointment_id) "
            "JOIN patient p USING (patient_id) WHERE p.hospital_no = %s", (hn,))
agree("M1", len(docs), cur.fetchone()[0])
json.dump(docs[0], open(os.path.join(HERE, "evidence", "sample_encounter.json"), "w"), indent=2, default=str)
p_doc = mdb.patients.find_one({"hospital_no": hn}, {"_id": 0})
json.dump(p_doc, open(os.path.join(HERE, "evidence", "sample_patient.json"), "w"), indent=2, default=str)

log("[M2] Aggregation pipeline: malaria cases per month in 2026 (B50.9 and B54), these 5,000 patients")
pipeline = [
    {"$match": {"visit_date": {"$gte": "2026-01-01", "$lt": "2027-01-01"}}},
    {"$unwind": "$diagnoses"},
    {"$match": {"diagnoses.code": {"$in": ["B50.9", "B54"]}}},
    {"$group": {"_id": {"$substr": ["$visit_date", 0, 7]}, "cases": {"$sum": 1}}},
    {"$sort": {"_id": 1}},
]
log("    " + json.dumps(pipeline))
doc_result = [(r["_id"], r["cases"]) for r in mdb.encounters.aggregate(pipeline)]
cur.execute("""SELECT to_char(a.scheduled_at, 'YYYY-MM'), count(*)
               FROM diagnosis d JOIN consultation c USING (consultation_id) JOIN appointment a USING (appointment_id)
               WHERE a.patient_id IN %s AND d.icd10_code IN ('B50.9','B54')
                 AND a.scheduled_at >= '2026-01-01' AND a.scheduled_at < '2027-01-01'
               GROUP BY 1 ORDER BY 1""", (ids,))
agree("M2", doc_result, cur.fetchall())

log("[M3] Lab worklist: outstanding requests across embedded arrays")
pipe3 = [{"$unwind": "$lab_results"}, {"$match": {"lab_results.status": "REQUESTED"}},
         {"$sort": {"lab_results.requested_at": 1}},
         {"$project": {"_id": 0, "hospital_no": 1, "test": "$lab_results.test", "requested_at": "$lab_results.requested_at"}}]
pending = list(mdb.encounters.aggregate(pipe3))
cur.execute("""SELECT count(*) FROM lab_request r JOIN consultation c USING (consultation_id)
               JOIN appointment a USING (appointment_id) WHERE r.status = 'REQUESTED' AND a.patient_id IN %s""", (ids,))
agree("M3", len(pending), cur.fetchone()[0])

log("[M4] Lab scientist reports a result: one atomic update inside one document (positional $ operator)")
if pending:
    e = mdb.encounters.find_one({"lab_results.status": "REQUESTED"})
    rid = next(l["request_id"] for l in e["lab_results"] if l["status"] == "REQUESTED")
    res = mdb.encounters.update_one(
        {"encounter_id": e["encounter_id"], "lab_results.request_id": rid},
        {"$set": {"lab_results.$.status": "REPORTED", "lab_results.$.result": "Negative",
                  "lab_results.$.abnormal": False}})
    after = mdb.encounters.find_one({"encounter_id": e["encounter_id"]})
    st = next(l["status"] for l in after["lab_results"] if l["request_id"] == rid)
    log(f"    update_one matched={res.matched_count} modified={res.modified_count}; request {rid} is now {st}")
log("")

log("[M5] New visit: insert encounter and keep only the last five summaries on the patient (subset pattern)")
before_len = len(p_doc["recent_encounters"])
mdb.patients.update_one({"hospital_no": hn}, {"$push": {"recent_encounters": {
    "$each": [{"encounter_id": 999999, "visit_date": "2026-10-16T09:00:00+01", "doctor": "Adebayo Ogunleye",
               "primary_diagnosis": "Plasmodium falciparum malaria, unspecified"}],
    "$sort": {"visit_date": -1}, "$slice": 5}}})
after_doc = mdb.patients.find_one({"hospital_no": hn})
log(f"    recent_encounters before: {before_len}, after: {len(after_doc['recent_encounters'])}, "
    f"newest is now encounter {after_doc['recent_encounters'][0]['encounter_id']}")
log("")
log("All checks finished.")
