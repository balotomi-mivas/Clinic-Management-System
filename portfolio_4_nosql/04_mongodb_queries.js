/*
  LASUTH Clinic Management System
  Portfolio 4: the document workload in mongosh syntax
  File: 04_mongodb_queries.js

  Same five operations that 02_migrate_and_query.py runs through the pymongo
  API. Use this file to repeat them on a real MongoDB server, for example a
  free MongoDB Atlas cluster, after loading with
  MONGO_URI="mongodb+srv://..." python3 02_migrate_and_query.py
*/
const db = db.getSiblingDB("lasuth");

/* M1 Folder retrieval: one read, no joins, newest visit first */
db.encounters.find({ hospital_no: "LASUTH/2021/002066" }).sort({ visit_date: -1 });
db.encounters.find({ hospital_no: "LASUTH/2021/002066" }).sort({ visit_date: -1 }).explain("executionStats");

/* M2 Malaria cases per month in 2026 */
db.encounters.aggregate([
  { $match: { visit_date: { $gte: "2026-01-01", $lt: "2027-01-01" } } },
  { $unwind: "$diagnoses" },
  { $match: { "diagnoses.code": { $in: ["B50.9", "B54"] } } },
  { $group: { _id: { $substr: ["$visit_date", 0, 7] }, cases: { $sum: 1 } } },
  { $sort: { _id: 1 } }
]);

/* M3 Lab worklist across embedded arrays */
db.encounters.aggregate([
  { $unwind: "$lab_results" },
  { $match: { "lab_results.status": "REQUESTED" } },
  { $sort: { "lab_results.requested_at": 1 } },
  { $project: { _id: 0, hospital_no: 1, test: "$lab_results.test", requested_at: "$lab_results.requested_at" } }
]);

/* M4 Report one result atomically inside its encounter document */
db.encounters.updateOne(
  { "lab_results.status": "REQUESTED" },                 /* first outstanding request */
  { $set: { "lab_results.$.status": "REPORTED", "lab_results.$.result": "Negative", "lab_results.$.abnormal": false } }
);

/* M5 Keep only the five newest visit summaries on the patient (subset pattern) */
db.patients.updateOne(
  { hospital_no: "LASUTH/2021/002066" },
  { $push: { recent_encounters: {
      $each: [ { encounter_id: 999999, visit_date: "2026-10-16T09:00:00+01",
                 doctor: "Adebayo Ogunleye", primary_diagnosis: "Plasmodium falciparum malaria, unspecified" } ],
      $sort: { visit_date: -1 }, $slice: 5 } } }
);

/* Validator check: this insert must be rejected by the server (no diagnosis, temperature 52) */
try {
  db.encounters.insertOne({ encounter_id: 1, patient_id: 1, hospital_no: "LASUTH/2026/000001",
    visit_date: "2026-10-16T09:00:00+01", doctor: { staff_id: 1, name: "x", specialty: "x", department: "x" },
    vitals: { temperature_c: 52 }, diagnoses: [] });
} catch (e) { print("Rejected by $jsonSchema: " + e.code + " " + e.errmsg); }
