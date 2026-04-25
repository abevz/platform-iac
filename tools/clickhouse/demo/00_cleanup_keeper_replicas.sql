-- ============================================================
-- Run on ANY one ClickHouse node after dropping the demo databases.
-- Removes stale ClickHouse Keeper replica metadata for this demo.
--
-- Use only for this demo schema. It removes the expected replica names
-- under /clickhouse/tables/homelab_cluster/s*/sensor_readings_*.
-- ============================================================

SYSTEM DROP REPLICA 'ch-1_s1_r1' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s1/sensor_readings_raw';
SYSTEM DROP REPLICA 'ch-2_s1_r2' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s1/sensor_readings_raw';
SYSTEM DROP REPLICA 'ch-1_s1_r1' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s1/sensor_readings_actual';
SYSTEM DROP REPLICA 'ch-2_s1_r2' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s1/sensor_readings_actual';

SYSTEM DROP REPLICA 'ch-2_s2_r1' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s2/sensor_readings_raw';
SYSTEM DROP REPLICA 'ch-3_s2_r2' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s2/sensor_readings_raw';
SYSTEM DROP REPLICA 'ch-2_s2_r1' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s2/sensor_readings_actual';
SYSTEM DROP REPLICA 'ch-3_s2_r2' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s2/sensor_readings_actual';

SYSTEM DROP REPLICA 'ch-3_s3_r1' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s3/sensor_readings_raw';
SYSTEM DROP REPLICA 'ch-1_s3_r2' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s3/sensor_readings_raw';
SYSTEM DROP REPLICA 'ch-3_s3_r1' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s3/sensor_readings_actual';
SYSTEM DROP REPLICA 'ch-1_s3_r2' FROM ZKPATH '/clickhouse/tables/homelab_cluster/s3/sensor_readings_actual';
