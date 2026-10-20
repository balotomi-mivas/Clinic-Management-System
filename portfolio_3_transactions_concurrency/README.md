# Portfolio 3: Transactions and Concurrency

Seven experiments were run against the LASUTH database with two genuinely concurrent sessions. Each one reproduces a problem a hospital would actually meet, shows it happening, and then shows the control that prevents it. The full timestamped transcript is `evidence/transactions_log.txt`.

## How the evidence was produced

`02_concurrency_runner.py` opens two PostgreSQL connections (A and B) plus an observer connection. It interleaves statements in a fixed order, runs any statement that is expected to block in a background thread, and while it waits queries `pg_stat_activity` and `pg_blocking_pids()` to record who is blocked by whom. The same steps can be replayed by hand in two `psql` windows with `03_manual_two_terminal_steps.sql`.

```
psql -U postgres -d lasuth -f 01_setup.sql
python3 02_concurrency_runner.py
```

## Results

| # | Scenario at LASUTH | Isolation level | What happened | Control demonstrated |
|---|---|---|---|---|
| 1 | Pharmacist dispenses a prescription | Read Committed | Stock 100 to 76, prescription DISPENSED, drug line added to the bill, all in one `COMMIT` | Atomicity through `sp_dispense_prescription` |
| 2 | Dispensing fails on the second drug (2 vials in stock, 5 needed) | Read Committed | Procedure raised `P0002`; later statements refused with `25P02`; after `ROLLBACK` Coartem was still 76 even though the procedure had already reduced it | Atomic rollback of partial work |
| 2b | Lab scientist enters a batch of results, one is invalid | Read Committed | Invalid result hit a `CHECK` (`23514`); `ROLLBACK TO SAVEPOINT` undid only that one, the valid result committed and was captured by the audit trigger | Savepoints |
| 3 | Two pharmacists issue 30 tablets each from 100 | Read Committed | **Lost update**: stock ended at 70 instead of 40. Session B was seen waiting on A's transaction lock, then overwrote A's work | Fixed by `SELECT ... FOR UPDATE` (result 40) and, alternatively, by Repeatable Read, where B was refused with `40001` and retried (result 40) |
| 4 | Doctor reads a malaria result twice while the lab amends it | Read Committed vs Repeatable Read | Read Committed showed two different values in one transaction; Repeatable Read showed the same value both times | Snapshot isolation (MVCC) |
| 5 | Two doctors leave the Children Emergency Ward rota at the same moment | Repeatable Read vs Serializable | **Write skew**: under Repeatable Read both commits succeeded and the ward had 0 doctors. Under Serializable the second commit failed with `40001` and 1 doctor stayed on duty | Serializable Snapshot Isolation |
| 6 | Two receptionists book Dr Ogunleye at 10:00 and 10:05 | Read Committed | B waited on A's uncommitted row, then failed with `23P01` on `no_double_booking` once A committed | Exclusion constraint |
| 7 | Two sessions update the same two drugs in opposite order | Read Committed | **Deadlock** detected after 1 second (`40P01`); PostgreSQL cancelled one session. Server log in `evidence/deadlock_server_log.txt` | Fixed by locking drugs in ascending `drug_id` order inside the procedure; the rerun queued instead of deadlocking |

## Discussion

PostgreSQL uses multiversion concurrency control: readers see a snapshot and never block writers. That is why Scenario 4 behaves as it does, and why the lost update in Scenario 3 is possible at Read Committed. Session B did wait for A's row lock, but it then wrote a value it had calculated from a stale read. The database protected the row; it could not protect logic that lived in the application.

Three ways of fixing that were compared. An atomic `UPDATE ... SET stock_qty = stock_qty - 30` is the simplest and is what the procedure uses. `SELECT ... FOR UPDATE` is pessimistic and suits the pharmacy, where conflicts on popular drugs are frequent and a short wait is better than an error. Repeatable Read is optimistic: it costs nothing when there is no conflict but the application must catch `40001` and retry.

Write skew (Scenario 5) is the case I found most instructive. No row was updated by both sessions, so row locks never conflicted, yet the combined result broke a rule that each transaction checked. Only Serializable detects it, by tracking read and write dependencies. For rules that span rows, such as minimum staffing, Serializable with a retry loop is the right tool. An alternative is to lock the ward row explicitly before counting.

The deadlock in Scenario 7 was resolved by PostgreSQL in about one second (`deadlock_timeout`), but the cancelled transaction is lost work for a pharmacist. Consistent lock ordering removes the cycle entirely, which is why the procedure sorts by `drug_id` before locking.

## Files

| File | Purpose |
|---|---|
| `01_setup.sql` | Dispensing procedure, ward duty rota, two test drugs |
| `02_concurrency_runner.py` | Runs all seven scenarios with two live sessions |
| `03_manual_two_terminal_steps.sql` | The same experiments by hand for screenshots |
| `evidence/transactions_log.txt` | Full timestamped transcript |
| `evidence/deadlock_server_log.txt` | PostgreSQL server log entry for the deadlock |
| `evidence/audit_trail_after_tests.log` | Audit rows written for the lab result changes |
