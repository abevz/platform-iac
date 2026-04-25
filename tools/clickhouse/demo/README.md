# ClickHouse Demo: Versioned Metrics on 3-Node Cluster (3 Shards × 2 Replicas)

## Topology

```
Node ch-1 (10.10.10.221): shard s1 (r1), shard s3 (r2)
Node ch-2 (10.10.10.222): shard s2 (r1), shard s1 (r2)
Node ch-3 (10.10.10.223): shard s3 (r1), shard s2 (r2)
```

Each shard lives in a **separate database**: `homelab_cluster_shard_01`, `_02`, `_03`.
This enables a single ClickHouse instance per node to host **two shards**
without table name conflicts. The Distributed table uses `default_database`
from the cluster config for automatic per-shard routing.

## Data Flow

```
INSERT → demo.sensor_readings_write (Distributed over raw)
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
  raw       raw       raw        ReplicatedMergeTree (all versions)
  sh_01     sh_02     sh_03
    │         │         │
    ▼         ▼         ▼
  MV        MV        MV         Materialized View (auto-copy on insert)
    │         │         │
    ▼         ▼         ▼
 actual    actual    actual       ReplacingMergeTree (latest only, fast)
    │         │         │
    └─────────┼─────────┘
              ▼
SELECT ← demo.sensor_readings (Distributed over actual)
```

- **`sensor_readings_raw`** — ReplicatedMergeTree, preserves ALL versions (audit trail)
- **`sensor_readings_actual`** — ReplicatedReplacingMergeTree, keeps only latest version (fast queries)
- **`demo.sensor_readings_write`** — Distributed over `raw`, WRITE path
- **`demo.sensor_readings`** — Distributed over `actual`, READ path (fast queries)
- Empty `''` database uses `default_database` from cluster config

## Files

| File | Purpose |
|------|---------|
| `01_create_shard_databases.sql` | Create per-shard databases on each node |
| `02_create_local_tables.sql` | Create `raw` + `actual` local tables per shard |
| `03_create_materialized_views.sql` | Auto-sync raw → actual (within each shard) |
| `04_create_distributed.sql` | Two Distributed tables: `_write` (over raw) + `_read` (over actual) |
| `05_insert_test_data.sql` | Insert ~5.2M rows with 3 version levels via `_write` |
| `06_verify.sql` | Cluster topology, shard distribution, replication, MV sync |

## Key Pattern: Per-Node Table Creation

Because each node serves **two shards**, tables must be created **individually per node**
(not `ON CLUSTER`) using the node's dual macros:

| Macro | Purpose |
|-------|---------|
| `{cluster}` | Cluster name (`homelab_cluster`) |
| `{shard01}` | Primary shard this node hosts |
| `{shard02}` | Secondary shard this node hosts |
| `{replica01}` | Replica ID for primary shard |
| `{replica02}` | Replica ID for secondary shard |

## Usage

```bash
# 1. Create databases (run on each node individually)
clickhouse-client --host ch-1 --port 9440 --secure < 01_create_shard_databases.sql
clickhouse-client --host ch-2 --port 9440 --secure < 01_create_shard_databases.sql
clickhouse-client --host ch-3 --port 9440 --secure < 01_create_shard_databases.sql

# 2. Create local tables (run on each node)
clickhouse-client --host ch-1 --port 9440 --secure < 02_create_local_tables.sql
clickhouse-client --host ch-2 --port 9440 --secure < 02_create_local_tables.sql
clickhouse-client --host ch-3 --port 9440 --secure < 02_create_local_tables.sql

# 3. Create materialized views (run on each node)
clickhouse-client --host ch-1 --port 9440 --secure < 03_create_materialized_views.sql
clickhouse-client --host ch-2 --port 9440 --secure < 03_create_materialized_views.sql
clickhouse-client --host ch-3 --port 9440 --secure < 03_create_materialized_views.sql

# 4. Create Distributed table (any node, once)
clickhouse-client --host ch-1 --port 9440 --secure < 04_create_distributed.sql

# 5. Insert test data (any node, once — writes through raw Distributed)
clickhouse-client --host ch-1 --port 9440 --secure < 05_insert_test_data.sql

# 6. Verify
clickhouse-client --host ch-1 --port 9440 --secure < 06_verify.sql
```

## Key Query Patterns

### Get latest value using argMax
```sql
SELECT ts, argMax(value, version) AS current_value
FROM sensor_readings_raw
WHERE sensor_id = 1 AND dt >= '2025-01-01'
GROUP BY ts;
```

### Get latest full row using LIMIT 1 BY
```sql
SELECT *
FROM sensor_readings_raw
WHERE sensor_id = 1
ORDER BY ts, version DESC
LIMIT 1 BY sensor_id, ts;
```

### Fast aggregation via actual table (Distributed)
```sql
SELECT toStartOfDay(ts) AS day, avg(value)
FROM demo.sensor_readings
WHERE dt BETWEEN '2025-01-01' AND '2025-01-07'
GROUP BY day;
```

## Replication Check

```bash
for host in ch-1 ch-2 ch-3; do
  echo "=== $host ==="
  clickhouse-client --host $host --port 9440 --secure \
    --query "SELECT database, count() FROM homelab_cluster_shard_01.sensor_readings_raw"
done
# Expect: shard_01 on ch-1 == shard_01 on ch-2
```

## Engine Reference

| Engine | Removes old versions | Use case |
|--------|---------------------|----------|
| `ReplicatedMergeTree` | No | Audit trail, full history |
| `ReplicatedReplacingMergeTree` | Yes (background merge) | Current state, fast queries |
| `ReplicatedSummingMergeTree` | Merges values | Counters, rollups |
| `ReplicatedAggregatingMergeTree` | Merges states | Pre-aggregated reports |
| `Distributed` | N/A (router) | Query/write entry point |
