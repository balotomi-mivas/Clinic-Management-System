# Portfolio 4: NoSQL and Advanced Data Models

The same LASUTH data was remodelled for two NoSQL stores, each chosen for the job it does better than the relational database. **MongoDB (document model)** holds the patient folder, where a doctor wants everything about a visit in one read. **Redis (key value model)** holds short lived, very hot data: the clinic waiting queue, a patient card cache and the live bed board. PostgreSQL stays the system of record for billing and stock, where multi row transactions matter.

## Document model

Two collections, defined with server side `$jsonSchema` validators in `01_mongodb_collections.js` and `schema/*.json`.

**patients**: one document per patient, embedding next of kin (at most 5), allergies (at most 20) and a summary of the five most recent visits.
**encounters**: one document per visit, embedding a copy of the doctor's name and specialty, vitals, diagnoses, prescriptions, lab results and the bill. It references the patient by `patient_id` and `hospital_no`.

Real examples produced by the migration are in `evidence/sample_patient.json` and `evidence/sample_encounter.json`.

### Design decisions

| Decision | Reason |
|---|---|
| Embed diagnoses, prescriptions and lab results in the encounter | They are always read with the visit, belong to only that visit, and stay small (median encounter 778 bytes, largest 2,845 bytes against the 16 MB document limit). |
| Do **not** embed all encounters in the patient | Visits grow without limit over a lifetime. One document would keep growing, get rewritten on every visit and could eventually reach the size limit. |
| Copy the doctor's name and specialty into each encounter (extended reference) | The folder shows them on every line. Copying avoids a lookup, and a historical record should show who the doctor was at the time, even if the doctor later changes department. |
| Keep the last five visit summaries on the patient (subset pattern) | The registration screen shows the latest visits instantly without touching the encounters collection. `$push` with `$slice: 5` keeps the array bounded. |
| Store `last_name_lower` | Mirrors the expression index from Portfolio 2, so surname search uses an ordinary index. |
| Indexes on `(patient_id, visit_date)`, multikey `diagnoses.code`, and a partial index on pending lab results | The same access paths that were tuned in Portfolio 2. |

## Implementation and evidence

`02_migrate_and_query.py` extracts 5,000 patients and their 28,318 visits from the PostgreSQL database, reshapes them into documents, validates every document against the same JSON schema the MongoDB server enforces, loads them, and runs five operations. Each answer is checked against the equivalent SQL.

| Operation | Document answer | SQL answer |
|---|---|---|
| M1 folder retrieval for LASUTH/2021/002066 | 16 visits, one query, no joins | 16 (four table join) |
| M2 malaria cases per month in 2026 (aggregation pipeline) | 10 months, identical counts | identical |
| M3 outstanding lab requests across embedded arrays | 319 | 319 |
| M4 report one lab result with the positional `$` operator | matched 1, modified 1 | Single document update, atomic without a transaction |
| M5 add a visit summary with `$push`, `$sort`, `$slice` | Array stayed at 5 | Not applicable |

The validator rejected a deliberately broken encounter on two counts: empty diagnoses, and a temperature of 52 against a maximum of 45. All 33,318 real documents passed.

**Honest note on the environment.** My working environment had no MongoDB server, so the evidence run used `mongomock`, an in process emulator of the pymongo API. It executes the same queries and aggregation pipelines but does not enforce `$jsonSchema` or use indexes. For that reason, validation was also done in Python against the identical schema files. To repeat the run on a real server, set `MONGO_URI` (for example to a free MongoDB Atlas cluster) and run the script again, then run `01_mongodb_collections.js` and `04_mongodb_queries.js` in mongosh.

## Key value model (Redis 7.0.15, real server)

`03_redis_keyvalue.sh` was run against a real Redis server; the full session is in `evidence/redis_session_log.txt`.

| LASUTH need | Redis structure | Why it fits |
|---|---|---|
| GOPD waiting queue | Sorted set, score = arrival time | `ZRANK` tells a patient their position; `ZPOPMIN` lets a doctor call the next patient in one atomic step, so two consulting rooms can never call the same person. `EXPIREAT` clears the queue at midnight. |
| Patient summary card | Hash with a 15 minute TTL | Cache aside: filled from PostgreSQL on first read, deleted when a diagnosis changes. |
| Ward bed board | Hash counters | `HINCRBY` is atomic, so simultaneous admissions cannot cause the lost update shown in Portfolio 3. |

`redis-benchmark` measured the queue read at about 125,000 requests per second with a median latency of 0.023 ms.

## When each model fits

The document model wins when the unit of reading matches the unit of storage: a visit is read whole, so embedding removes four joins. It loses when one fact is shared and changes often. Drug prices and stock live in many prescriptions, and updating copies would bring back the update anomalies that normalisation removed in Portfolio 1. Multi document consistency (dispense, reduce stock, bill) also needs MongoDB transactions, which are costlier than PostgreSQL's. That is why pharmacy and billing stay relational. Redis is fast because it keeps everything in memory, which makes it right for data that is hot and can be rebuilt, and wrong as the only copy of a clinical record.

A graph model was considered for the referral network (GOPD to specialist clinics to surgery), where questions like "which referral paths lead to the longest waits" are path queries. It was not implemented because the volume of referral data in this case study is too small to justify a separate store.

## Files

| File | Purpose |
|---|---|
| `01_mongodb_collections.js` | Collections, validators and indexes (mongosh) |
| `schema/patient.schema.json`, `schema/encounter.schema.json` | `$jsonSchema` rules |
| `02_migrate_and_query.py` | Migration from PostgreSQL, validation, workload, cross checks |
| `03_redis_keyvalue.sh` | Redis session |
| `04_mongodb_queries.js` | The workload in mongosh syntax for a real server |
| `evidence/` | Workload log, Redis log, sample documents |
