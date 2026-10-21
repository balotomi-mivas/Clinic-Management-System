/*
  LASUTH Clinic Management System
  Portfolio 4: NoSQL and Advanced Data Models
  File: 01_mongodb_collections.js   (run with mongosh)

    mongosh "mongodb://localhost:27017/lasuth" 01_mongodb_collections.js

  Two collections:
    patients    one document per patient, with small bounded arrays embedded
    encounters  one document per clinic visit, holding everything that happened
                in that visit (vitals, diagnoses, prescriptions, lab results, bill)

  The validators are kept in schema/*.json so the Python loader can check
  documents against exactly the same rules before inserting them.
*/
const db = db.getSiblingDB("lasuth");

const patientSchema   = JSON.parse(fs.readFileSync("schema/patient.schema.json", "utf8"));
const encounterSchema = JSON.parse(fs.readFileSync("schema/encounter.schema.json", "utf8"));

db.patients.drop();
db.encounters.drop();

db.createCollection("patients", {
  validator: { $jsonSchema: patientSchema },
  validationLevel: "strict",
  validationAction: "error"
});

db.createCollection("encounters", {
  validator: { $jsonSchema: encounterSchema },
  validationLevel: "strict",
  validationAction: "error"
});

/* patients */
db.patients.createIndex({ hospital_no: 1 }, { unique: true });
db.patients.createIndex({ last_name_lower: 1, date_of_birth: 1 });      /* front desk search */

/* encounters */
db.encounters.createIndex({ patient_id: 1, visit_date: -1 });            /* folder retrieval, newest first */
db.encounters.createIndex({ "diagnoses.code": 1, visit_date: 1 });       /* multikey: disease surveillance */
db.encounters.createIndex({ "doctor.staff_id": 1, visit_date: 1 });      /* doctor workload */
db.encounters.createIndex(                                               /* lab worklist, partial like Portfolio 2 */
  { "lab_results.requested_at": 1 },
  { partialFilterExpression: { "lab_results.status": "REQUESTED" } }
);

print("Collections and indexes created");
printjson(db.encounters.getIndexes().map(i => i.name));
