-- ============================================================
-- Run on EACH node individually
-- Creates two tables per shard: raw (all versions) + actual (latest)
-- {shard01}/{shard02} and {replica01}/{replica02} resolve from macros
-- ============================================================

-- ---------- Node 1 (ch-1) | primary shard s1, secondary shard s3 ----------
-- Primary shard 1: raw table (audit trail)
CREATE TABLE homelab_cluster_shard_01.sensor_readings_raw
(
    sensor_id  UInt32,
    dt         Date,
    ts         DateTime,
    value      Float64,
    version    UInt32,
    inserted_at DateTime DEFAULT now()
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{cluster}/{shard01}/sensor_readings_raw',
    '{replica01}'
)
PARTITION BY toYYYYMM(dt)
ORDER BY (sensor_id, dt, ts, version)
SETTINGS index_granularity = 8192;

-- Primary shard 1: actual table (latest version, fast queries)
CREATE TABLE homelab_cluster_shard_01.sensor_readings_actual
(
    sensor_id  UInt32,
    dt         Date,
    ts         DateTime,
    value      Float64,
    version    UInt32,
    updated_at DateTime DEFAULT now()
)
ENGINE = ReplicatedReplacingMergeTree(
    '/clickhouse/tables/{cluster}/{shard01}/sensor_readings_actual',
    '{replica01}',
    version
)
PARTITION BY toYYYYMM(dt)
ORDER BY (sensor_id, dt, ts)
SETTINGS index_granularity = 8192;

-- Secondary shard 3: raw table
CREATE TABLE homelab_cluster_shard_03.sensor_readings_raw
(
    sensor_id  UInt32,
    dt         Date,
    ts         DateTime,
    value      Float64,
    version    UInt32,
    inserted_at DateTime DEFAULT now()
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{cluster}/{shard02}/sensor_readings_raw',
    '{replica02}'
)
PARTITION BY toYYYYMM(dt)
ORDER BY (sensor_id, dt, ts, version)
SETTINGS index_granularity = 8192;

-- Secondary shard 3: actual table
CREATE TABLE homelab_cluster_shard_03.sensor_readings_actual
(
    sensor_id  UInt32,
    dt         Date,
    ts         DateTime,
    value      Float64,
    version    UInt32,
    updated_at DateTime DEFAULT now()
)
ENGINE = ReplicatedReplacingMergeTree(
    '/clickhouse/tables/{cluster}/{shard02}/sensor_readings_actual',
    '{replica02}',
    version
)
PARTITION BY toYYYYMM(dt)
ORDER BY (sensor_id, dt, ts)
SETTINGS index_granularity = 8192;

-- ---------- Node 2 (ch-2) | primary shard s2, secondary shard s1 ----------
-- CREATE TABLE homelab_cluster_shard_02.sensor_readings_raw  ... /{cluster}/{shard01}/...  '{replica01}'
-- CREATE TABLE homelab_cluster_shard_02.sensor_readings_actual ... /{cluster}/{shard01}/...  '{replica01}'
-- CREATE TABLE homelab_cluster_shard_01.sensor_readings_raw  ... /{cluster}/{shard02}/...  '{replica02}'
-- CREATE TABLE homelab_cluster_shard_01.sensor_readings_actual ... /{cluster}/{shard02}/...  '{replica02}'

-- ---------- Node 3 (ch-3) | primary shard s3, secondary shard s2 ----------
-- CREATE TABLE homelab_cluster_shard_03.sensor_readings_raw  ... /{cluster}/{shard01}/...  '{replica01}'
-- CREATE TABLE homelab_cluster_shard_03.sensor_readings_actual ... /{cluster}/{shard01}/...  '{replica01}'
-- CREATE TABLE homelab_cluster_shard_02.sensor_readings_raw  ... /{cluster}/{shard02}/...  '{replica02}'
-- CREATE TABLE homelab_cluster_shard_02.sensor_readings_actual ... /{cluster}/{shard02}/...  '{replica02}'
