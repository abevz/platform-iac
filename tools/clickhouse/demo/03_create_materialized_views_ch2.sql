-- ============================================================
-- Run on ch-2 only
-- ch-2 hosts shard 02 and shard 01
-- ============================================================

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
