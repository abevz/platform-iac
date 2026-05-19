#!/bin/bash
# Configure Vault Kubernetes auth for ESO integration.
# Run this after Vault is initialized and unsealed.
# Run from a machine with VAULT_ADDR and VAULT_TOKEN set.
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://192.0.2.109:8200}"
K8S_API="${K8S_API:-https://192.0.2.200:6443}"

echo "Configuring Vault Kubernetes auth at ${VAULT_ADDR}..."

# Create long-lived reviewer SA token in kube-system (run once on the K8s cluster)
# kubectl apply -f vault-reviewer-sa.yaml
# REVIEWER_TOKEN=$(kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
# K8S_CA=$(kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.ca\.crt}' | base64 -d)

REVIEWER_TOKEN="${REVIEWER_TOKEN:?Set REVIEWER_TOKEN from vault-auth-token secret in kube-system}"
K8S_CA="${K8S_CA:-}"

# Configure Kubernetes auth method
vault write auth/kubernetes/config \
  kubernetes_host="${K8S_API}" \
  ${K8S_CA:+kubernetes_ca_cert="${K8S_CA}"} \
  token_reviewer_jwt="${REVIEWER_TOKEN}"

# ESO role — no audience constraint (ESO may use different audiences per version)
# bound_service_account_names/namespaces must match the ESO Helm chart values
vault write auth/kubernetes/role/eso-sandbox \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-sandbox \
  ttl=1h \
  alias_name_source=serviceaccount_uid

echo "Done. Verify with:"
echo "  vault read auth/kubernetes/config"
echo "  vault read auth/kubernetes/role/eso-sandbox"
