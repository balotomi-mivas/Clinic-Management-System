#!/usr/bin/env bash
# LASUTH Clinic Management System
# Portfolio 5: replication, consistency and availability tests
# File: replication/01_replication_tests.sh
# Primary: port 5432   Standby: port 5433
export PGHOST=localhost PGUSER=postgres
P="psql -p 5432 -d lasuth -X"
S="psql -p 5433 -d lasuth -X"
say() { echo; echo ">>> $*"; }

say "1. Roles: the primary is not in recovery, the standby is"
$P -Atc "select 'primary  port 5432  in_recovery=' || pg_is_in_recovery()"
$S -Atc "select 'standby  port 5433  in_recovery=' || pg_is_in_recovery()"

say "2. Replication status seen from the primary"
$P -c "select application_name, state, sync_state, sent_lsn, replay_lsn, pg_wal_lsn_diff(sent_lsn, replay_lsn) as bytes_behind from pg_stat_replication"
$P -c "select slot_name, slot_type, active, restart_lsn from pg_replication_slots"

say "3. A patient registered on the primary appears on the standby"
$P -Atc "insert into clinic.patient (hospital_no, first_name, last_name, sex, date_of_birth, lga) values ('LASUTH/2026/700001','Replica','Test','F','1995-05-05','Ikeja') returning 'primary inserted ' || hospital_no || ' at ' || clock_timestamp()"
for i in 1 2 3 4 5 6 7 8 9 10; do
  r=$($S -Atc "select count(*) from clinic.patient where hospital_no='LASUTH/2026/700001'")
  if [ "$r" = "1" ]; then echo "standby sees the row after poll $i at $($S -Atc 'select clock_timestamp()')"; break; fi
  sleep 0.05
done
$S -c "select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), now() - pg_last_xact_replay_timestamp() as replay_delay"

say "4. The standby is read only: writes are refused"
$S -c "insert into clinic.patient (hospital_no, first_name, last_name, sex, date_of_birth) values ('LASUTH/2026/700002','X','Y','M','1990-01-01')"

say "5. Reporting load can be moved to the standby: the monthly report runs there"
$S -c "select date_trunc('month', month)::date as month, sum(cases) as diagnoses from clinic.mv_monthly_disease_burden where month >= '2026-07-01' group by 1 order by 1"
