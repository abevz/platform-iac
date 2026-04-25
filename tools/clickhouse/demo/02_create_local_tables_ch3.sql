-- ============================================================
-- Run on ch-3 only
-- ch-3: primary shard 03, secondary shard 02
-- ============================================================

CREATE TABLE IF NOT EXISTS homelab_cluster_shard_03.sensor_readings_raw
(
    sensor_id   UInt32,
    dt          Date,
    ts          DateTime,
    value       Float64,
    version     UInt32,
    inserted_at DateTime DEFAULT now()
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{cluster}/{shard01}/sensor_readings_raw',
    '{replica01}'
)
PARTITION BY toYYYYMM(dt)
ORDER BY (sensor_id, dt, ts, version)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS homelab_cluster_shard_03.sensor_readings_actual
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

CREATE TABLE IF NOT EXISTS homelab_cluster_shard_02.sensor_readings_raw
(
    sensor_id   UInt32,
    dt          Date,
    ts          DateTime,
    value       Float64,
    version     UInt32,
    inserted_at DateTime DEFAULT now()
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{cluster}/{shard02}/sensor_readings_raw',
    '{replica02}'
)
PARTITION BY toYYYYMM(dt)
ORDER BY (sensor_id, dt, ts, version)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS homelab_cluster_shard_02.sensor_readings_actual
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
