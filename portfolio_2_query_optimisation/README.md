# Portfolio 2: Query Processing and Optimisation

The six queries that carry most of the daily load at LASUTH were measured on a realistic volume, the plans were read to find the cause of each slow step, and each cause was fixed with the narrowest change that worked. Median execution time fell by between 41 and 2,490 times.

## Data volume

`01_generate_volume_data.sql` loads close to two years of outpatient activity with a fixed random seed, so anyone rerunning it gets the same rows.

| Table | Rows |
|---|---|
| patient | 60,003 |
| doctor | 120 |
| appointment | 400,003 |
| consultation, diagnosis, prescription, invoice | 342,177 each |
| lab_request | 239,200 (3,798 outstanding) |
| payment | 273,523 |

Database size after load: 343 MB.

## Method

1. Load the data and run `VACUUM ANALYZE` so the planner has current statistics.
2. `03_benchmark.py 02_workload_queries.sql before` runs each query once to warm the cache, then `EXPLAIN (ANALYZE)` seven times, and keeps the median. It saves the full `EXPLAIN (ANALYZE, BUFFERS)` plan of each query to `evidence/plans_before/`.
3. Apply `04_optimisation.sql`.
4. `03_benchmark.py 05_optimised_queries.sql after` repeats the measurement into `evidence/plans_after/`.

Medians are used rather than averages so that a single slow run caused by the operating system does not distort the figure.

## Results

![Before and after chart](evidence/before_after_chart.png)

| Query | Before (ms) | After (ms) | What the plan showed | Fix |
|---|---|---|---|---|
| Q1 Patient history | 52.30 | 0.27 | Parallel Seq Scan over all 400,003 appointments to find 21 rows | B tree index on the foreign key `appointment(patient_id)` |
| Q2 Doctor day list | 25.70 | 0.12 | Parallel Seq Scan; the `scheduled_at::date` cast hides the column from any index | Composite index `(doctor_id, scheduled_at)` and a half open range predicate |
| Q3 Surname search | 2.84 | 0.03 | Seq Scan on patient with `lower()` applied to every row | Expression index on `(lower(last_name), date_of_birth)` |
| Q4 Lab worklist | 23.46 | 0.57 | Full scan and sort of 239,200 lab requests to return 50 | Partial index on `requested_at WHERE status = 'REQUESTED'` |
| Q5 Patient balance | 378.50 | 0.15 | The view summed every invoice line and payment in the hospital before filtering | View rewritten with `LATERAL`, plus indexes on `invoice(patient_id)` and `payment(invoice_id)` |
| Q6 Monthly report | 451.82 | 0.35 | Large hash joins and aggregation across four tables | Materialised view refreshed nightly with `REFRESH ... CONCURRENTLY` |

## What I learned from the plans

**Foreign keys are not indexed automatically in PostgreSQL.** Q1 joined cleanly through primary keys everywhere except `appointment.patient_id`, where it fell back to a parallel sequential scan. One index removed 99.5 percent of the time. SQL Server behaves the same way, so this check now goes into my standard review of any new schema.

**An index is useless if the predicate cannot reach it.** `evidence/06_extra_checks.log` (Check A) shows Q2 with the composite index in place but the original cast kept. PostgreSQL can only use the `doctor_id` part, reads 3,334 rows and throws 3,318 away (10.48 ms). Rewriting the predicate as `scheduled_at >= '2026-10-14' AND scheduled_at < '2026-10-15'` lets the index seek straight to 16 rows (0.12 ms).

**Partial indexes suit queue tables.** The pending lab index is 48 kB against 1,824 kB for a full index on the same column (Check B), because it only holds the 1.6 percent of rows that are still outstanding.

**Views can hide expensive work.** Q5 looked trivial, but the original view aggregated 342,178 invoice lines and 273,523 payments first and filtered afterwards. The planner cannot push a filter into a grouped subquery. Rewriting it with `LATERAL` makes each sum run only for the patient's 17 invoices.

**Materialised views trade freshness for speed.** Q6 drops from 452 ms to 0.35 ms, but the figures are only as current as the last refresh. The refresh costs 681 ms (Check C) and runs at night. That is acceptable for a management report and would not be acceptable for anything clinical.

**Costs of the fixes.** The eight new indexes add about 30 MB (Check D) and slightly slow inserts into `appointment`, `invoice` and `payment`. For a read heavy clinical system that trade is clearly worth it.

## Files

| File | Purpose |
|---|---|
| `01_generate_volume_data.sql` | Repeatable volume load |
| `02_workload_queries.sql` | The six queries as originally written |
| `03_benchmark.py` | Measurement harness (Python standard library and psql only) |
| `04_optimisation.sql` | Indexes, view rewrite, materialised view, each with its reason |
| `05_optimised_queries.sql` | The queries after tuning |
| `evidence/plans_before/`, `evidence/plans_after/` | Full `EXPLAIN (ANALYZE, BUFFERS)` output per query |
| `evidence/benchmark_*.log`, `evidence/timings_*.json` | Measured medians |
| `evidence/06_extra_checks.log` | Cast versus range, index sizes, refresh cost |
| `evidence/before_after_chart.png` | Chart of the results |
