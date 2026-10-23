#!/usr/bin/env bash
# LASUTH Clinic Management System
# Portfolio 5: synchronous versus asynchronous replication, standby loss, and failover
# File: replication/02_consistency_and_failover.sh
PG=/usr/lib/postgresql/16/bin
export PGHOST=localhost PGUSER=postgres
P="psql -p 5432 -d lasuth -X"
S="psql -p 5433 -d lasuth -X"
say() { echo; echo ">>> $*"; }
as_pg() { su postgres -c "$*"; }

# 200 single row commits, used to measure commit cost
for i in $(seq 1 200); do echo "insert into clinic.audit_log (table_name, record_id, action) values ('commit_test', $i, 'TEST');"; done > /tmp/commits.sql

say "1. Asynchronous replication (default): 200 separate commits"
s=$(date +%s.%N); $P -q -f /tmp/commits.sql; e=$(date +%s.%N)
echo "async: $(echo "($e - $s) * 1000 / 200" | bc -l | cut -c1-5) ms per commit"

say "2. Switch to synchronous replication: a commit returns only after the standby has the WAL"
$P -c "alter system set synchronous_standby_names = 'lasuth_standby_1'" -c "select pg_reload_conf()" > /dev/null
sleep 1
$P -c "select application_name, sync_state from pg_stat_replication"
s=$(date +%s.%N); $P -q -f /tmp/commits.sql; e=$(date +%s.%N)
echo "sync:  $(echo "($e - $s) * 1000 / 200" | bc -l | cut -c1-5) ms per commit"

say "3. The standby fails while replication is synchronous"
as_pg "$PG/pg_ctl -D /home/claude/pg/replica -m fast stop" | tail -1
$P -c "select count(*) as connected_standbys from pg_stat_replication"
echo "A records officer registers a patient on the primary..."
( $P -c "insert into clinic.patient (hospital_no, first_name, last_name, sex, date_of_birth) values ('LASUTH/2026/700003','Sync','Wait','M','1980-01-01')" > /tmp/sync_insert.out 2>&1 ) &
sleep 3
$P -c "select pid, state, wait_event_type, wait_event, now() - query_start as waiting_for, left(query, 45) as query from pg_stat_activity where wait_event = 'SyncRep'"
echo "...the commit is stuck waiting for a standby that is not there. Operator cancels the wait:"
$P -Atc "select pg_cancel_backend(pid) from pg_stat_activity where wait_event = 'SyncRep'"
wait; cat /tmp/sync_insert.out
$P -c "select hospital_no from clinic.patient where hospital_no = 'LASUTH/2026/700003'"
echo "The row is visible: it committed locally but was never confirmed on a second copy."
echo "Availability option: drop to asynchronous until the standby returns."
$P -c "alter system set synchronous_standby_names = ''" -c "select pg_reload_conf()" > /dev/null

say "4. Standby restarts and catches up from the replication slot"
as_pg "$PG/pg_ctl -D /home/claude/pg/replica -o '-p 5433 -c hot_standby=on' -l /home/claude/pg/replica.log start" | tail -1
sleep 3
$P -c "select application_name, state, sync_state, pg_wal_lsn_diff(sent_lsn, replay_lsn) as bytes_behind from pg_stat_replication"
$S -c "select hospital_no from clinic.patient where hospital_no = 'LASUTH/2026/700003'"

say "5. Failover: the primary crashes"
$P -Atc "insert into clinic.patient (hospital_no, first_name, last_name, sex, date_of_birth) values ('LASUTH/2026/700004','Last','Before Crash','F','1977-07-07') returning 'last row written on old primary: ' || hospital_no"
sleep 1
as_pg "$PG/pg_ctl -D /home/claude/pg/primary -m immediate stop" | tail -1
psql -p 5432 -d lasuth -Atc "select 1" 2>&1 | head -1
s=$(date +%s.%N)
as_pg "$PG/pg_ctl -D /home/claude/pg/replica promote" | tail -1
e=$(date +%s.%N)
echo "promotion took $(echo "($e - $s)" | bc -l | cut -c1-4) s"
$S -Atc "checkpoint" > /dev/null
$S -Atc "select 'port 5433 in_recovery=' || pg_is_in_recovery() || ', now on timeline ' || timeline_id from pg_control_checkpoint()"
$S -c "select hospital_no, last_name from clinic.patient where hospital_no like 'LASUTH/2026/7000%' order by 1"
$S -Atc "insert into clinic.patient (hospital_no, first_name, last_name, sex, date_of_birth) values ('LASUTH/2026/700005','First','After Failover','M','1999-09-09') returning 'new primary accepted write: ' || hospital_no"
echo "The sharded tables are reachable from the new primary as well:"
$S -c "select tableoid::regclass as shard, count(*) from dist.encounter group by 1 order by 1"
