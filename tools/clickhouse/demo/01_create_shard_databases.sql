-- ============================================================
-- Run on EACH node individually (NOT ON CLUSTER)
-- Each node hosts 2 shard databases: primary + secondary
-- ============================================================

-- ---------- Node 1 (ch-1): shards 1 + 3 ----------
-- clickhouse-client --host ch-1 --port 9440 --secure < 01_create_shard_databases.sql
CREATE DATABASE IF NOT EXISTS homelab_cluster_shard_01;
CREATE DATABASE IF NOT EXISTS homelab_cluster_shard_03;

-- ---------- Node 2 (ch-2): shards 2 + 1 ----------
-- clickhouse-client --host ch-2 --port 9440 --secure
-- CREATE DATABASE IF NOT EXISTS homelab_cluster_shard_02;
-- CREATE DATABASE IF NOT EXISTS homelab_cluster_shard_01;

-- ---------- Node 3 (ch-3): shards 3 + 2 ----------
-- clickhouse-client --host ch-3 --port 9440 --secure
-- CREATE DATABASE IF NOT EXISTS homelab_cluster_shard_03;
-- CREATE DATABASE IF NOT EXISTS homelab_cluster_shard_02;
