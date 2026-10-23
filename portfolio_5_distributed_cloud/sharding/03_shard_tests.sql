/*
  LASUTH Clinic Management System
  Portfolio 5: evidence that sharding behaves as designed
  File: sharding/03_shard_tests.sql   (coordinator)
*/
\echo '>>> 1. Rows per shard, counted through the coordinator'
SELECT tableoid::regclass AS shard, count(*) AS encounters, count(DISTINCT patient_id) AS patients
FROM dist.encounter GROUP BY 1 ORDER BY 1;

\echo '>>> 2. No patient is split across shards'
SELECT count(*) AS patients_on_both_shards
FROM (SELECT patient_id FROM dist.encounter GROUP BY patient_id HAVING count(DISTINCT tableoid) > 1) x;

\echo '>>> 3. Folder lookup for one patient: partition pruning sends the query to ONE shard only'
EXPLAIN (VERBOSE, COSTS OFF)
SELECT encounter_id, visit_date, primary_icd10 FROM dist.encounter WHERE patient_id = 25018 ORDER BY visit_date DESC;
SELECT encounter_id, visit_date, primary_icd10 FROM dist.encounter WHERE patient_id = 25018 ORDER BY visit_date DESC LIMIT 5;

\echo '>>> 4a. Hospital wide report: both shards are read at the same time (Async Append)'
\echo '        Grouping is not on the shard key, so PostgreSQL 16 finishes the count on the coordinator.'
SET enable_partitionwise_aggregate = off;
EXPLAIN (VERBOSE, COSTS OFF)
SELECT primary_icd10, count(*) FROM dist.encounter GROUP BY primary_icd10;
\timing on
SELECT primary_icd10, count(*) AS cases FROM dist.encounter GROUP BY primary_icd10 ORDER BY cases DESC LIMIT 5;
\timing off

\echo '>>> 4b. Grouping BY the shard key: the whole aggregation is pushed down and runs on each shard'
SET enable_partitionwise_aggregate = on;
EXPLAIN (VERBOSE, COSTS OFF)
SELECT patient_id, count(*) AS visits, sum(total_billed) AS billed FROM dist.encounter GROUP BY patient_id;
SELECT patient_id, count(*) AS visits, sum(total_billed) AS billed
FROM dist.encounter GROUP BY patient_id ORDER BY visits DESC, patient_id LIMIT 3;

\echo '>>> 5. A new visit is routed by the coordinator to the correct shard'
INSERT INTO dist.encounter VALUES (900000001, 25018, 'LASUTH/2015/025017', now(), 1, 'B50.9', 6500)
RETURNING tableoid::regclass AS stored_on;
DELETE FROM dist.encounter WHERE encounter_id = 900000001;
