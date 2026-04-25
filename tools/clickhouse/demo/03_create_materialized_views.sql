-- ============================================================
-- Run on EACH node individually
-- Materialized Views: auto-sync raw -> actual within each shard
-- ============================================================

-- ---------- Node 1 (ch-1) ----------
CREATE MATERIALIZED VIEW homelab_cluster_shard_01.sensor_readings_sync
TO homelab_cluster_shard_01.sensor_readings_actual
AS SELECT * FROM homelab_cluster_shard_01.sensor_readings_raw;

CREATE MATERIALIZED VIEW homelab_cluster_shard_03.sensor_readings_sync
TO homelab_cluster_shard_03.sensor_readings_actual
AS SELECT * FROM homelab_cluster_shard_03.sensor_readings_raw;

-- ---------- Node 2 (ch-2) ----------
-- CREATE MATERIALIZED VIEW homelab_cluster_shard_02.sensor_readings_sync
-- TO homelab_cluster_shard_02.sensor_readings_actual
-- AS SELECT * FROM homelab_cluster_shard_02.sensor_readings_raw;
--
-- CREATE MATERIALIZED VIEW homelab_cluster_shard_01.sensor_readings_sync
-- TO homelab_cluster_shard_01.sensor_readings_actual
-- AS SELECT * FROM homelab_cluster_shard_01.sensor_readings_raw;

-- ---------- Node 3 (ch-3) ----------
-- CREATE MATERIALIZED VIEW homelab_cluster_shard_03.sensor_readings_sync
-- TO homelab_cluster_shard_03.sensor_readings_actual
-- AS SELECT * FROM homelab_cluster_shard_03.sensor_readings_raw;
--
-- CREATE MATERIALIZED VIEW homelab_cluster_shard_02.sensor_readings_sync
-- TO homelab_cluster_shard_02.sensor_readings_actual
-- AS SELECT * FROM homelab_cluster_shard_02.sensor_readings_raw;
