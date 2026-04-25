-- ============================================================
-- Run on ANY node that has demo Distributed tables.
-- ============================================================

-- 1. Cluster topology and per-shard default databases.
SELECT
    cluster,
    shard_num,
    replica_num,
    host_name,
    port,
    default_database,
    is_local
FROM system.clusters
WHERE cluster = 'homelab_cluster'
ORDER BY shard_num, replica_num;

-- 2. Row counts via Distributed read/write paths.
-- actual_physical_rows can be higher than logical rows until background merges finish.
SELECT
    (SELECT count() FROM demo.sensor_readings_write) AS raw_rows,
    (SELECT count() FROM demo.sensor_readings) AS actual_physical_rows,
    (SELECT count() FROM demo.sensor_readings FINAL) AS actual_logical_rows;

-- 3. Raw row distribution across shards via Distributed write table.
SELECT
    _shard_num AS shard_num,
    count() AS raw_rows
FROM demo.sensor_readings_write
GROUP BY shard_num
ORDER BY shard_num;

-- 4. Physical version distribution before ReplacingMergeTree background merges.
SELECT version, count() AS rows, uniq(sensor_id) AS sensors
FROM demo.sensor_readings
GROUP BY version
ORDER BY version;

-- 4b. Logical latest-version distribution.
SELECT version, count() AS rows, uniq(sensor_id) AS sensors
FROM demo.sensor_readings FINAL
GROUP BY version
ORDER BY version;

-- 5. Replication health on the local node.
SELECT database, table, zookeeper_path, replica_name, active_replicas, total_replicas
FROM system.replicas
WHERE table LIKE 'sensor_readings_%'
ORDER BY database, table;

-- 6. Latest value via raw Distributed table, confirming all versions exist.
SELECT
    sensor_id,
    ts,
    argMax(value, version) AS current_value
FROM demo.sensor_readings_write
WHERE sensor_id BETWEEN 1 AND 5
  AND dt = '2025-01-01'
GROUP BY sensor_id, ts
ORDER BY sensor_id, ts
LIMIT 20;

-- 7. Fast aggregate via actual Distributed table.
-- Use FINAL when the demo must show logically deduplicated latest values immediately.
SELECT
    toStartOfDay(ts) AS day,
    avg(value) AS avg_val,
    count() AS readings
FROM demo.sensor_readings FINAL
WHERE dt BETWEEN '2025-01-01' AND '2025-01-07'
GROUP BY day
ORDER BY day;
