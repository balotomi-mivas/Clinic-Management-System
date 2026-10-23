#!/usr/bin/env bash
# LASUTH Clinic Management System
# Portfolio 4: Key value model with Redis
# File: 03_redis_keyvalue.sh
#
# Three jobs at LASUTH that need sub millisecond answers and do not need to
# live forever, so they suit an in memory key value store better than the
# relational database:
#   1. The live GOPD waiting queue (sorted set)
#   2. A short lived cache of a patient's summary card (hash with expiry)
#   3. Live bed counts per ward (hash counters with atomic increments)
#
# Usage:  bash 03_redis_keyvalue.sh > evidence/redis_session_log.txt
R="redis-cli --no-raw"
run() { echo "redis> $*"; $R "$@"; echo; }

echo "LASUTH Portfolio 4: Redis key value session, $(date -Iseconds)"
echo "Server: $($R INFO server | grep redis_version | tr -d '\r')"
echo
$R DEL queue:gopd:2026-10-16 card:LASUTH/2021/002066 beds:children_emergency > /dev/null

echo "=== 1. GOPD waiting queue: score = arrival time (epoch seconds), so the queue orders itself ==="
run ZADD queue:gopd:2026-10-16 1792130400 LASUTH/2021/002066
run ZADD queue:gopd:2026-10-16 1792130460 LASUTH/2015/025017
run ZADD queue:gopd:2026-10-16 1792130520 LASUTH/2026/000001
run ZADD queue:gopd:2026-10-16 1792130580 LASUTH/2024/041999
echo "# A patient asks how many people are ahead of them (0 based rank)"
run ZRANK queue:gopd:2026-10-16 LASUTH/2026/000001
echo "# Display board shows the whole queue in arrival order"
run ZRANGE queue:gopd:2026-10-16 0 -1 WITHSCORES
echo "# Doctor presses Call Next: remove and return the earliest arrival in one atomic step,"
echo "# so two consulting rooms can never call the same patient"
run ZPOPMIN queue:gopd:2026-10-16
run ZCARD queue:gopd:2026-10-16
echo "# The queue disappears by itself at midnight"
run EXPIREAT queue:gopd:2026-10-16 1792191600
run TTL queue:gopd:2026-10-16

echo "=== 2. Patient summary card cache: filled from PostgreSQL on first read, kept 15 minutes ==="
run HSET card:LASUTH/2021/002066 name "Sade Kalu" genotype SS blood_group A+ allergies "none recorded" last_visit 2026-10-06 last_diagnosis "Acute upper respiratory infection, unspecified"
run EXPIRE card:LASUTH/2021/002066 900
run HGETALL card:LASUTH/2021/002066
run TTL card:LASUTH/2021/002066
echo "# When a doctor records a new diagnosis the application deletes the card,"
echo "# so the next read comes fresh from PostgreSQL (cache aside invalidation)"
run DEL card:LASUTH/2021/002066
run EXISTS card:LASUTH/2021/002066

echo "=== 3. Live bed board for the Children Emergency Ward ==="
run HSET beds:children_emergency total 24 occupied 21
echo "# Two admissions arrive from two terminals; HINCRBY is atomic, so no lost update"
run HINCRBY beds:children_emergency occupied 1
run HINCRBY beds:children_emergency occupied 1
echo "# A discharge"
run HINCRBY beds:children_emergency occupied -1
run HMGET beds:children_emergency total occupied

echo "=== 4. Latency of the queue read, 2,000 calls ==="
redis-benchmark -q -n 2000 -c 4 ZRANGE queue:gopd:2026-10-16 0 -1 2>/dev/null | tr '\r' '\n' | tail -1
