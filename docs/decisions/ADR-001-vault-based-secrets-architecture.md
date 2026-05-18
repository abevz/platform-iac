# ADR-001: Vault-based secrets architecture

## Status

Accepted — 2026-05-12

Updated — 2026-05-18: MVP uses manual Shamir unseal and
MinIO + encrypted Google Drive backups. Cloud KMS auto-unseal and
cloud S3 backups are optional hardening, not the first implementation.

## Context

`platform-iac` provisions virtual machines and base services on Proxmox
VE for a home lab. The lab hosts Kubernetes clusters, infrastructure
services, databases, and consumer workloads such as HCRO. As those
consumers grow, the platform needs a consistent runtime secrets layer:

- short-lived AWS credentials for cloud-burst workloads
- TLS certificates for in-cluster and ingress services
- database credentials
- webhook tokens and third-party API keys
- future SSH certificates and encryption-as-a-service

Current Day-0 secrets already live in SOPS under `config/secrets/`.
Those SOPS files are required before Vault exists: Proxmox provider
credentials, MinIO backend credentials, and Ansible extra vars. Vault
must not replace that bootstrap layer during the MVP.

The first concrete runtime consumer is `hybrid-cloud-optimizer` (HCRO).
HCRO's boundary is simple: the application reads Kubernetes Secrets;
the platform is responsible for how those Secrets are provisioned.

Operational constraint: the homelab is intentionally powered off at
night. Manual unseal after startup is acceptable and simpler than
running a cloud KMS dependency from day one.

## Decision

Adopt **HashiCorp Vault** or **OpenBao** as the central runtime secret
store, fronted by **External Secrets Operator (ESO)** as the Kubernetes
bridge.

MVP architecture:

- **Vault/OpenBao server** on a dedicated Proxmox VM, provisioned by
  `platform-iac`.
- **Raft integrated storage** on the Vault VM.
- **Manual Shamir unseal**, initialized as 5 shares / threshold 3.
- **SOPS remains the Day-0 bootstrap store** for Proxmox, MinIO,
  Ansible, and any values required before Vault exists.
- **ESO in Kubernetes** materializes selected Vault paths into
  Kubernetes Secrets.
- **Raft snapshots** are written on a timer, uploaded to MinIO, and
  copied offsite to Google Drive through `rclone crypt`.
- **Vault telemetry and audit logs** are integrated into the
  Kubernetes-native observability layer from ADR-002 when that layer is
  available.

Out of MVP:

- Cloud KMS auto-unseal.
- AWS S3 as the primary snapshot target.
- AWS dynamic credentials engine for HCRO.
- SSH, Transit, and Database engines.

Those remain valid hardening phases after the basic lifecycle,
backup, and restore drill work.

## Boundaries

SOPS owns Day-0/IaC bootstrap secrets:

- `config/secrets/proxmox/provider.sops.yml`
- `config/secrets/minio/backend.sops.yml`
- `config/secrets/ansible/extra_vars.sops.yml`
- local SOPS/age private key material outside the repository

Vault owns Day-2/runtime secrets:

- application API keys
- runtime database credentials
- future dynamic AWS credentials
- future TLS/PKI material
- future SSH certificates

ESO owns Kubernetes synchronization:

- `ExternalSecret` and `SecretStore`/`ClusterSecretStore` resources
- refresh behavior and Kubernetes events on sync failures

Consumer applications own only their consumption contract:

- read a normal Kubernetes Secret
- do not import Vault SDKs
- do not know whether the backing secret came from KV, dynamic AWS,
  database engine, or another Vault engine

## Consequences

Positive:

- **Low MVP complexity.** Manual unseal avoids cloud KMS bootstrap
  credentials and reduces moving parts.
- **On-prem first.** Vault/OpenBao runs in the Proxmox lab and serves
  non-AWS consumers such as Kubernetes workloads, databases, and future
  SSH access.
- **Runtime audit and rotation path.** SOPS remains for bootstrap, while
  Vault becomes the runtime system with audit logs, policies, leases,
  and dynamic engines.
- **Git-safe consumer workflow.** Applications commit `ExternalSecret`
  resources with no secret values; ESO materializes Kubernetes Secrets.
- **Recoverable backups.** MinIO provides quick local restore; encrypted
  Google Drive copies provide offsite disaster backup.

Trade-offs:

- **Manual startup step.** After the homelab starts, Vault stays sealed
  until the operator enters 3 unseal keys.
- **Unseal keys are critical.** Recovery requires both a usable snapshot
  and enough Shamir shares.
- **MinIO is not enough by itself.** If MinIO lives on the same lab
  hardware, it is quick restore only. Offsite encrypted Google Drive
  copy is part of the MVP backup policy.
- **Dynamic AWS credentials wait.** HCRO can start with static or
  manually managed runtime secrets and move to Vault AWS engine later.

## Alternatives Considered

### A. SOPS only for runtime secrets — rejected

SOPS is excellent for Day-0 secrets, but it has no runtime read audit,
lease revocation, dynamic credential issuance, or automatic consumer
refresh beyond redeploying manifests.

### B. AWS Secrets Manager or AWS-native IRSA — rejected as platform default

AWS-native options work well on EKS, but this lab is Proxmox-first and
has non-AWS consumers. They remain valid for AWS-native deployments, not
as the default platform contract.

### C. Cloud KMS auto-unseal — deferred

AWS KMS, GCP Cloud KMS, Azure Key Vault, or another seal backend can
remove the manual unseal step. That is useful for unattended startup,
but it adds cloud credentials and account dependencies. The current
homelab operating model accepts manual unseal.

### D. Transit auto-unseal — deferred

Vault-to-Vault Transit unseal is a good self-hosted pattern, but it
requires another trusted Vault/OpenBao instance. That is too much
operational overhead for the MVP.

### E. Selected — Vault/OpenBao + ESO + manual unseal

This gives the platform the right runtime secret boundary while keeping
the first implementation small enough to operate and restore.

## Implementation Roadmap

- **Phase A** — Vault/OpenBao VM with Raft storage and manual Shamir
  unseal.
- **Phase B** — Snapshot timer, MinIO upload, encrypted Google Drive
  offsite copy, and restore drill.
- **Phase C** — Kubernetes auth method and ESO with a sandbox
  `ExternalSecret`.
- **Phase D** — HCRO runtime secret contract through ESO.
- **Phase E** — Vault telemetry and audit log integration with
  observability from ADR-002.
- **Phase F** — PKI, AWS dynamic credentials, SSH, Transit, Database,
  or cloud KMS auto-unseal as needed.

## Forward References

- [Secrets architecture](../secrets-architecture.md) — operational
  how-to and runbook.
- [ADR-002](ADR-002-observability-stack-architecture.md) — monitoring
  and audit-log integration target.

## References

- HashiCorp Vault: https://developer.hashicorp.com/vault
- OpenBao: https://openbao.org/
- External Secrets Operator: https://external-secrets.io/
- rclone crypt: https://rclone.org/crypt/
