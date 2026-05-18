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
