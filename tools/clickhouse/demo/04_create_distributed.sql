-- ============================================================
-- Run on EACH node where you want to query/insert through demo tables.
-- Two Distributed tables:
--   demo.sensor_readings_write -> routes INSERTS to sensor_readings_raw
--   demo.sensor_readings       -> routes SELECTS to sensor_readings_actual
-- Empty '' database uses per-shard default_database from cluster config.
-- ============================================================

CREATE DATABASE IF NOT EXISTS demo;

-- Write path: inserts go to raw tables (ReplicatedMergeTree, all versions)
-- Use a deterministic sharding key so all versions for one sensor land
-- on the same shard and ReplacingMergeTree can deduplicate them.
CREATE TABLE IF NOT EXISTS demo.sensor_readings_write
(
    sensor_id   UInt32,
    dt          Date,
    ts          DateTime,
    value       Float64,
    version     UInt32,
    inserted_at DateTime DEFAULT now()
)
ENGINE = Distributed(
    'homelab_cluster',
    '',
    'sensor_readings_raw',
    cityHash64(sensor_id)
);

-- Read path: queries hit actual tables (ReplacingMergeTree, latest version)
CREATE TABLE IF NOT EXISTS demo.sensor_readings
(
    sensor_id  UInt32,
    dt         Date,
    ts         DateTime,
    value      Float64,
    version    UInt32,
    updated_at DateTime DEFAULT now()
)
ENGINE = Distributed(
    'homelab_cluster',
    '',
    'sensor_readings_actual',
    cityHash64(sensor_id)
);
