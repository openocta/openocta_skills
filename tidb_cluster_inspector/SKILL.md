---
name: tidb-cluster-inspector
version: 1.1.0
description: >
  Comprehensive TiDB cluster inspection. Checks cluster topology, node health,
  slow queries, hot regions, TiKV storage status, PD scheduling, leader skew,
  and TopSQL drain (latency / execution count / memory). Outputs a full
  inspection report with prioritized findings. Compatible with TiDB v4.0+.
allowed-tools: db_query, db_get_status, db_get_variable
---

# TiDB Cluster Inspector

## Overview

TiDB clusters have a complex distributed architecture (TiDB + PD + TiKV) where issues in any component can cascade. This skill performs a systematic inspection across all layers:

1. **Topology** — Map all nodes, versions, uptime
2. **Node Health** — Check each TiDB/PD/TiKV node status
3. **Slow Queries** — Identify TOP N slow queries
4. **Hot Regions** — Detect read/write hotspots (hot-degree ranked)
5. **TiKV Storage** — Capacity and region distribution
6. **PD Scheduling** — Leader/region balance check
7. **Leader Skew** — Detect leader concentration imbalance across TiKV stores
8. **TopSQL** — Rank SQL by total latency, execution count, and memory

## When to Use

- Periodic cluster health inspection (daily/weekly)
- After TiDB version upgrades
- Performance degradation investigation
- Capacity planning and scaling decisions
- Pre-maintenance readiness check

## Required MCP Server

| Tool | Purpose |
|------|---------|
| `db_query` | Query TiDB system tables |
| `db_get_status` | Get server metrics |
| `db_get_variable` | Get configuration |

### Required Privileges

- `SELECT` on `information_schema.*`

## Diagnostic Workflow

### Step 1: Cluster Topology

```sql
-- All nodes: type, address, version, status, uptime
SELECT
  TYPE AS role, INSTANCE AS address,
  VERSION AS version, STATUS AS status,
  START_TIME AS start_time
FROM information_schema.cluster_info
ORDER BY TYPE, INSTANCE;
```

Verify:
- All expected nodes present
- Version consistency across nodes
- No recently restarted nodes (uptime check)

### Step 2: Node Health

```sql
-- Per-node server info
SELECT
  TYPE, INSTANCE, VERSION,
  TIMESTAMPDIFF(HOUR, START_TIME, NOW()) AS uptime_hours
FROM information_schema.cluster_info
WHERE STATUS != 'Up' OR STATUS IS NULL;
```

Alert conditions:
- Any node `STATUS != 'Up'` → critical
- Uptime < 24 hours → recently restarted, investigate
- Version mismatch → upgrade incomplete

### Step 3: Slow Query Analysis

```sql
-- TiDB v4.0+: slow query from system table
SELECT
  Txn_start, Query_time, Parse_time, Compile_time,
  Process_time, Wait_time, Backoff_time,
  Request_count, Coprocessor_involved_count,
  LEFT(Query, 300) AS sql_fragment
FROM information_schema.slow_query
WHERE Time > DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY Query_time DESC
LIMIT 20;

-- TiDB v6.0+: cluster-wide slow query
SELECT * FROM information_schema.cluster_slow_query
WHERE Time > DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY Query_time DESC LIMIT 20;
```

### Step 4: Hot Region Detection

```sql
-- Current hot regions: which tables/indexes are hot, read vs write, and how hot.
-- Columns verified against TiDB information_schema.TIDB_HOT_REGIONS (v4.0+).
SELECT
  DB_NAME,
  TABLE_NAME,
  INDEX_NAME,
  TYPE AS hot_type,             -- 'read' or 'write'
  MAX_HOT_DEGREE AS hot_degree, -- >0 means hot; higher = hotter
  FLOW_BYTES,                   -- bytes read + written in the region
  REGION_COUNT
FROM information_schema.TIDB_HOT_REGIONS
ORDER BY MAX_HOT_DEGREE DESC, FLOW_BYTES DESC
LIMIT 20;
```

Interpretation:
- `MAX_HOT_DEGREE > 0` → region is a hotspot; the higher the degree the hotter
- `TYPE = 'read'` → read hotspot: add a covering/composite index or scatter the region to reduce point reads
- `TYPE = 'write'` → write hotspot: usually auto-increment or sequential inserts; consider region pre-splitting
- **Pre-splitting is a write operation** (run via `pd-ctl` or a dedicated tool such as `tidba split`); it is out of scope for this read-only skill — only recommend it

### Step 5: TiKV Storage Status

```sql
-- Per-store storage and region distribution
SELECT
  STORE_ID,
  ADDRESS,
  STORE_STATE_NAME AS state,
  CAPACITY,
  AVAILABLE,
  USED_SIZE,
  ROUND(USED_SIZE / CAPACITY * 100, 2) AS usage_pct,
  REGION_COUNT,
  LEADER_COUNT
FROM information_schema.tikv_store_status
ORDER BY STORE_ID;
```

Alert conditions:
- Usage > 80% → plan expansion
- Leader count heavily imbalanced → PD scheduling issue
- Any store `state != 'Up'` → critical

### Step 6: PD Scheduling

```sql
-- Check PD scheduling configuration
SHOW CONFIG WHERE TYPE = 'pd' AND NAME LIKE '%schedule%';
SHOW CONFIG WHERE TYPE = 'pd' AND NAME LIKE '%replicate%';
```

Key configs:
- `schedule.leader-schedule-limit` — Leader balance speed
- `schedule.region-schedule-limit` — Region balance speed
- `schedule.enable-cross-table-merge` — Region merge optimization

### Step 7: Region Leader Skew

```sql
-- Leader concentration per TiKV store (cluster-level, lightweight — no full
-- region scan). leader_share_pct should be roughly even across TiKV nodes.
SELECT
  STORE_ID,
  ADDRESS,
  REGION_COUNT,
  LEADER_COUNT,
  ROUND(LEADER_COUNT / NULLIF(REGION_COUNT, 0) * 100, 2) AS leader_pct_of_store,
  ROUND(
    LEADER_COUNT /
      (SELECT SUM(LEADER_COUNT) FROM information_schema.TIKV_STORE_STATUS) * 100,
    2
  ) AS leader_share_pct
FROM information_schema.TIKV_STORE_STATUS
ORDER BY leader_share_pct DESC;
```

Alert conditions:
- One store's `leader_share_pct` far exceeds the others → PD leader scheduling skew
- Check `schedule.leader-schedule-limit` and each store's `weight` / `labels` config
- Per-table leader drill-down is possible via `TIKV_REGION_STATUS` (one row per region — expensive on large clusters; always scope with `WHERE DB_NAME = '...' AND TABLE_NAME = '...'`)

### Step 8: TopSQL Diagnosis

Rank SQL by drain across the cluster using the statement summary. All latency
fields are in **nanoseconds** (`SUM_LATENCY / 1e9` → seconds, `/ 1e6` → ms).

**8a — Top 10 by total latency** (which SQL drains the most cluster time):

```sql
SELECT
  DIGEST_TEXT,
  SCHEMA_NAME,
  STMT_TYPE,
  EXEC_COUNT,
  ROUND(SUM_LATENCY / 1e9, 3) AS total_latency_s,
  ROUND(AVG_LATENCY / 1e6, 2) AS avg_latency_ms,
  ROUND(MAX_LATENCY / 1e6, 2) AS max_latency_ms
FROM information_schema.CLUSTER_STATEMENTS_SUMMARY
WHERE EXEC_COUNT > 0
ORDER BY SUM_LATENCY DESC
LIMIT 10;
```

**8b — Top 10 by execution count** (high-frequency queries):

```sql
SELECT
  DIGEST_TEXT,
  SCHEMA_NAME,
  EXEC_COUNT,
  ROUND(AVG_LATENCY / 1e6, 2) AS avg_latency_ms
FROM information_schema.CLUSTER_STATEMENTS_SUMMARY
WHERE EXEC_COUNT > 0
ORDER BY EXEC_COUNT DESC
LIMIT 10;
```

**8c — Top 10 by memory** (OOM risk):

```sql
SELECT
  DIGEST_TEXT,
  SCHEMA_NAME,
  EXEC_COUNT,
  SUM_MEMORY,
  ROUND(AVG_MEM / 1024 / 1024, 2) AS avg_mem_mb
FROM information_schema.CLUSTER_STATEMENTS_SUMMARY
WHERE EXEC_COUNT > 0
ORDER BY SUM_MEMORY DESC
LIMIT 10;
```

**8d — Diagnostic TOP 5** (the single biggest combined drain):

```sql
SELECT
  DIGEST_TEXT,
  SCHEMA_NAME,
  STMT_TYPE,
  EXEC_COUNT,
  ROUND(SUM_LATENCY / 1e9, 3) AS total_latency_s,
  ROUND(AVG_LATENCY / 1e6, 2) AS avg_latency_ms,
  ROUND(SUM_MEMORY / 1024 / 1024, 2) AS total_mem_mb
FROM information_schema.CLUSTER_STATEMENTS_SUMMARY
WHERE EXEC_COUNT > 0
ORDER BY SUM_LATENCY DESC
LIMIT 5;
```

**Empty result guard** — if the queries above return no rows, statement summary
is disabled, so recommend enabling it:

```sql
SELECT @@tidb_enable_stmt_summary AS enabled;   -- expected ON (default since v4.0)
-- SET GLOBAL tidb_enable_stmt_summary = ON;     -- requires SUPER privilege; recommend to DBA
```

## Scope & Limitations

This skill is a **read-only SQL inspection**. Some TiDB operational capabilities
are **not reachable via SQL** — they require the PD HTTP API, write access, or a
dedicated feature. For those, point the DBA to the right tool instead of
attempting them here:

| Capability | Why not in this skill | Where to do it |
|---|---|---|
| Region pre-splitting (`tidba split`) | Write operation via PD | `pd-ctl` / `SPLIT TABLE` DDL / `tidba split` |
| Runaway SQL throttle/kill (`tidba runaway`) | Resource-group write op | `RESOURCE GROUP` + runaway watches |
| Majority-DOWN region detection (`tidba region replica`) | Needs PD region-peer API | `pd-ctl` / `tidba region replica` |
| Native CPU-ranked TopSQL (`tidba topsql cpu`) | Needs TiDB TopSQL feature (`tidb_enable_top_sql`) | TopSQL / TiDB Dashboard |

The four enhanced steps above (hot region, leader skew, TopSQL latency/exec/memory)
cover the **read-only diagnosis** surface. This skill approximates "CPU drain"
via total latency, which is the standard proxy when the TopSQL feature is not
enabled.

## Output Template

```
🔍 TiDB Cluster Inspection Report
══════════════════════════════════
📋 Cluster Overview
  Topology: {tidb_count} TiDB + {pd_count} PD + {tikv_count} TiKV
  TiDB Version: {version}
  Inspection Time: {timestamp}

✅ Node Health
  | Role | Address | Version | Status | Uptime |
  |------|---------|---------|--------|--------|
  | TiDB | ...     | 4.0.11  | Up     | 187d   |
  | PD   | ...     | 4.0.11  | Up     | 327d   |
  | TiKV | ...     | 4.0.11  | Up     | 4d     |

⚠️ Slow Queries TOP 5
  | Duration | Scan Rows | SQL |
  |----------|-----------|-----|

⚡ TopSQL TOP 5 (by total latency)
  | SQL (digest) | Schema | Execs | Total Latency | Avg Latency |
  |--------------|--------|-------|---------------|-------------|

🔥 Hot Regions
  | DB | Table | Type | Flow Bytes |
  |----|-------|------|------------|

⚖️ Leader Skew (per TiKV store)
  | Store | Leader Share% | Note |
  |-------|---------------|------|

💾 TiKV Storage
  | Store | Capacity | Used | Usage% | Regions | Leaders |
  |-------|----------|------|--------|---------|---------|

⚙️ PD Config
  Leader Schedule: {enabled}
  Region Schedule: {enabled}

💡 Findings & Recommendations
  {Prioritized action items}
```

## Example Usage

**User**: "Inspect my TiDB cluster"

**AI Response**:
```
🔍 TiDB Cluster Inspection

Topology: 3 TiDB + 3 PD + 3 TiKV = 9 nodes
Version: v4.0.11 ✅ (consistent)

✅ All 9 nodes Up

🔥 Hot Regions: 5 found
  order_service.order_detail (read, 9.5MB flow)
  → Check index on order_detail

💾 TiKV Storage: 3 stores
  All < 50% usage ✅
  Leaders balanced ✅

💡 Recommendation: Investigate read hotspot on order_service
   order_detail table — consider adding composite index.
```

## Best Practices

### Inspection Schedule

| Frequency | Scope | Focus |
|-----------|-------|-------|
| Daily | Slow queries + hot regions | Performance |
| Weekly | Full 8-step inspection | Health check |
| Monthly | Storage trends + capacity | Planning |

### TiDB-Specific Tuning

```sql
-- Enable slow query log
SET GLOBAL tidb_enable_slow_log = ON;
SET GLOBAL tidb_slow_log_threshold = 200; -- 200ms

-- Hot region scatter (execute via pd-ctl)
-- pd-ctl scheduler add scatter-range {table_name}

-- Region merge for small tables
SET GLOBAL tidb_merge_partial_ddl = ON;
```

## Quick Reference

| Action | Query |
|--------|-------|
| Cluster info | `SELECT * FROM information_schema.cluster_info` |
| Slow queries | `SELECT * FROM information_schema.slow_query ORDER BY Query_time DESC` |
| Hot regions | `SELECT * FROM information_schema.TIDB_HOT_REGIONS` |
| TiKV stores | `SELECT * FROM information_schema.tikv_store_status` |
| PD config | `SHOW CONFIG WHERE TYPE='pd'` |
| TopSQL drain | `SELECT DIGEST_TEXT, EXEC_COUNT, SUM_LATENCY FROM information_schema.CLUSTER_STATEMENTS_SUMMARY ORDER BY SUM_LATENCY DESC LIMIT 10` |
| Table stats | `SHOW STATS_META WHERE table_name='...'` |

**Use this skill for systematic TiDB cluster health inspection across all components.**
