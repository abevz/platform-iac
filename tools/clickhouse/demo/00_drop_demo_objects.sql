-- ============================================================
-- Run on EACH node.
-- Drops only SQL objects for this demo. Keeper replica metadata is cleaned
-- separately by 00_cleanup_keeper_replicas.sql.
-- ============================================================

DROP TABLE IF EXISTS demo.sensor_readings_write;
DROP TABLE IF EXISTS demo.sensor_readings;
DROP DATABASE IF EXISTS demo;

DROP DATABASE IF EXISTS homelab_cluster_shard_01;
DROP DATABASE IF EXISTS homelab_cluster_shard_02;
DROP DATABASE IF EXISTS homelab_cluster_shard_03;
