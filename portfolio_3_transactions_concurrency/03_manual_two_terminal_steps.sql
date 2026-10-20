/*
  LASUTH Clinic Management System
  Portfolio 3: the same experiments by hand in two psql windows
  File: 03_manual_two_terminal_steps.sql

  Open two terminals:  psql -U postgres -d lasuth
  Run SET search_path TO clinic; in both, then follow the steps in order.
  "A:" lines go in the first window, "B:" lines in the second.
  This is how the screenshots for the LMS submission can be produced.
*/

/* ===== Experiment 1: lost update ===== */
/* A: */ UPDATE drug SET stock_qty = 100 WHERE name = 'Demo Coartem';
/* A: */ BEGIN;
/* B: */ BEGIN;
/* A: */ SELECT stock_qty FROM drug WHERE name = 'Demo Coartem';       /* 100 */
/* B: */ SELECT stock_qty FROM drug WHERE name = 'Demo Coartem';       /* 100 */
/* A: */ UPDATE drug SET stock_qty = 70 WHERE name = 'Demo Coartem';
/* B: */ UPDATE drug SET stock_qty = 70 WHERE name = 'Demo Coartem';   /* B hangs here */
/* A: */ COMMIT;                                                       /* B now returns */
/* B: */ COMMIT;
/* A: */ SELECT stock_qty FROM drug WHERE name = 'Demo Coartem';       /* 70, should be 40 */

/* ===== Experiment 2: the same with SELECT ... FOR UPDATE ===== */
/* A: */ UPDATE drug SET stock_qty = 100 WHERE name = 'Demo Coartem';
/* A: */ BEGIN;
/* B: */ BEGIN;
/* A: */ SELECT stock_qty FROM drug WHERE name = 'Demo Coartem' FOR UPDATE;   /* 100 */
/* B: */ SELECT stock_qty FROM drug WHERE name = 'Demo Coartem' FOR UPDATE;   /* B hangs */
/* A: */ UPDATE drug SET stock_qty = 70 WHERE name = 'Demo Coartem';
/* A: */ COMMIT;                                                              /* B returns 70 */
/* B: */ UPDATE drug SET stock_qty = 40 WHERE name = 'Demo Coartem';
/* B: */ COMMIT;

/* While B is hanging, a third window shows who blocks whom: */
SELECT pid, application_name, state, wait_event_type, wait_event, pg_blocking_pids(pid) AS blocked_by, left(query, 60)
FROM pg_stat_activity WHERE datname = 'lasuth' AND state <> 'idle';

/* ===== Experiment 3: write skew, then prevented by SERIALIZABLE ===== */
/* A: */ UPDATE duty_rota SET on_duty = TRUE;
/* A: */ BEGIN ISOLATION LEVEL REPEATABLE READ;
/* B: */ BEGIN ISOLATION LEVEL REPEATABLE READ;
/* A: */ SELECT count(*) FROM duty_rota WHERE on_duty;                 /* 2 */
/* B: */ SELECT count(*) FROM duty_rota WHERE on_duty;                 /* 2 */
/* A: */ UPDATE duty_rota SET on_duty = FALSE WHERE doctor_id = 3;
/* B: */ UPDATE duty_rota SET on_duty = FALSE WHERE doctor_id = 2;
/* A: */ COMMIT;
/* B: */ COMMIT;
/* A: */ SELECT count(*) FROM duty_rota WHERE on_duty;                 /* 0, ward left without a doctor */
/* Repeat with BEGIN ISOLATION LEVEL SERIALIZABLE in both windows: B's COMMIT fails with SQLSTATE 40001. */
