-- ============================================================
-- Run on ch-3 only.
-- Removes benchmark rows inserted by 07_benchmark_insert_1m.sql.
-- ============================================================

ALTER TABLE homelab_cluster_shard_03.sensor_readings_raw
    DELETE WHERE sensor_id >= 100000;
ALTER TABLE homelab_cluster_shard_03.sensor_readings_actual
    DELETE WHERE sensor_id >= 100000;

ALTER TABLE homelab_cluster_shard_02.sensor_readings_raw
    DELETE WHERE sensor_id >= 100000;
ALTER TABLE homelab_cluster_shard_02.sensor_readings_actual
    DELETE WHERE sensor_id >= 100000;
