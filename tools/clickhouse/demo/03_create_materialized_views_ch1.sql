-- ============================================================
-- Run on ch-1 only
-- ch-1 hosts shard 01 and shard 03
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS homelab_cluster_shard_01.sensor_readings_sync
TO homelab_cluster_shard_01.sensor_readings_actual
AS
SELECT
    sensor_id,
    dt,
    ts,
    value,
    version,
    inserted_at AS updated_at
FROM homelab_cluster_shard_01.sensor_readings_raw;

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
