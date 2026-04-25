-- ============================================================
-- Run on ANY single node
-- Inserts go through demo.sensor_readings_write -> sensor_readings_raw
-- Materialized View auto-syncs raw -> actual on each shard
-- 1000 sensors × 15-min intervals × Jan 2025 = 2 976 000 rows
-- ============================================================

-- Version 1: initial data load
INSERT INTO demo.sensor_readings_write
SELECT
    number % 1000 AS sensor_id,
    toDate(ts) AS dt,
    ts,
    round(20 + (number % 1000) / 50.0 + rand() / 1e8, 2) AS value,
    1 AS version,
    now()
FROM (
    SELECT toDateTime('2025-01-01 00:00:00') + INTERVAL number*900 SECOND AS ts
    FROM numbers(2976000)
);

-- Version 2: update 500 sensors (simulated correction)
INSERT INTO demo.sensor_readings_write
SELECT
    number % 500 AS sensor_id,
    toDate(ts) AS dt,
    ts,
    round(21 + (number % 500) / 50.0 + rand() / 1e8, 2) AS value,
    2 AS version,
    now()
FROM (
    SELECT toDateTime('2025-01-01 00:00:00') + INTERVAL number*900 SECOND AS ts
    FROM numbers(1488000)
);

-- Version 3: update 300 sensors (further correction)
INSERT INTO demo.sensor_readings_write
SELECT
    number % 300 AS sensor_id,
    toDate(ts) AS dt,
    ts,
    round(22 + (number % 300) / 50.0 + rand() / 1e8, 2) AS value,
    3 AS version,
    now()
FROM (
    SELECT toDateTime('2025-01-01 00:00:00') + INTERVAL number*900 SECOND AS ts
    FROM numbers(744000)
);
