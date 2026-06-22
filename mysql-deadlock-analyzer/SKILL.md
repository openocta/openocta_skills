---
name: mysql-deadlock-analyzer
version: 1.0.0
description: >
  Full-chain MySQL deadlock analysis. Captures InnoDB status, parses lock chains,
  identifies deadlock patterns (AB-BA / Gap Lock / FK), finds current lock waits
  and long transactions, outputs structured report with fix recommendations.
  Supports MySQL 5.7+ performance_schema and 5.6 compatibility mode.
allowed-tools: db_query, db_get_status, db_get_processlist
---

# MySQL Deadlock Analyzer

## Overview

Deadlocks are among the most difficult database issues to diagnose — they involve multiple transactions, lock chains, and often intermittent patterns. This skill performs a full-chain deadlock analysis:

1. Capture the latest deadlock from InnoDB status
2. Parse lock chains (who holds what, who waits for what)
3. Classify deadlock pattern (AB-BA mutual wait, Gap Lock, FK cascade, etc.)
4. Check for current lock waits and long transactions
5. Output a structured report with root cause and fix recommendations

## When to Use

- Deadlock alerts or errors from application logs (`Error: 1213 Deadlock found`)
- Proactive monitoring shows `Innodb_deadlocks` counter increasing
- Investigation of lock contention during peak hours
- After schema changes that may affect locking behavior

## Required MCP Server

| Tool | Purpose |
|------|---------|
| `db_query` | Run diagnostic SQL queries |
| `db_get_status` | Get InnoDB deadlock counters |
| `db_get_processlist` | Check for blocking queries |

### Required MySQL Privileges

- `PROCESS` — View all threads and InnoDB status

## Diagnostic Workflow

### Step 1: Capture Deadlock Status

```sql
-- Get deadlock count and recent lock metrics
SHOW GLOBAL STATUS LIKE 'Innodb_deadlocks';
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_waits';
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_time_avg';

-- Capture full InnoDB status (contains LATEST DETECTED DEADLOCK section)
SHOW ENGINE INNODB STATUS;
```

### Step 2: Check Current Lock State (MySQL 5.7+)

```sql
-- Current lock waits (who is blocking whom)
SELECT
  waiting_trx.trx_id AS waiting_trx,
  blocking_trx.trx_id AS blocking_trx,
  waiting_trx.trx_state AS wait_state,
  waiting_trx.trx_started AS wait_started,
  waiting_trx.trx_query AS wait_query,
  blocking_trx.trx_query AS block_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx waiting_trx ON w.requesting_trx_id = waiting_trx.trx_id
JOIN information_schema.innodb_trx blocking_trx ON w.blocking_trx_id = blocking_trx.trx_id;

-- Fallback for MySQL 5.6:
SELECT * FROM information_schema.innodb_trx ORDER BY trx_started;
```

### Step 3: Find Long Transactions

```sql
-- Transactions running longer than 60 seconds
SELECT
  trx_id, trx_state, trx_started,
  TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS duration_sec,
  trx_tables_locked, trx_rows_locked,
  LEFT(trx_query, 200) AS current_query
FROM information_schema.innodb_trx
WHERE TIMESTAMPDIFF(SECOND, trx_started, NOW()) > 60
ORDER BY trx_started;
```

### Step 4: Parse Deadlock Pattern

From the InnoDB status output, extract and classify:

| Pattern | Description | Typical Fix |
|---------|-------------|-------------|
| **AB-BA** | Transaction A locks row1→row2, B locks row2→row1 | Ensure consistent access order |
| **Gap Lock** | Next-key lock on index gap | Reduce range scans, use RC isolation |
| **FK Cascade** | Foreign key triggers cascading lock | Add index on FK column |
| **Auto-Inc** | Concurrent inserts competing for auto-inc lock | Use `innodb_autoinc_lock_mode=2` |
| **Lock Upgrade** | S-lock upgraded to X-lock | Reduce transaction scope |

### Step 5: Check Configuration

```sql
SHOW VARIABLES LIKE 'innodb_print_all_deadlocks';
SHOW VARIABLES LIKE 'tx_isolation';
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';
```

## Output Template

```
🔒 MySQL Deadlock Analysis Report
═════════════════════════════════
📋 Instance: {host}:{port}
   Analysis Time: {timestamp}

🔍 Deadlock Status
  Total Deadlocks: {count}
  Row Lock Waits: {count}
  Avg Lock Wait: {ms}ms

📜 Latest Deadlock (from InnoDB Status)
  ┌─────────────────────────────────────────┐
  │ Transaction A (ID: {trx_id})            │
  │   Status: {status}  Duration: {time}s   │
  │   Holds: {locks_held}                   │
  │   Waits: {locks_waited}                 │
  │   SQL: {sql_fragment}                   │
  ├─────────────────────────────────────────┤
  │ Transaction B (ID: {trx_id})            │
  │   Status: {status}  Duration: {time}s   │
  │   Holds: {locks_held}                   │
  │   Waits: {locks_waited}                 │
  │   SQL: {sql_fragment}                   │
  └─────────────────────────────────────────┘
  Pattern: {AB-BA / Gap Lock / FK / Auto-Inc}

⚠️ Current Lock Waits
  {If blocking chains exist, list them}

📊 Long Transactions ({count} found)
  | Trx ID | Duration | State | SQL |
  |--------|----------|-------|-----|

💡 Root Cause
  {Analysis conclusion}

🛠️ Recommendations
  1. {SQL-level fix} — e.g., add index, change access order
  2. {Code-level fix} — e.g., unify lock order, add retry
  3. {Config-level fix} — e.g., enable innodb_print_all_deadlocks
```

## Example Usage

**User**: "Check for deadlocks on db-prod-01"

**AI Response**:
```
🔒 Deadlock Analysis — db-prod-01:3306

Total Deadlocks: 0 ✅ (no deadlocks recorded)
Row Lock Waits: 0 ✅ (no lock contention)

Long Transactions: 3 found
  | Trx ID | Duration | State    | SQL |
  |--------|----------|----------|-----|
  | 5847M  | 0s       | RUNNING  | SELECT ... |
  | 5847K  | 0s       | RUNNING  | UPDATE ... |

💡 Conclusion: No current deadlock issues.
   Recommendation: Enable innodb_print_all_deadlocks = ON
   to capture future deadlock details automatically.
```

## Best Practices

### Prevention

- Ensure consistent access order across transactions (always lock row1 before row2)
- Keep transactions short — avoid user input inside transactions
- Add appropriate indexes to avoid full table scans (which cause more locking)
- Consider READ COMMITTED isolation level if Gap Locks are an issue
- Enable `innodb_print_all_deadlocks = ON` for continuous monitoring

### Configuration Recommendations

```sql
-- Always enable this in production
SET GLOBAL innodb_print_all_deadlocks = ON;

-- Monitor lock wait timeout (default 50s)
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';

-- For high-concurrency workloads
SET GLOBAL innodb_autoinc_lock_mode = 2;
```

### Advanced: Deadlock Monitoring SQL (for Grafana / Alerts)

```sql
-- Deadlock rate (deadlocks per minute)
SELECT
  VARIABLE_VALUE AS deadlocks,
  NOW() AS collected_at
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_deadlocks';

-- Row lock contention rate
SELECT
  VARIABLE_VALUE AS lock_waits,
  NOW() AS collected_at
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_row_lock_waits';

-- Average lock wait time (milliseconds)
SELECT
  ROUND(VARIABLE_VALUE / 1000, 2) AS avg_lock_wait_ms
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_row_lock_time_avg';
```

Alert thresholds for monitoring:
| Metric | Warning | Critical |
|--------|---------|----------|
| Deadlocks/min | > 1 | > 5 |
| Row lock waits/min | > 100 | > 500 |
| Avg lock wait | > 100ms | > 500ms |

### Advanced: pt-deadlock-logger Integration

For continuous deadlock capture beyond `innodb_print_all_deadlocks`:

```bash
# Percona Toolkit: capture deadlocks to a file
pt-deadlock-logger \
  --host={host} --port={port} \
  --user={user} --password={password} \
  --dest D=/tmp/deadlocks.log \
  --daemonize --interval 30

# Output format:
# server ts thread txn_id txn_time user host ip db tbl idx lock_type lock_mode wait_hold query
```

### Advanced: Deadlock Replay with EXPLAIN

After identifying the deadlocked SQL, replay to verify the lock pattern:

```sql
-- Check the execution plan of the deadlocked query
EXPLAIN FORMAT=JSON {deadlocked_sql};

-- Check if the query uses the correct index
SHOW INDEX FROM {table};

-- Verify row scan count vs actual data volume
SELECT COUNT(*) FROM {table} WHERE {where_clause};
```

## Quick Reference

| Action | Query |
|--------|-------|
| Deadlock count | `SHOW STATUS LIKE 'Innodb_deadlocks'` |
| InnoDB status | `SHOW ENGINE INNODB STATUS` |
| Current transactions | `SELECT * FROM information_schema.innodb_trx` |
| Lock waits (5.7+) | `SELECT * FROM performance_schema.data_lock_waits` |
| Lock waits (5.6) | `SELECT * FROM information_schema.innodb_lock_waits` |
| Enable deadlock logging | `SET GLOBAL innodb_print_all_deadlocks = ON` |

**Use this skill for comprehensive deadlock diagnosis — from detection to root cause to fix.**
