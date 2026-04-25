-- ============================================================
-- Same select benchmark, but discards output for cleaner client timing.
--
-- Use with:
--   clickhouse-client ... --query_id bench_select_aggregate_null < 07_benchmark_select_aggregate_null.sql
-- ============================================================

SELECT
    count(),
    uniqExact(sensor_id),
    avg(value)
FROM demo.sensor_readings
WHERE sensor_id >= 100000
FORMAT Null;
