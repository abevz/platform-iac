-- ============================================================
-- Run on ch-3 only
-- ch-3 hosts shard 03 and shard 02
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS homelab_cluster_shard_03.sensor_readings_sync
TO homelab_cluster_shard_03.sensor_readings_actual
AS
SELECT
    sensor_id,
    dt,
    ts,
    value,
    version,
    inserted_at AS updated_at
FROM homelab_cluster_shard_03.sensor_readings_raw;

CREATE MATERIALIZED VIEW IF NOT EXISTS homelab_cluster_shard_02.sensor_readings_sync
TO homelab_cluster_shard_02.sensor_readings_actual
AS
SELECT
    sensor_id,
    dt,
    ts,
    value,
    version,
    inserted_at AS updated_at
FROM homelab_cluster_shard_02.sensor_readings_raw;
