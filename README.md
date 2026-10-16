# LASUTH Clinic Management System: Advanced Database Systems Portfolio

**Course:** MIT 8103 Advanced Database Systems, MIVA Open University, 2026/2027 First Semester
**Case study:** Lagos State University Teaching Hospital (LASUTH), Ikeja: outpatient clinics, laboratory, pharmacy and billing
**Repository:** https://github.com/balotomi-mivas/Clinic-Management-System

## The organisation

LASUTH is a tertiary teaching hospital in Ikeja, Lagos. The database supports records officers, doctors, nurses, laboratory scientists, pharmacists, cashiers and hospital management. It stores patients and next of kin, staff and doctors, appointments, consultations and ICD 10 diagnoses, prescriptions and drug stock, laboratory requests and results, invoices and payments, and an audit trail. Key operations: register a patient, book an appointment without double booking, record a diagnosis, request and report tests, dispense against live stock, bill and receive payment, and retrieve a full patient history.

All data in this repository is synthetic. No real patient record was used.

## Portfolio map

| Folder | Activity | Headline result |
|---|---|---|
| [`portfolio_1_database_design`](portfolio_1_database_design) | Database Design and Modelling | 20 table 3NF schema; business rules enforced by constraints and tested |
| [`portfolio_2_query_optimisation`](portfolio_2_query_optimisation) | Query Processing and Optimisation | Six workload queries 41 to 2,490 times faster on 400,003 appointments |
| [`portfolio_3_transactions_concurrency`](portfolio_3_transactions_concurrency) | Transactions and Concurrency | Lost update, write skew and deadlock reproduced with live sessions, then prevented |
| [`portfolio_4_nosql`](portfolio_4_nosql) | NoSQL and Advanced Data Models | MongoDB document model cross checked against SQL; Redis queue and cache |
| [`portfolio_5_distributed_cloud`](portfolio_5_distributed_cloud) | Distributed and Cloud Database | Streaming replication, failover in 0.11 s, hash sharding on two servers, Azure DR template |
| [`documentation`](documentation) | Final documentation | LMS summary |

Each folder has its own README explaining what was built, how it was tested and what the evidence shows. Raw output is in each `evidence/` folder.

## Environment

| Component | Version |
|---|---|
| PostgreSQL | 16.15 (Ubuntu 24.04) |
| Redis | 7.0.15 |
| MongoDB API | mongomock 4.3.0 for the evidence run; scripts provided for a real MongoDB server |
| Python | 3, with psycopg2, jsonschema, pymongo |
| Bicep CLI | 0.48.1 |

## Rebuilding everything

```
psql -U postgres -f portfolio_1_database_design/00_create_database.sql
psql -U postgres -d lasuth -f portfolio_1_database_design/01_schema.sql
psql -U postgres -d lasuth -f portfolio_1_database_design/02_seed_data.sql
psql -U postgres -d lasuth -f portfolio_1_database_design/03_constraint_tests.sql
psql -U postgres -d lasuth -f portfolio_2_query_optimisation/01_generate_volume_data.sql
cd portfolio_2_query_optimisation && python3 03_benchmark.py 02_workload_queries.sql before
psql -U postgres -d lasuth -f 04_optimisation.sql && python3 03_benchmark.py 05_optimised_queries.sql after && cd ..
psql -U postgres -d lasuth -f portfolio_3_transactions_concurrency/01_setup.sql
python3 portfolio_3_transactions_concurrency/02_concurrency_runner.py
python3 portfolio_4_nosql/02_migrate_and_query.py
bash portfolio_4_nosql/03_redis_keyvalue.sh
```
Portfolio 5 needs extra PostgreSQL servers on ports 5433 to 5435; see its README.
