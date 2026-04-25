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
- Distributed sharding uses `cityHash64(sensor_id)` so all versions of one
  sensor land on the same shard and can be deduplicated by ReplacingMergeTree

## Files

| File | Purpose |
|------|---------|
| `01_create_shard_databases_ch*.sql` | Create per-shard databases for one specific node |
| `02_create_local_tables_ch*.sql` | Create `raw` + `actual` local tables for one specific node |
| `03_create_materialized_views_ch*.sql` | Auto-sync raw -> actual for one specific node |
| `04_create_distributed.sql` | Two Distributed tables: `_write` (over raw) + `_read` (over actual) |
| `05_insert_test_data.sql` | Insert ~5.2M rows with 3 version levels via `_write` |
| `06_verify.sql` | Cluster topology, shard distribution, replication, MV sync |
| `07_benchmark_*.sql` | Insert/select benchmark and query-log report |

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

The cluster config must also map each logical shard to its shard database via
`default_database`, so Distributed tables can use an empty database argument:

| Logical shard | `default_database` |
|---------------|--------------------|
| `s1` | `homelab_cluster_shard_01` |
| `s2` | `homelab_cluster_shard_02` |
| `s3` | `homelab_cluster_shard_03` |

| Node | Local databases | Macro mapping |
|------|-----------------|---------------|
| `ch-1` | `homelab_cluster_shard_01`, `homelab_cluster_shard_03` | `{shard01}=s1`, `{shard02}=s3` |
| `ch-2` | `homelab_cluster_shard_02`, `homelab_cluster_shard_01` | `{shard01}=s2`, `{shard02}=s1` |
| `ch-3` | `homelab_cluster_shard_03`, `homelab_cluster_shard_02` | `{shard01}=s3`, `{shard02}=s2` |

## Usage

First apply the ClickHouse Ansible role so `remote_servers` contains the
per-shard `default_database` mapping. Then recreate the demo objects.

```bash
CH_CLIENT=(
  clickhouse-client
  --port 9440
  --secure
  --user admin
  --password "$(cat ~/.clickhouse_admin_password)"
  --accept-invalid-certificate
)

# 1. Create databases (run on each node individually)
"${CH_CLIENT[@]}" --host ch-1 < 01_create_shard_databases_ch1.sql
"${CH_CLIENT[@]}" --host ch-2 < 01_create_shard_databases_ch2.sql
"${CH_CLIENT[@]}" --host ch-3 < 01_create_shard_databases_ch3.sql

# 2. Create local tables (run on each node)
"${CH_CLIENT[@]}" --host ch-1 < 02_create_local_tables_ch1.sql
"${CH_CLIENT[@]}" --host ch-2 < 02_create_local_tables_ch2.sql
"${CH_CLIENT[@]}" --host ch-3 < 02_create_local_tables_ch3.sql

# 3. Create materialized views (run on each node)
"${CH_CLIENT[@]}" --host ch-1 < 03_create_materialized_views_ch1.sql
"${CH_CLIENT[@]}" --host ch-2 < 03_create_materialized_views_ch2.sql
"${CH_CLIENT[@]}" --host ch-3 < 03_create_materialized_views_ch3.sql

# 4. Create Distributed tables (run on each node where you want the demo DB)
"${CH_CLIENT[@]}" --host ch-1 < 04_create_distributed.sql
"${CH_CLIENT[@]}" --host ch-2 < 04_create_distributed.sql
"${CH_CLIENT[@]}" --host ch-3 < 04_create_distributed.sql

# 5. Insert test data (any node, once - writes through raw Distributed)
"${CH_CLIENT[@]}" --host ch-1 < 05_insert_test_data.sql

# 6. Verify from any node with demo Distributed tables
"${CH_CLIENT[@]}" --host ch-1 < 06_verify.sql
```

## Benchmark

SQL benchmark:

```bash
# Insert 1,000,000 benchmark rows.
"${CH_CLIENT[@]}" --host ch-1 \
  --query_id bench_insert_1m \
  < 07_benchmark_insert_1m.sql

SYSTEM_FLUSH="SYSTEM FLUSH DISTRIBUTED demo.sensor_readings_write"
"${CH_CLIENT[@]}" --host ch-1 --query "$SYSTEM_FLUSH"

# Select benchmark with visible result.
"${CH_CLIENT[@]}" --host ch-1 \
  --query_id bench_select_aggregate \
  < 07_benchmark_select_aggregate.sql

# Select benchmark with output discarded.
"${CH_CLIENT[@]}" --host ch-1 \
  --query_id bench_select_aggregate_null \
  < 07_benchmark_select_aggregate_null.sql

# Read elapsed time, rows, bytes and memory from system.query_log.
"${CH_CLIENT[@]}" --host ch-1 < 07_benchmark_report.sql
```

Latest measured result on this homelab:

| Query | Duration | Rows |
|-------|----------|------|
| `bench_insert_1m` | 75 ms | `written_rows=1,000,000` |
| `bench_select_aggregate` | 21 ms | `read_rows=1,000,000` |
| `bench_select_aggregate_null` | 31 ms | `read_rows=1,000,000` |

Approximate throughput:

| Operation | Throughput |
|-----------|------------|
| Insert | ~13.3M rows/sec |
| Select aggregate | ~47.6M rows/sec |
| Select with `FORMAT Null` | ~32.3M rows/sec |

Go parallel benchmark runner:

```bash
go run main.go \
  --host ch-1 \
  --workers 4 \
  --rows-per-worker 250000
```

The Go runner inserts benchmark rows in parallel, flushes the Distributed
queue, runs a simple aggregate read, and prints a query-log report.

Cleanup benchmark rows:

```bash
"${CH_CLIENT[@]}" --host ch-1 < 07_cleanup_benchmark_data_ch1.sql
"${CH_CLIENT[@]}" --host ch-2 < 07_cleanup_benchmark_data_ch2.sql
"${CH_CLIENT[@]}" --host ch-3 < 07_cleanup_benchmark_data_ch3.sql
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
CH_CLIENT=(
  clickhouse-client
  --port 9440
  --secure
  --user admin
  --password "$(cat ~/.clickhouse_admin_password)"
  --accept-invalid-certificate
)

for host in ch-1 ch-2 ch-3; do
  echo "=== $host ==="
  "${CH_CLIENT[@]}" --host "$host" \
    --query "SELECT database, table, zookeeper_path, replica_name, active_replicas, total_replicas FROM system.replicas WHERE table LIKE 'sensor_readings_%' ORDER BY database, table"
done
# Expect two raw replicas and two actual replicas per hosted shard.
```

## Engine Reference

| Engine | Removes old versions | Use case |
|--------|---------------------|----------|
| `ReplicatedMergeTree` | No | Audit trail, full history |
| `ReplicatedReplacingMergeTree` | Yes (background merge) | Current state, fast queries |
| `ReplicatedSummingMergeTree` | Merges values | Counters, rollups |
| `ReplicatedAggregatingMergeTree` | Merges states | Pre-aggregated reports |
| `Distributed` | N/A (router) | Query/write entry point |
