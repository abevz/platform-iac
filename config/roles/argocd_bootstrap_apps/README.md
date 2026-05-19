# Role: argocd_bootstrap_apps

Bootstraps the first ArgoCD app-of-apps root for `k8s-lab-01`.

It applies:

1. an `AppProject` named `platform-lab`;
2. a root `Application` named `platform-root`;
3. GitOps source path `kubernetes/gitops/k8s-lab-01/apps`.

## Wrapper Usage

Install ArgoCD first:

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 install_argocd.yml k8s_master
```

Then bootstrap the root app:

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 bootstrap_argocd_apps.yml k8s_master
```

## Current GitOps Scope

The initial root app manages a safe, narrow slice:

- `AppProject/platform-lab`
- child app `argocd-config`
- child app `external-secrets-config`
- ArgoCD custom health checks for ESO CRDs
- `ClusterSecretStore/vault-backend`
- sandbox `ExternalSecret`

This keeps app-of-apps real without trying to re-adopt every cluster component
in one step.

## Verification

```bash
kubectl get applications -n argocd
kubectl get appproject -n argocd
kubectl get clustersecretstore vault-backend
kubectl get externalsecret -n sandbox-secrets
```
