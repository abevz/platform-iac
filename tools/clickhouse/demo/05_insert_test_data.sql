-- ============================================================
-- Run on ANY node that has demo.sensor_readings_write.
-- Inserts go through Distributed -> per-shard default_database
-- -> sensor_readings_raw.
--
-- Requires remote_servers replicas to define:
--   shard 1 -> homelab_cluster_shard_01
--   shard 2 -> homelab_cluster_shard_02
--   shard 3 -> homelab_cluster_shard_03
-- ============================================================

-- Version 1: initial data load
-- 1000 sensors x 2,976 15-minute intervals in Jan 2025 = 2,976,000 rows
INSERT INTO demo.sensor_readings_write
SELECT
    sensor_id,
    toDate(ts) AS dt,
    ts,
    round(20 + sensor_id / 50.0 + rand() / 1e8, 2) AS value,
    1 AS version,
    now()
FROM (
    SELECT
        number % 1000 AS sensor_id,
        toDateTime('2025-01-01 00:00:00') + INTERVAL intDiv(number, 1000)*900 SECOND AS ts
    FROM numbers(2976000)
);

-- Version 2: update 500 sensors (simulated correction)
-- 500 sensors x 2,976 intervals = 1,488,000 rows
INSERT INTO demo.sensor_readings_write
SELECT
    sensor_id,
    toDate(ts) AS dt,
    ts,
    round(21 + sensor_id / 50.0 + rand() / 1e8, 2) AS value,
    2 AS version,
    now()
FROM (
    SELECT
        number % 500 AS sensor_id,
        toDateTime('2025-01-01 00:00:00') + INTERVAL intDiv(number, 500)*900 SECOND AS ts
    FROM numbers(1488000)
);

-- Version 3: update 300 sensors (further correction)
-- 300 sensors x 2,976 intervals = 892,800 rows
INSERT INTO demo.sensor_readings_write
SELECT
    sensor_id,
    toDate(ts) AS dt,
    ts,
    round(22 + sensor_id / 50.0 + rand() / 1e8, 2) AS value,
    3 AS version,
    now()
FROM (
    SELECT
        number % 300 AS sensor_id,
        toDateTime('2025-01-01 00:00:00') + INTERVAL intDiv(number, 300)*900 SECOND AS ts
    FROM numbers(892800)
);
