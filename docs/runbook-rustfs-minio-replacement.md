# RustFS Binary Replacement Runbook

This runbook replaces the existing MinIO container with RustFS while preserving
the VM, S3 endpoint, bucket names, and data directory. It intentionally keeps
the `minio_servers` inventory group and `/srv/minio/*` paths for the first
migration so rollback stays simple.

## Scope

- Replace the Docker Compose service image with pinned `rustfs/rustfs`.
- Reuse the existing object data under `/srv/minio/data`.
- Keep existing S3 endpoints such as `s3.minio.example.com`.
- Include Terraform/OpenTofu state buckets in the same service cutover.
- Do not change Harbor. The repo-managed Harbor config currently uses local
  `data_volume: /data`, not S3.

## Pre-Cutover Checks

1. Confirm VM and Docker state:

   ```bash
   ssh <minio-host> 'hostname && sudo docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}"'
   ```

2. Confirm the data layout and current bucket names:

   ```bash
   ssh <minio-host> 'sudo find /srv/minio/data -maxdepth 2 -mindepth 1 -printf "%P\n" | sort'
   ```

3. Confirm VM snapshot and object-store backup freshness before stopping MinIO.

4. Capture a no-change plan for every OpenTofu component that uses the S3
   backend. Use `iac-wrapper.sh`, because it injects the backend endpoint,
   bucket, state key, and SOPS-derived credentials:

   ```bash
   ./tools/iac-wrapper.sh plan dev <component>
   ```

## Benchmark Before and After

Run the same benchmark once against MinIO before cutover and once against
RustFS after cutover. Use `iac-wrapper.sh` so endpoint and credentials are
loaded through the same SOPS-backed path as OpenTofu. The script writes
temporary objects to a dedicated bucket and removes its own prefix by default.

```bash
S3_BENCH_ITERATIONS=5 \
S3_BENCH_SIZES='4096 1048576 67108864' \
./tools/iac-wrapper.sh s3-benchmark dev minio | tee /tmp/s3-bench-before.csv
```

Repeat the same command after RustFS is running and write to
`/tmp/s3-bench-after.csv`.

If you intentionally need a host-local benchmark that bypasses the external
proxy path, override `S3_BENCH_ENDPOINT` while running the wrapper from an
environment that can reach that endpoint.

## Cutover

1. Stop writes from clients that depend on this endpoint, especially OpenTofu
   applies.

2. Stop the current MinIO Compose service:

   ```bash
   ssh <minio-host> 'cd /srv/minio && sudo docker compose down'
   ```

3. Apply the updated Ansible role:

   ```bash
   ./tools/iac-wrapper.sh configure dev minio
   ```

4. Verify RustFS is running:

   ```bash
   ssh <minio-host> 'sudo docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}"'
   ```

5. Verify S3 visibility through the same endpoint:

   ```bash
   mc alias set rustfs https://s3.minio.example.com '<access-key>' '<secret-key>'
   mc ls rustfs
   mc ls rustfs/vault-backups/raft
   ```

## State Validation

For each OpenTofu component, confirm the backend can be read through RustFS
before running any apply. Use the wrapper for the same reason as pre-cutover:
it supplies the S3 backend configuration and decrypted credentials.

```bash
./tools/iac-wrapper.sh plan dev <component>
```

Do not proceed with infrastructure changes until state reads and at least one
representative no-change plan succeed.

## Ownership Note

RustFS container images run as UID/GID `10001`. The role defaults
`rustfs_manage_data_ownership` to `true` and recursively updates
`/srv/minio/data`, `/srv/minio/config`, and `/srv/minio/logs` before starting
the container. Set it to `false` only if ownership is managed manually outside
Ansible.

## Rollback

1. Stop RustFS:

   ```bash
   ssh <minio-host> 'cd /srv/minio && sudo docker compose down'
   ```

2. Restore the previous MinIO Compose definition from git or VM snapshot.

3. Start MinIO again against the same `/srv/minio/data` directory.

4. If RustFS modified the data layout in a way MinIO cannot read, restore the
   pre-cutover VM snapshot or filesystem backup.

5. Re-run the state-read checks before allowing normal OpenTofu operations.
