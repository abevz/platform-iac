-- ============================================================
-- Run on ANY node that has demo Distributed tables.
--
-- Use with:
--   clickhouse-client ... --query_id bench_select_aggregate < 07_benchmark_select_aggregate.sql
-- ============================================================

SELECT
    count() AS rows,
    uniqExact(sensor_id) AS sensors,
    avg(value) AS avg_value
FROM demo.sensor_readings
WHERE sensor_id >= 100000;
