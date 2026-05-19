# Role: external_secrets_install

## Description

Installs or removes External Secrets Operator (ESO) in Kubernetes using the
official Helm chart.

## Default Variables

```yaml
external_secrets_chart_version: "0.19.2"
external_secrets_namespace: "external-secrets"
external_secrets_release_name: "external-secrets"
external_secrets_chart_ref: "external-secrets/external-secrets"
external_secrets_helm_repo_url: "https://charts.external-secrets.io"
external_secrets_install_crds: true
external_secrets_wait_timeout: "5m"
```

## Wrapper Usage

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 install_external_secrets.yml k8s_master
```

## Verification

```bash
kubectl get pods -n external-secrets
kubectl get crd | grep external-secrets.io
```
