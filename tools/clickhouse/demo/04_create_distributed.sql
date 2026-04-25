-- ============================================================
-- Run on ANY single node
-- Two Distributed tables:
--   demo.sensor_readings_write -> routes INSERTS to sensor_readings_raw
--   demo.sensor_readings       -> routes SELECTS to sensor_readings_actual
-- Empty '' database uses default_database from cluster config
-- ============================================================

CREATE DATABASE IF NOT EXISTS demo;

-- Write path: inserts go to raw tables (ReplicatedMergeTree, all versions)
CREATE TABLE demo.sensor_readings_write
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
    rand()
);

-- Read path: queries hit actual tables (ReplacingMergeTree, latest version)
CREATE TABLE demo.sensor_readings
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
    rand()
);
