# Role: vault_server

Installs a single-node Vault server for the homelab MVP.

## Operating Model

- Storage: integrated Raft on the Vault VM.
- Seal: manual Shamir unseal.
- Init: run manually with 5 shares and threshold 3.
- Backups: local Raft snapshots every 6 hours, with optional RustFS/S3 and
  rclone copy.

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

## RustFS Snapshot Upload

Local snapshots are created first. RustFS upload is enabled by SOPS-managed
Ansible variables:

```yaml
vault:
  backup:
    s3:
      enabled: true
      endpoint: "https://s3.minio.example.com"
      bucket: "vault-backups"
      prefix: "raft"
      create_bucket: true
      access_key: "vault-backup-access-key"
      secret_key: "vault-backup-secret-key"
```

Flat `vault_backup_*` keys still work for backward compatibility.

The role renders these values to `/etc/vault.d/snapshot-s3.env` with mode
`0640` and group `vault`. The snapshot service uses `rclone` with an ephemeral
S3 remote from environment variables, optionally creates the bucket, uploads the
snapshot, and checks that the object is visible in RustFS.

Verify after configuration:

```bash
sudo systemctl start vault-snapshot.service
sudo journalctl -u vault-snapshot.service -n 100 --no-pager
sudo bash -lc 'set -a; source /etc/vault.d/snapshot-s3.env; set +a; rclone --config /dev/null lsf vaults3:vault-backups/raft --files-only'
```

Verified on 2026-05-19:

```text
Uploaded snapshot to RustFS: vaults3:vault-backups/raft/vault-raft-20260519T060919Z.snap
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

## Encrypted Offsite Copy

RustFS is the fast local restore target. The offsite copy must be encrypted
before it leaves the homelab. Enable it with an rclone config stored in SOPS:

```yaml
vault:
  backup:
    rclone:
      enabled: true
      target: "vaultgdrivecrypt:raft"
      config: |
        [gdrive]
        type = drive
        scope = drive
        token = {"access_token":"example","token_type":"Bearer","refresh_token":"example","expiry":"2099-01-01T00:00:00Z"}

        [vaultgdrivecrypt]
        type = crypt
        remote = gdrive:99_Archive/Backups/Vault/vault-backups
        password = obscured-password
        password2 = obscured-salt
```

Flat `vault_backup_rclone_*` keys still work for backward compatibility.

The role renders the config to `/etc/vault.d/rclone.conf` with mode `0640`.
The snapshot service copies the same local snapshot to the configured encrypted
target and verifies that the encrypted object is listed there.

Verify after configuration:

```bash
sudo systemctl start vault-snapshot.service
sudo journalctl -u vault-snapshot.service -n 100 --no-pager
sudo rclone --config /etc/vault.d/rclone.conf lsf vaultgdrivecrypt:raft --files-only
```

Verified on 2026-05-19:

```text
Copied encrypted snapshot to rclone target: vaultgdrivecrypt:raft/vault-raft-20260519T062127Z.snap
```

Recovery requirement:

- To decrypt the offsite backup on another machine, you need the rclone
  configuration for both the Google Drive remote and the `vaultgdrivecrypt`
  crypt remote.
- In this project that config is stored in SOPS as `vault_backup_rclone_config`
  and rendered to `/etc/vault.d/rclone.conf`.
- Losing the crypt remote passwords makes the Google Drive objects useless even
  if the files are still present.
- Store the SOPS decryption key material and a recovery copy of the rclone crypt
  config outside the Vault VM.

Minimal recovery check on another machine:

```bash
rclone --config ./rclone.conf lsf vaultgdrivecrypt:raft --files-only
rclone --config ./rclone.conf copyto \
  vaultgdrivecrypt:raft/vault-raft-YYYYMMDDTHHMMSSZ.snap \
  ./vault-restore-test.snap
```
