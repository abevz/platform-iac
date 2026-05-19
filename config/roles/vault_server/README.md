# Role: vault_server

Installs a single-node Vault server for the homelab MVP.

## Operating Model

- Storage: integrated Raft on the Vault VM.
- Seal: manual Shamir unseal.
- Init: run manually with 5 shares and threshold 3.
- Backups: local Raft snapshots every 6 hours, with optional MinIO and rclone copy.

## Bootstrap

```bash
./tools/iac-wrapper.sh apply dev vault
./tools/iac-wrapper.sh configure dev vault vault_servers
```

Proxmox allocates the VMID by default. To pin a VMID, copy
`infra/dev/vault/terraform.tfvars.example` to `terraform.tfvars` and set
`vm_id` before running `apply`.

Initialize once:

```bash
export VAULT_ADDR=http://vault:8200
vault operator init -key-shares=5 -key-threshold=3
```

Daily startup after powering on the lab:

```bash
export VAULT_ADDR=http://vault:8200
vault status
vault operator unseal
vault operator unseal
vault operator unseal
vault status
```

## Snapshot Token

The timer does not use the root token. After Vault is initialized and unsealed,
create a limited token for snapshots and place it on the VM:

```bash
vault policy write raft-snapshot - <<'POLICY'
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
POLICY

vault token create -policy=raft-snapshot -period=24h
```

Store only that token on the Vault VM:

```bash
sudo install -o root -g vault -m 0640 /dev/stdin /etc/vault.d/snapshot-token
```

Then paste the token and press `Ctrl-D`.

## MinIO Snapshot Upload

Local snapshots are created first. MinIO upload is enabled by SOPS-managed
Ansible variables:

```yaml
vault_backup_s3_enabled: true
vault_backup_s3_endpoint: "https://s3.minio.example.com"
vault_backup_s3_bucket: "vault-backups"
vault_backup_s3_prefix: "raft"
vault_backup_s3_create_bucket: true
vault_backup_s3_access_key: "vault-backup-access-key"
vault_backup_s3_secret_key: "vault-backup-secret-key"
```

The role renders these values to `/etc/vault.d/snapshot-s3.env` with mode
`0640` and group `vault`. The snapshot service uses `rclone` with an ephemeral
S3 remote from environment variables, optionally creates the bucket, uploads the
snapshot, and checks that the object is visible in MinIO.

Verify after configuration:

```bash
sudo systemctl start vault-snapshot.service
sudo journalctl -u vault-snapshot.service -n 100 --no-pager
sudo bash -lc 'set -a; source /etc/vault.d/snapshot-s3.env; set +a; rclone --config /dev/null lsf vaults3:vault-backups/raft --files-only'
```

Verified on 2026-05-19:

```text
Uploaded snapshot to MinIO: vaults3:vault-backups/raft/vault-raft-20260519T060919Z.snap
```

## Optional AWS CLI

Vault can store AWS credentials for other projects without AWS CLI being
installed on the Vault VM. AWS CLI is therefore not required for the snapshot
path. If the Vault VM later needs to run AWS operational commands directly,
enable the opt-in installer:

```yaml
vault_awscli_enabled: true
```

The role installs AWS CLI v2 from the official AWS installer because some
Debian/Ubuntu images do not provide an `awscli` package in the enabled apt
repositories.
