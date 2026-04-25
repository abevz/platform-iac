-- ============================================================
-- Run after benchmark queries.
-- Reports timing and row/byte counters from system.query_log.
-- ============================================================

SYSTEM FLUSH LOGS;

SELECT
    query_id,
    query_duration_ms,
    read_rows,
    read_bytes,
    written_rows,
    written_bytes,
    memory_usage
FROM system.query_log
WHERE query_id IN (
    'bench_insert_1m',
    'bench_select_aggregate',
    'bench_select_aggregate_null'
)
  AND type = 'QueryFinish'
ORDER BY event_time_microseconds;
