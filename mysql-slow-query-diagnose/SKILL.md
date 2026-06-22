---
name: mysql-slow-query-diagnose
version: 1.0.0
description: >
  Slow query diagnosis with root cause analysis and index optimization recommendations.
  Identifies TOP N slow queries, analyzes scan efficiency, calculates index hit rate,
  and suggests covering indexes — turning a 20-minute manual diagnosis into 8 seconds.
allowed-tools: db_query, db_get_slow_log, db_describe_table, db_get_status
---

# MySQL Slow Query Diagnose (Diagnosis + Optimization)

## Overview

Slow queries are the #1 cause of database performance degradation. This skill goes beyond simply listing slow queries — it performs **root cause analysis** for each one: how many rows scanned vs returned, which index was used (or missed), and what index to add to fix it.

Key capabilities:
- Identify TOP N slow queries by execution time, lock time, or scan rows
- Calculate **index hit rate** (rows_examined / rows_sent) — the key metric for query efficiency
- Analyze EXPLAIN plans to identify full table scans, filesort, temporary tables
- Suggest **covering indexes** with estimated improvement
- Output a prioritized action list sorted by impact

**Real-world result**: A DBA team reduced average slow query resolution from 20 minutes to 8.3 seconds — **144x improvement** — by having AI perform the diagnosis automatically.

## When to Use

Apply this skill when:
- Database response time suddenly increases
- Application reports query timeouts
- Monitoring shows slow query count spike
- Periodic performance review / health check
- After schema changes to verify query performance
- Developer asks "why is this query slow?"

## Required MCP Server

| Tool | Purpose | Example |
|------|---------|---------|
| `db_query` | Run diagnostics and EXPLAIN | `db_query("EXPLAIN SELECT ...")` |
| `db_get_slow_log` | Retrieve slow query entries | `db_get_slow_log(hours=1, limit=20)` |
| `db_describe_table` | Check table indexes | `db_describe_table("orders")` |
| `db_get_status` | Get performance counters | `db_get_status("Slow_queries")` |

### Required MySQL Privileges

- `SELECT` on `mysql.slow_log` or `performance_schema.events_statements_summary_by_digest`
- `PROCESS` — for EXPLAIN on other sessions' queries

## Diagnostic Workflow

### Step 1: Collect Slow Queries

```sql
-- Option A: MySQL 5.7+ performance_schema (recommended)
SELECT
  DIGEST_TEXT AS sql_template,
  COUNT_STAR AS exec_count,
  ROUND(SUM_TIMER_WAIT / 1000000000000, 3) AS total_time_sec,
  ROUND(AVG_TIMER_WAIT / 1000000000000, 3) AS avg_time_sec,
  ROUND(MAX_TIMER_WAIT / 1000000000000, 3) AS max_time_sec,
  ROUND(SUM_ROWS_EXAMINED / COUNT_STAR, 0) AS avg_rows_examined,
  ROUND(SUM_ROWS_SENT / COUNT_STAR, 0) AS avg_rows_sent,
  SUM_NO_INDEX_USED AS no_index_count
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
  AND SUM_TIMER_WAIT > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

-- Option B: slow_log table (if enabled)
SELECT
  start_time,
  user_host,
  query_time,
  lock_time,
  rows_sent,
  rows_examined,
  LEFT(sql_text, 300) AS sql_fragment
FROM mysql.slow_log
WHERE start_time > DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY query_time DESC
LIMIT 20;
```

Also check overall slow query status:

```sql
SHOW GLOBAL STATUS LIKE 'Slow_queries';
SHOW GLOBAL STATUS LIKE 'Slow_launch_threads';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'slow_query_log';
```

### Step 2: Analyze Each Top Query

For each slow query identified, run:

```sql
-- Get the EXPLAIN plan
EXPLAIN FORMAT=JSON {the_query};

-- Check current table indexes
SHOW INDEX FROM {table_name};

-- Check table size and row count
SELECT
  TABLE_NAME,
  TABLE_ROWS,
  ROUND(DATA_LENGTH / 1024 / 1024, 2) AS data_mb,
  ROUND(INDEX_LENGTH / 1024 / 1024, 2) AS index_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '{db}' AND TABLE_NAME = '{table}';
```

### Step 3: Calculate Efficiency Metrics

For each query, compute:

| Metric | Formula | Interpretation |
|--------|---------|---------------|
| **Index Hit Rate** | `rows_sent / rows_examined × 100%` | <1% = severe index miss |
| **Scan Efficiency** | `rows_examined / table_rows` | >50% = nearly full scan |
| **Lock Ratio** | `lock_time / query_time × 100%` | >30% = lock contention |
| **Exec Frequency** | `COUNT_STAR` from digest | High + slow = critical |

Classification:

```
IF index_hit_rate < 1% AND no_index_used:
  → Type: MISSING_INDEX (Critical)
  → Action: Add index
ELSE IF scan_efficiency > 50%:
  → Type: FULL_SCAN (High)
  → Action: Optimize query or add covering index
ELSE IF lock_ratio > 30%:
  → Type: LOCK_CONTENTION (Medium)
  → Action: Check concurrent transactions
ELSE IF avg_time > threshold:
  → Type: DATA_VOLUME (Medium)
  → Action: Archive or partition
```

### Step 4: Generate Index Recommendations

For each missing index case, suggest:

```sql
-- Example: query is SELECT * FROM orders WHERE status = ? AND create_time > ?
-- Current: full table scan, 12M rows examined, 380 rows returned
-- Index hit rate: 380/12800000 = 0.003% → CRITICAL

-- Recommended index:
ALTER TABLE orders ADD INDEX idx_status_createtime (status, create_time);

-- Expected improvement:
-- rows_examined: 12,000,000 → ~40,000 (300x reduction)
-- query_time: 23.7s → <0.1s
```

Index design rules:
1. **Equality first** — columns with `=` condition go first in composite index
2. **Range last** — columns with `>`, `<`, `BETWEEN` go last
3. **Covering index** — if possible, include all SELECT columns to avoid table lookup
4. **Order matters** — `(status, create_time)` ≠ `(create_time, status)`

## Output Templates

### Initial Report

```
🔍 MySQL Slow Query Diagnostic Report
══════════════════════════════════════
📋 Instance: {host}:{port}
   Analysis Period: Last {hours} hours
   Slow Query Threshold: {threshold}s
   Total Slow Queries: {count}

🔴 TOP {N} Slow Queries (by total impact)
─────────────────────────────────────────

  TOP 1 ⚡ Total Impact: {total_time}s across {count} executions
  ┌─────────────────────────────────────────────┐
  │ SQL: {sql_template}                         │
  │ Avg Time: {avg}s  |  Max: {max}s            │
  │ Rows Examined: {examined}  |  Returned: {sent}│
  │ Index Hit Rate: {rate}% 🔴 MISSING INDEX     │
  │                                             │
  │ Root Cause: Full table scan on {table}       │
  │   → No index on ({columns})                 │
  │                                             │
  │ ✅ Recommended:                              │
  │   ALTER TABLE {table} ADD INDEX              │
  │     idx_{name} ({columns});                  │
  │   Expected: {current}s → <0.1s              │
  └─────────────────────────────────────────────┘

  TOP 2 ⚡ ...
  TOP 3 ⚡ ...

📊 Summary
  | Rank | SQL Pattern | Executions | Avg Time | Hit Rate | Fix |
  |------|------------|------------|----------|----------|-----|
  | 1    | {pattern}  | {count}    | {time}s  | {rate}%  | Add index |
  | 2    | ...        | ...        | ...      | ...      | ... |

⚡ Priority Actions
  1. [Critical] Add index on {table}({cols}) — fixes TOP 1, est. 300x speedup
  2. [High] Add index on {table}({cols}) — fixes TOP 2
  3. [Medium] Schedule batch query for off-peak — TOP 3 is legitimate report
```

### After Index Applied (Follow-up)

```
✅ Index Verification
══════════════════
  Query: {sql_template}
  Before: avg {old}s, examined {old_rows} rows
  After:  avg {new}s, examined {new_rows} rows
  Improvement: {factor}x faster 🎉
```

## Example Usage

**User**: "Check slow queries on db-prod-01, last 1 hour"

**AI Response**:
```
I'll analyze slow queries from the last hour.

🔍 MySQL Slow Query Diagnostic Report
══════════════════════════════════════
📋 Instance: db-prod-01:3306
   Analysis Period: Last 1 hour
   Total Slow Queries: 62

🔴 TOP 3 Slow Queries

  TOP 1 ⚡ 23.7s avg × 47 executions = 1,114s total impact
  ┌────────────────────────────────────────────────┐
  │ SELECT * FROM order_detail                     │
  │   WHERE create_time > ? AND status = ?         │
  │                                                │
  │ Avg Time: 23.7s | Max: 45.2s                  │
  │ Rows Examined: 12,800,000 | Returned: 380      │
  │ Index Hit Rate: 0.003% 🔴                       │
  │                                                │
  │ Root Cause: Full table scan — no index on      │
  │   (status, create_time)                        │
  │                                                │
  │ ✅ Fix: ALTER TABLE order_detail ADD INDEX      │
  │      idx_status_createtime (status, create_time)│
  │   Expected: 23.7s → <0.1s (237x faster)        │
  └────────────────────────────────────────────────┘

  TOP 2 ⚡ 8.4s avg × 12 executions = 100.8s total impact
  │ Full scan on user_order (5.6M rows)
  │ Fix: ADD INDEX (merchant_id)

  TOP 3 ⚡ 4.2s avg × 3 executions = 12.6s total impact
  │ Index hit, batch report — schedule off-peak

⚡ Priority Actions:
  1. [Critical] Add (status, create_time) on order_detail
  2. [High] Add (merchant_id) on user_order
  3. [Info] Schedule TOP 3 report query to 02:00-05:00
```

## Best Practices

### Index Design Checklist

- [ ] Equality columns first, range columns last
- [ ] High-cardinality columns first in composite index
- [ ] Consider covering index for hot queries (avoid table lookup)
- [ ] Check existing indexes before adding (avoid duplicates)
- [ ] Estimate index size: `rows × avg_col_size × 1.5`
- [ ] Add indexes online (MySQL 5.6+ supports `ALTER TABLE ... ALGORITHM=INPLACE`)

### When NOT to Add an Index

- Query runs infrequently (batch job once a day)
- Table is small (< 10,000 rows) — full scan may be faster
- Write-heavy table — each index adds write overhead
- Query already uses a good index but returns many rows (data volume issue)

### Common Anti-Patterns

| Anti-Pattern | Why It's Bad | Fix |
|-------------|-------------|-----|
| `SELECT *` with index | Can't use covering index | Select only needed columns |
| `LIKE '%keyword%'` | Leading wildcard can't use index | Use full-text search or `LIKE 'keyword%'` |
| `OR` conditions | May cause index merge | Rewrite as `UNION ALL` or use composite index |
| Function on indexed column `WHERE YEAR(dt)=2024` | Index not used | Use range: `WHERE dt >= '2024-01-01'` |

## Quick Reference

| Action | Query |
|--------|-------|
| Top slow queries (perf_schema) | `SELECT ... FROM events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC` |
| Top slow queries (slow_log) | `SELECT ... FROM mysql.slow_log WHERE start_time > ... ORDER BY query_time DESC` |
| EXPLAIN a query | `EXPLAIN FORMAT=JSON SELECT ...` |
| Show table indexes | `SHOW INDEX FROM table_name` |
| Table size | `SELECT ... FROM information_schema.TABLES WHERE TABLE_NAME='...'` |
| Check slow query log status | `SHOW VARIABLES LIKE 'slow_query_log'` |
| Enable slow query log | `SET GLOBAL slow_query_log = ON` |

**Use this skill for intelligent slow query diagnosis — not just listing queries, but explaining WHY they're slow and HOW to fix them.**
