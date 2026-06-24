# Secrets Architecture

How-to companion for
[ADR-001](decisions/ADR-001-vault-based-secrets-architecture.md).
Covers the MVP Vault/OpenBao lifecycle for `platform-iac`: install,
manual unseal, ESO integration, backup, and restore.

## Overview

MVP shape:

```text
Proxmox VM "vault"
  Vault/OpenBao
  Raft storage
  manual Shamir unseal: 5 shares / threshold 3
  audit log
  Prometheus telemetry
  snapshot timer
        |
        +--> RustFS bucket "vault-backups"      # quick local restore
        |
        +--> rclone crypt -> Google Drive       # encrypted offsite copy

k8s-lab-01
  External Secrets Operator
  ClusterSecretStore / SecretStore
  ExternalSecret resources
  Kubernetes Secrets consumed by workloads
```

SOPS remains the Day-0 bootstrap store. Vault/OpenBao becomes the Day-2
runtime store.

## Current SOPS Boundary

Existing encrypted files:

- `config/secrets/proxmox/provider.sops.yml`: Proxmox API and SSH
  bootstrap credentials.
- `config/secrets/minio/backend.sops.yml`: RustFS/S3 endpoint and credentials
  for OpenTofu state. The path keeps the historical `minio` name for
  compatibility.
- `config/secrets/ansible/extra_vars.sops.yml`: current Ansible
  service secrets.

Do not duplicate one secret in both SOPS and Vault. During migration,
pick one authority per secret and move consumers one at a time.

MVP does **not** require AWS KMS, AWS access keys, or AWS S3.

## Bootstrap Sequence

### 1. Provision Vault VM

MVP component:

```text
infra/dev/vault/
config/playbooks/setup_vault.yml
config/roles/vault_server/
```

Wrapper path:

```bash
./tools/iac-wrapper.sh plan dev vault
./tools/iac-wrapper.sh apply dev vault
./tools/iac-wrapper.sh configure dev vault vault_servers
```

By default, Proxmox allocates the next available VMID and OpenTofu stores
that value in the RustFS-backed S3 state. To pin a specific VMID, copy
`infra/dev/vault/terraform.tfvars.example` to `terraform.tfvars` and set
`vm_id` explicitly before `apply`.

The OpenTofu component should create only the VM, networking, and
inventory output. Vault tokens, root tokens, recovery keys, and runtime
secrets must not enter Terraform/OpenTofu state.

### 2. Install Vault/OpenBao

The Ansible role should:

- install Vault or OpenBao
- write `/etc/vault.d/vault.hcl`
- enable Raft storage
- configure TLS
- enable telemetry
- prepare audit log path
- install snapshot service/timer
- start the service sealed

MVP config intentionally has no cloud `seal` stanza.

### 3. Initialize Vault/OpenBao

Run once on the Vault host:

```bash
export VAULT_ADDR=https://vault.<domain>:8200
vault operator init -key-shares=5 -key-threshold=3
```

Store the 5 unseal key shares offline. Do not store them in the repo,
Obsidian plain text, shell history, or the Vault VM. The root token is
temporary bootstrap material; revoke it after admin auth is configured.

### 4. Daily Startup

Because the homelab is powered off at night, manual unseal is part of
normal startup:

```bash
export VAULT_ADDR=https://vault.<domain>:8200
vault status
vault operator unseal
vault operator unseal
vault operator unseal
vault status
```

Expected final state:

```text
Initialized: true
Sealed: false
```

## External Secrets Operator

Install ESO into `k8s-lab-01` after Vault is reachable from the cluster.

Wrapper shape:

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 install_external_secrets.yml k8s_master
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 apply_external_secrets.yml k8s_master
```

Platform responsibilities:

- enable Vault Kubernetes auth
- create TokenReviewer service account
- configure Vault auth role bindings
- install ESO
- create `ClusterSecretStore` or namespace `SecretStore`
- seed one sandbox secret and prove ESO sync into a normal Kubernetes Secret

Current bootstrap path in this repo:

- `install_external_secrets.yml` installs ESO in namespace `external-secrets`
- `apply_external_secrets.yml` configures Vault auth and a sandbox
  `ClusterSecretStore` / `ExternalSecret`
- the first sandbox sync uses:
  - Vault role/policy: `eso-sandbox`
  - namespace: `sandbox-secrets`
  - `ClusterSecretStore`: `vault-backend`
  - `ExternalSecret`: `vault-sandbox-example`
  - Vault endpoint: `https://vault.example.com`

Runtime requirement:

- `apply_external_secrets.yml` needs `vault_eso_admin_token` because it writes
  Vault auth config, Vault policy, Vault role, and the initial sandbox secret.

## Monitoring Vault Agent Flow

The monitoring stack uses a different Vault integration path than ESO.

### Why use Vault here at all?

Short answer: mostly for runtime isolation and operational hygiene, not
because the homelab suddenly became a high-security environment.

What Vault improves here:

- Prometheus no longer needs a long-lived Kubernetes bearer token stored
  as a static file in the repo or hand-copied onto the monitoring VM.
- The monitoring VM gets a short-lived token on demand via AppRole and
  the Kubernetes secrets engine.
- The Kubernetes-side permissions stay attached to
  `monitoring/prometheus-external` in `platform-iac-gitops`, while the
  monitoring VM only gets the ability to ask Vault for that token.
- Token rotation becomes automatic at the Vault/Agent layer instead of
  a manual “replace the file and restart Prometheus” workflow.

What Vault does not magically solve:

- It does not make the homelab “secure by default”.
- If the monitoring VM is fully compromised, an attacker can still use
  the rendered short-lived token while it is valid.
- It adds complexity: AppRole, Vault policy, Kubernetes secrets engine,
  monitoring VM runtime config, and docs all have to line up.

Honest tradeoff for this homelab:

- Security improvement: moderate
- Operational complexity increase: high
- Main practical value: reproducible token issuance, smaller blast radius
  than a permanent static cluster token, and a closer-to-production flow
  for learning and future reuse

Simple architecture view:

```text
platform-iac-gitops
  -> creates monitoring/prometheus-external ServiceAccount + RBAC
  -> grants vault-auth the ability to mint SA tokens

platform-iac
  -> configures Vault Kubernetes secrets engine
  -> configures AppRole policy for monitoring VM
  -> configures Vault Agent and Prometheus on monitoring VM

monitoring VM
  Vault Agent -> AppRole login to Vault
              -> request kubernetes/creds/prometheus-external
              -> write short-lived token to local file
  Prometheus  -> reads local token file
              -> scrapes kube pod/endpoints discovery targets
```

In other words: `platform-iac-gitops` defines what the cluster allows,
and `platform-iac` defines how the external monitoring VM gets and uses
that access at runtime.

Split of responsibilities:

- `platform-iac-gitops` owns Kubernetes manifests for:
  - `monitoring/prometheus-external` ServiceAccount
  - `prometheus-external` ClusterRole and ClusterRoleBinding
  - `vault-token-creator` RBAC for the `vault-auth` service account
- `platform-iac` owns:
  - Vault Kubernetes secrets engine configuration
  - Vault AppRole policy and role for the monitoring VM
  - Vault Agent and Prometheus configuration on the monitoring VM

The live flow is:

```text
Prometheus on monitoring VM
  -> reads token file from /etc/prometheus/k8s-tokens/dev-k8s-lab-01.token
Vault Agent on monitoring VM
  -> authenticates with AppRole
  -> requests kubernetes/creds/prometheus-external in namespace monitoring
Vault Kubernetes secrets engine
  -> asks the cluster to mint a short-lived SA token
Kubernetes RBAC in platform-iac-gitops
  -> allows the generated token to watch pods/endpoints/services/nodes
```

Required Vault policy for the monitoring AppRole:

```hcl
path "kubernetes/creds/prometheus-external" {
  capabilities = ["create", "update"]
}
```

Required `vault_config` vars:

```yaml
vault_k8s_secrets_enabled: true
vault_k8s_secrets_path: "kubernetes"
vault_k8s_secrets_host: "https://10.10.10.200:6443"
vault_k8s_secrets_ca_cert: |
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----
vault_k8s_secrets_service_account_jwt: "<vault-auth-jwt>"
vault_k8s_secrets_roles:
  - name: prometheus-external
    allowed_namespaces: "monitoring"
    service_account_name: "prometheus-external"
    token_ttl: "1h"
    token_max_ttl: "4h"

vault_approle_enabled: true
vault_approle_roles:
  - name: monitoring-k8s-read
    policy: |
      path "kubernetes/creds/prometheus-external" {
        capabilities = ["create", "update"]
      }
```

Required monitoring vars:

```yaml
monitoring:
  vault_agent_enabled: true
  vault_agent_role_id: "<approle-role-id>"
  vault_agent_secret_id: "<approle-secret-id>"
  vault_agent_vault_addr: "https://vault.bevz.net"
```

Example:

```bash
ssh your-username@192.0.2.109
export VAULT_ADDR=http://127.0.0.1:8200
vault login
vault token create -ttl=1h

./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 apply_external_secrets.yml k8s_master \
  -e vault_eso_admin_token=<admin-or-root-token>
```

Important implementation notes from the first live bootstrap:

- the Vault Kubernetes auth role needs `audience` set to the cluster service
  account token audience;
- final steady-state config uses `https://vault.example.com` from inside the
  cluster;
- cluster DNS must resolve homelab service FQDNs through the lab DNS server;
- the Vault auth backend should use the control-plane IP for
  `kubernetes_host`, so Vault does not depend on resolving kubeconfig hostnames.

Troubleshooting notes:

- the first live debug pass temporarily used `http://192.0.2.109:8200` and
  temporary node-to-Vault firewall exceptions;
- those steps were not kept as the recommended model;
- `s3.minio.example.com` NXDOMAIN remains a separate lab DNS record problem, not
  an ESO or kubelet resolver contract issue.

### DNS Source Of Truth

New VM provisioning should take its resolver from the Ansible secrets file:

```yaml
dns:
  server:
    ip_address: "192.0.2.53"
```

`tools/iac-wrapper.sh` maps that value into OpenTofu as `vm_dns_server`. It
still falls back to `pihole.ip_address` for backward compatibility.

## ArgoCD App-Of-Apps

After ESO and Vault auth are working, ArgoCD can take over the GitOps-safe
Kubernetes resources.

Wrapper flow:

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 install_argocd.yml k8s_master
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 bootstrap_argocd_apps.yml k8s_master
```

Current manifest layout:

```text
kubernetes/gitops/k8s-lab-01/
  apps/
    argocd-config.yaml
    platform-project.yaml
    external-secrets-config.yaml
  argocd-config/
    argocd-cm-external-secrets-health.yaml
  external-secrets-config/
    namespace-sandbox-secrets.yaml
    clustersecretstore-vault-backend.yaml
    externalsecret-vault-sandbox-example.yaml
```

The initial scope is intentionally narrow:

- root app `platform-root`
- project `platform-lab`
- child app `argocd-config`
- child app `external-secrets-config`
- ArgoCD health customization for ESO CRDs
- Git-managed `ClusterSecretStore/vault-backend`
- Git-managed sandbox `ExternalSecret`

That gives a real app-of-apps entry point without trying to migrate every
cluster add-on into ArgoCD in one operation.

Consumer responsibilities:

- commit `ExternalSecret` resources
- consume normal Kubernetes Secrets
- avoid Vault SDK dependency in application code

## Adding a Runtime Secret

Example for a static KV secret:

```bash
vault kv put secret/hcro/aws-pricing \
  access_key_id="<value>" \
  secret_access_key="<value>"
```

Create a narrow policy:

```hcl
path "secret/data/hcro/aws-pricing" {
  capabilities = ["read"]
}
```

Bind it to the consumer service account:

```bash
vault write auth/kubernetes/role/hcro \
  bound_service_account_names=hcro-controller \
  bound_service_account_namespaces=hcro-system \
  policies=hcro-runtime \
  ttl=1h
```

ESO then syncs the Vault path into a Kubernetes Secret. The pod reads
the Kubernetes Secret only.

## Backup Policy

Vault snapshots contain all runtime secrets. Treat every snapshot as
highly sensitive.

MVP backup flow:

```text
vault operator raft snapshot save
  -> local protected directory on Vault VM
  -> RustFS bucket vault-backups
  -> rclone crypt remote backed by Google Drive
```

Security expectations:

- local snapshot directory is root/vault owned and not world-readable
- Google Drive copy goes through `rclone crypt`
- plain snapshots are not uploaded directly to Google Drive
- retention exists for both local and remote copies
- restore is tested, not assumed

Manual snapshot:

```bash
vault operator raft snapshot save /var/backups/vault/manual.snap
```

RustFS upload is implemented in `config/roles/vault_server` with `rclone`
using an environment-only S3 remote. The role writes the S3 settings to
`/etc/vault.d/snapshot-s3.env`, keeps that file readable only by `root:vault`,
and the snapshot service verifies that the uploaded object is visible in the
`vault-backups` bucket.

Current proven flow:

```text
/var/backups/vault/vault-raft-*.snap
  -> vaults3:vault-backups/raft/vault-raft-*.snap
```

Encrypted offsite copy is implemented with `rclone crypt`. Plain Vault snapshots
must not be copied directly to Google Drive. The current offsite target is:

```text
gdrive:99_Archive/Backups/Vault/vault-backups
  -> vaultgdrivecrypt:raft/vault-raft-*.snap
```

The snapshot service verifies the encrypted object through the crypt remote
after upload.

Recovery warning: the encrypted Google Drive files are not self-describing.
Restoring from another machine requires the rclone config for both the Google
Drive remote and the crypt remote. In this repo the recovery material is stored
as SOPS-managed `vault_backup_rclone_config`. If the crypt passwords are lost,
the offsite objects cannot be decrypted.

## Restore Drill

Quarterly drill:

1. Provision a fresh Vault VM.
2. Install Vault/OpenBao with the same role.
3. Copy a snapshot from RustFS or encrypted Google Drive restore path.
4. Restore:
   ```bash
   vault operator raft snapshot restore /path/to/snapshot.snap
   ```
5. Unseal manually with 3 shares.
6. Verify:
   ```bash
   vault status
   vault kv get secret/test
   ```
7. Record date, source snapshot, restore duration, and result.

If all unseal shares are lost, snapshot data is not recoverable. If all
offsite backups are lost, local lab disk failure can destroy the runtime
secret store.

## Observability

Vault telemetry and audit logs belong to the Kubernetes-native
observability layer described in
[ADR-002](decisions/ADR-002-observability-stack-architecture.md).

MVP checks:

- `vault status` shows initialized and unsealed after manual unseal
- `/v1/sys/metrics?format=prometheus` is scrapeable
- audit log is enabled and written
- snapshot timer last success is visible as a metric or alert input
- future `observability/consumers/vault` package adds rules and
  dashboards

## Optional Hardening

These are not MVP requirements:

- AWS KMS, GCP Cloud KMS, Azure Key Vault, or Transit auto-unseal
- AWS S3 snapshot target
- Vault AWS secrets engine for dynamic credentials
- Vault PKI engine for cert-manager
- SSH, Transit, and Database engines

Add them only after the manual-unseal lifecycle and restore drill are
working.

## Verification Checklist

- [ ] `./tools/iac-wrapper.sh plan dev vault` shows only the Vault VM and cloud-init snippet
- [ ] Vault VM is provisioned by `./tools/iac-wrapper.sh apply dev vault`
- [ ] Vault initializes with 5 shares / threshold 3
- [ ] Reboot leaves Vault sealed until manual unseal
- [ ] Manual unseal with 3 shares works
- [ ] ESO syncs one sandbox `ExternalSecret`
- [ ] Snapshot exists in RustFS
- [ ] Encrypted offsite copy exists in Google Drive via `rclone crypt`
- [ ] Restore drill completed and logged

## Drill Log

| Date | Operator | Source | Result | Duration | Notes |
|------|----------|--------|--------|----------|-------|
| _pending_ | _pending_ | _pending_ | _pending_ | _pending_ | initial run after MVP install |

## References

- [ADR-001](decisions/ADR-001-vault-based-secrets-architecture.md)
- [ADR-002](decisions/ADR-002-observability-stack-architecture.md)
- HashiCorp Vault: https://developer.hashicorp.com/vault
- OpenBao: https://openbao.org/
- External Secrets Operator: https://external-secrets.io/
- rclone crypt: https://rclone.org/crypt/
