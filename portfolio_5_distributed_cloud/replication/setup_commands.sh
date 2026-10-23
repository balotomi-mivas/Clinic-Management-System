#!/usr/bin/env bash
# LASUTH Clinic Management System
# Portfolio 5: streaming replication setup (commands exactly as run)
# File: replication/setup_commands.sh
PG=/usr/lib/postgresql/16/bin

# Primary was started with WAL suitable for replication
$PG/pg_ctl -D /home/claude/pg/primary -o "-p 5432 -c wal_level=replica -c max_wal_senders=5" start

# Clone the primary into a standby. -R writes primary_conninfo and standby.signal,
# -C -S creates a physical replication slot so the primary keeps WAL the standby still needs.
$PG/pg_basebackup -h localhost -p 5432 -U postgres -D /home/claude/pg/replica \
    -R -X stream -C -S lasuth_standby_1 -d "application_name=lasuth_standby_1" -P

# Start the standby on port 5433 as a read only hot standby
$PG/pg_ctl -D /home/claude/pg/replica -o "-p 5433 -c hot_standby=on" start
