-- ============================================================
-- Run on ANY node
-- ============================================================

-- 1. Cluster topology (expect 3 shards × 2 replicas = 6 entries)
SELECT cluster, shard_num, replica_num, host_name, port,
       default_database
FROM system.clusters
WHERE cluster = 'homelab_cluster'
ORDER BY shard_num, replica_num;

-- 2. Total rows via Distributed (read path → actual tables)
SELECT count() AS total FROM demo.sensor_readings;

-- 3. Per-shard raw rows (run on EACH node)
-- clickhouse-client --host ch-1 --port 9440 --secure
-- clickhouse-client --host ch-2 --port 9440 --secure
-- clickhouse-client --host ch-3 --port 9440 --secure
SELECT database, count() AS raw_rows
FROM homelab_cluster_shard_01.sensor_readings_raw
GROUP BY database
UNION ALL
SELECT database, count() FROM homelab_cluster_shard_03.sensor_readings_raw
GROUP BY database;

-- 4. Version distribution across cluster
SELECT version, count() AS rows, uniq(sensor_id) AS sensors
FROM demo.sensor_readings
GROUP BY version
ORDER BY version;

-- 5. Replication health
SELECT database, table, is_leader, total_replicas, active_replicas
FROM system.replicas
WHERE table LIKE '%sensor_readings%'
ORDER BY database, table;

-- 6. Get latest value via argMax (from raw — confirms all versions stored)
SELECT
    sensor_id, ts,
    argMax(value, version) AS current_value
FROM homelab_cluster_shard_01.sensor_readings_raw
WHERE sensor_id BETWEEN 1 AND 5
  AND dt = '2025-01-01'
GROUP BY sensor_id, ts
ORDER BY sensor_id, ts
LIMIT 20;

-- 7. Fast aggregate via actual table (Distributed read path)
SELECT
    toStartOfDay(ts) AS day,
    avg(value) AS avg_val,
    count() AS readings
FROM demo.sensor_readings
WHERE dt BETWEEN '2025-01-01' AND '2025-01-07'
GROUP BY day
ORDER BY day;

-- 8. Verify MV sync: raw vs actual row count (should be == after merge)
SELECT
    (SELECT count() FROM homelab_cluster_shard_01.sensor_readings_raw) AS raw_rows,
    (SELECT count() FROM homelab_cluster_shard_01.sensor_readings_actual) AS actual_rows,
    (SELECT count() FROM homelab_cluster_shard_03.sensor_readings_raw) AS raw_rows_s3,
    (SELECT count() FROM homelab_cluster_shard_03.sensor_readings_actual) AS actual_rows_s3;
