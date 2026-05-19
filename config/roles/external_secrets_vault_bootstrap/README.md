# Role: external_secrets_vault_bootstrap

## Description

Bootstraps the first Vault to ESO integration path for `k8s-lab-01`.

The role:

1. creates the TokenReview service account and binding;
2. enables and configures Vault Kubernetes auth;
3. creates a narrow sandbox Vault policy and role;
4. applies a `ClusterSecretStore` and one sandbox `ExternalSecret`.

## Required Runtime Variable

```yaml
vault_eso_admin_token: ""
```

Without a valid admin or root token, the role cannot configure Vault.

Minimal operator flow on the Vault VM:

```bash
ssh abevz@10.10.10.109
export VAULT_ADDR=http://127.0.0.1:8200
vault login
vault token create -ttl=1h
```

## Wrapper Usage

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 apply_external_secrets.yml k8s_master \
  -e vault_eso_admin_token=<admin-or-root-token>
```

## Notes from the working bootstrap

- The Kubernetes auth role needs `audience` set to the Kubernetes service
  account token audience. In this lab that value is
  `https://kubernetes.default.svc.cluster.local`.
- Final steady-state path uses `https://vault.bevz.net`.
- Cluster DNS must resolve homelab service FQDNs through the lab DNS server.
- The Vault auth backend uses `https://<control-plane-ip>:6443` for
  `kubernetes_host` so Vault does not depend on resolving kubeconfig hostnames.

Troubleshooting history:

- During the first live debug pass, ESO was temporarily pointed at the internal
  Vault IP and Vault firewall was briefly opened to Kubernetes node IPs.
- Those were debug-only steps. The validated end state uses
  `https://vault.bevz.net`, and Vault firewall can stay restricted to the nginx
  proxy path.

## Verification

```bash
kubectl get clustersecretstore
kubectl get externalsecret -n sandbox-secrets
kubectl get secret -n sandbox-secrets vault-sandbox-example -o yaml
```
