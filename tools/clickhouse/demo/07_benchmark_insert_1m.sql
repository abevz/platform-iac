-- ============================================================
-- Run on ANY node that has demo Distributed tables.
-- Inserts 1,000,000 benchmark rows.
--
-- Use with:
--   clickhouse-client ... --query_id bench_insert_1m < 07_benchmark_insert_1m.sql
--
-- Uses sensor_id >= 100000 to avoid mixing with the demo data.
-- ============================================================

INSERT INTO demo.sensor_readings_write
SELECT
    100000 + (number % 100000) AS sensor_id,
    toDate(ts) AS dt,
    ts,
    round(42 + (number % 100000) / 1000.0 + rand() / 1e8, 2) AS value,
    1 AS version,
    now()
FROM (
    SELECT
        number,
        toDateTime('2025-02-01 00:00:00') + INTERVAL intDiv(number, 100000)*900 SECOND AS ts
    FROM numbers(1000000)
);
