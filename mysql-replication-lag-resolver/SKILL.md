---
name: mysql-replication-lag-resolver
version: 1.0.0
description: >
  Replication lag root cause analysis with automated resolution workflow. Detects lag,
  identifies blocking queries on the master, presents KILL candidates with safety classification,
  and executes KILL only after double user confirmation. Reduces recovery from 20 minutes to 2 minutes.
allowed-tools: db_query, db_get_status, db_get_processlist, db_kill_query
---

# MySQL Replication Lag Resolver (Auto-Diagnose + Fix)

## Overview

Replication lag is one of the most critical database incidents — it means read replicas are falling behind the master, serving stale data to applications. Traditional resolution requires DBA to: receive alert → open laptop → connect VPN → login to jumpbox → check slave status → find blocking queries on master → decide what to kill → execute KILL → monitor recovery. **20+ minutes at 2 AM.**

This skill automates the entire diagnosis and presents a one-click resolution:

1. **Detect** — Check Seconds_Behind_Master and replication health
2. **Root Cause** — Find long-running queries on master blocking binlog sync
3. **Classify** — Mark each query as safe/caution/dangerous to kill
4. **Present** — Show candidates with impact analysis
5. **Resolve** — Execute KILL with double user confirmation
6. **Verify** — Monitor lag recovery in real-time

**Real-world result**: From 20 minutes to 2 minutes — **10x improvement**. DBA only needs to say "confirm" on their phone.

## When to Use

Apply this skill when:
- Replication lag alert fires (Seconds_Behind_Master > threshold)
- Application reports stale reads from replicas
- Scheduled monitoring detects lag trend
- After bulk operations (data migration, batch updates) that may cause lag
- Proactive check during peak hours

## Required MCP Server

| Tool | Purpose | Example |
|------|---------|---------|
| `db_query` | Check replication status | `db_query("SHOW SLAVE STATUS")` |
| `db_get_status` | Get replication counters | `db_get_status("Seconds_Behind_Master")` |
| `db_get_processlist` | Find blocking queries | `db_get_processlist()` |
| `db_kill_query` | Terminate blocking queries | `db_kill_query(thread_id=123)` |

### Required MySQL Privileges

- `REPLICATION CLIENT` — View replication status
- `PROCESS` — View all threads on master
- `SUPER` or `CONNECTION_ADMIN` — KILL queries (on master only)

## ⚠️ CRITICAL: Safety Rules

### NEVER Kill
- Replication threads (`system user` on slaves)
- DDL operations (ALTER, CREATE, DROP) — killing DDL on master can corrupt data dictionary
- The diagnostic session itself
- Any thread running < 60 seconds (may be legitimate)

### KILL with Caution
| Type | Risk | Guidance |
|------|------|----------|
| UPDATE/DELETE | Partial rollback, breaks idempotent operations | Kill only if > 300s AND lag is critical |
| INSERT...SELECT | May leave partial data | Verify target table before killing |
| Large SELECT | Safe but wastes work | Prefer killing SELECTs first |

### Mandatory Approval Protocol

**This skill enforces double-confirmation for ALL KILL operations:**

1. **Phase 1**: Present findings + candidates
2. **Phase 2**: User selects targets ("KILL 123, 124")
3. **Phase 3**: AI reads back + user types "CONFIRM KILL"
4. **Phase 4**: Execute KILL
5. **Phase 5**: Monitor recovery

## Diagnostic Workflow

### Step 1: Assess Replication Health

```sql
-- Master status
SHOW MASTER STATUS;

-- Slave status (run on replica)
SHOW SLAVE STATUS\G

-- Key fields from SHOW SLAVE STATUS:
--   Seconds_Behind_Master: {lag_seconds}
--   Slave_IO_Running: Yes/No
--   Slave_SQL_Running: Yes/No
--   Last_Error: {error_message}
--   Relay_Master_Log_File: {master_log}
--   Exec_Master_Log_Pos: {executed_pos}
--   Read_Master_Log_Pos: {read_pos}
```

Classify lag severity:

| Seconds_Behind_Master | Severity | Action |
|----------------------|----------|--------|
| 0-30 | ✅ Normal | No action needed |
| 30-120 | 🟡 Warning | Monitor, check trend |
| 120-600 | 🔴 High | Diagnose root cause |
| > 600 | 🔴 Critical | Immediate intervention |

### Step 2: Identify Root Cause on Master

```sql
-- Find long-running queries on master that may block binlog sync
SELECT
  ID, USER, HOST, DB, COMMAND,
  TIME AS duration_sec,
  STATE,
  LEFT(INFO, 300) AS sql_fragment
FROM information_schema.PROCESSLIST
WHERE COMMAND != 'Sleep'
  AND TIME > 60
  AND USER != 'system user'
ORDER BY TIME DESC;

-- Check master binlog position vs what slaves have read
SHOW MASTER STATUS;
-- Compare with Exec_Master_Log_Pos from each slave
```

Root cause patterns:

| Pattern | Cause | Fix |
|---------|-------|-----|
| Long SELECT on master | Binlog events queued behind the SELECT | Kill the SELECT |
| Large UPDATE/DELETE | Single big transaction blocks binlog | Kill if > 300s |
| Binlog Dump idle | Network issue between master/slave | Check network, not kill |
| Slave_SQL stopped | Duplicate key / constraint error | Fix error, START SLAVE |

### Step 3: Classify Candidates

For each long-running query on master, classify:

```
IF SQL starts with ALTER/CREATE/DROP/TRUNCATE/RENAME:
  → Type: DDL, Kill: NOT RECOMMENDED (explain risk to user)
ELSE IF SQL starts with SELECT:
  → Type: SELECT, Kill: SAFE (kill first)
ELSE IF SQL starts with UPDATE/DELETE and duration > 300:
  → Type: DML, Kill: CAUTION (present risk)
ELSE IF Command = 'Binlog Dump':
  → Type: REPLICATION, Kill: NEVER
ELSE:
  → Type: OTHER, Kill: REVIEW
```

### Step 4: Present to User

Show candidates using the template below. Wait for user response.

### Step 5: Execute KILL (After Confirmation)

```sql
-- Kill confirmed threads
KILL {thread_id};

-- If KILL fails (thread already gone), report it
-- Alternative: KILL QUERY {thread_id} (kills query, keeps connection)
```

### Step 6: Monitor Recovery

After killing, check lag every 10-30 seconds:

```sql
-- Recheck slave status
SHOW SLAVE STATUS\G

-- Expected recovery pattern:
-- Seconds_Behind_Master: 623 → 412 → 89 → 0
```

Report recovery timeline to user.

## Output Templates

### Initial Diagnosis

```
🔄 Replication Lag Alert
═══════════════════════
📊 Current Status
  Master: {host}:{port} (Binlog: {file}, Pos: {pos})
  Slave:  {host}:{port}
  Lag: {seconds}s 🔴 CRITICAL
  IO Thread: {io_status}
  SQL Thread: {sql_status}

🔍 Root Cause Analysis
  Cause: {count} long-running queries on master blocking binlog sync
  Impact: Slave is {seconds}s behind, serving stale data to {app_count} applications

📋 Blocking Queries (candidates for KILL)
  | Thread | User | Duration | Type | SQL | Kill Safety |
  |--------|------|----------|------|-----|-------------|
  | 23451  | app1 | 892s     | SELECT | SELECT ... FROM order_detail | ✅ Safe |
  | 23487  | app2 | 567s     | SELECT | SELECT ... FROM user_session | ✅ Safe |
  | 23502  | app3 | 423s     | SELECT | SELECT ... FROM payment_record | ✅ Safe |

  ℹ️ Skipped: 2 Binlog Dump threads (replication, NEVER kill)

⚠️ Action Required (Step 1 of 2):
  Reply "KILL {thread_ids}" to select targets,
  "KILL ALL" for all candidates,
  or "SKIP" to cancel.
  ⚠️ A final confirmation will be required before execution.
```

### After User Selects (Double Confirmation)

```
⚠️ DOUBLE CONFIRMATION REQUIRED (Step 2 of 2)
══════════════════════════════════════════════
You are about to KILL {count} queries on MASTER:

  | Thread | User | Duration | Type | SQL |
  |--------|------|----------|------|-----|
  | 23451  | app1 | 892s     | SELECT | ... |
  | 23487  | app2 | 567s     | SELECT | ... |
  | 23502  | app3 | 423s     | SELECT | ... |

  ❗️ Please type EXACTLY "CONFIRM KILL" to proceed.
     Any other response cancels this operation.
```

### Recovery Report

```
✅ KILL Execution Complete
═════════════════════════
  Thread 23451 (892s, SELECT): ✅ Killed
  Thread 23487 (567s, SELECT): ✅ Killed
  Thread 23502 (423s, SELECT): ✅ Killed

📈 Recovery Timeline
  0s:   Lag = 623s (KILL executed)
  30s:  Lag = 412s ↓
  60s:  Lag = 89s ↓
  90s:  Lag = 0s ✅ Replication normalized

💡 Root Cause Summary:
  3 concurrent full-table-scan queries on master blocked binlog sync.
  Recommended: Add indexes on order_detail(status, create_time) and
  user_session(last_active) to prevent recurrence.
```

## Example Usage

**User**: "Replication lag alert on db-slave-01"

**AI** (Phase 1):
```
🔄 Replication Lag Alert
═══════════════════════
  Slave: db-slave-01:3306
  Lag: 623s 🔴 CRITICAL
  Root Cause: 3 long-running SELECT queries on master blocking binlog sync

  KILL candidates:
    23451 · app1 · 892s · SELECT * FROM order_detail WHERE ...
    23487 · app2 · 567s · SELECT * FROM user_session WHERE ...
    23502 · app3 · 423s · SELECT * FROM payment_record WHERE ...

  Reply "KILL ALL" or specify thread IDs.
```

**User**: "KILL ALL"

**AI** (Phase 3 — Double check):
```
⚠️ CONFIRM: Kill all 3 queries on master?
Type "CONFIRM KILL" to proceed.
```

**User**: "CONFIRM KILL"

**AI** (Phase 4+5):
```
✅ 3 queries killed. Lag recovering: 623 → 412 → 89 → 0. Normalized.
```

## Best Practices

### Preventing Replication Lag

| Prevention | How |
|-----------|-----|
| Set long_query_time low | `SET GLOBAL long_query_time = 1` |
| Monitor lag proactively | Check every 30s, alert at > 60s |
| Use row-based replication | RBR is more efficient for most workloads |
| Batch operations | Split large UPDATEs into 1000-row batches |
| Parallel replication | `SET GLOBAL slave_parallel_workers = 4` (MySQL 5.7+) |

### After Resolving Lag

1. **Check data consistency** — Compare row counts on master vs slave for critical tables
2. **Root cause remediation** — Add missing indexes to prevent recurrence
3. **Update monitoring** — Lower alert threshold if this was a recurring issue
4. **Notify stakeholders** — Applications may have cached stale data

## Quick Reference

| Action | Command |
|--------|---------|
| Check slave status | `SHOW SLAVE STATUS\G` |
| Check master status | `SHOW MASTER STATUS` |
| Start slave | `START SLAVE` |
| Stop slave | `STOP SLAVE` |
| Skip one replication error | `SET GLOBAL sql_slave_skip_counter = 1; START SLAVE` |
| Show long queries | `SELECT * FROM information_schema.PROCESSLIST WHERE TIME > 60` |
| Kill a thread | `KILL {thread_id}` |
| Kill query only | `KILL QUERY {thread_id}` |

**Use this skill when replication lag fires — diagnose, present options, resolve with one confirmation.**
