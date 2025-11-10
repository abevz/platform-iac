# Role: argocd_install

## Description

Deploys ArgoCD, a declarative GitOps continuous delivery tool for Kubernetes. This role installs ArgoCD using official manifests and provides initial admin credentials for UI access.

## Requirements

- Kubernetes cluster (1.24+)
- kubectl configured with cluster admin access
- Python package: `kubernetes` (for kubernetes.core collection)

## Role Variables

### defaults/main.yml

```yaml
# ArgoCD version to install
argocd_version: "v2.13.2"

# Namespace for ArgoCD installation
argocd_namespace: "argocd"

# Installation manifest URL
argocd_install_url: "https://raw.githubusercontent.com/argoproj/argo-cd/dc43124058130db9a747d141d86d7c2f4aac7bf9/manifests/install.yaml"

# State management (present or absent)
addon_state: present
```

### Override Variables

```yaml
# Use specific version
requested_version: "v2.12.0"

# Change namespace
argocd_namespace: "gitops"

# Remove ArgoCD
addon_state: absent
```

## Tags

| Tag | Purpose |
|-----|---------|
| `argocd` | All ArgoCD-related tasks |

## Dependencies

- Kubernetes cluster must be initialized
- `kubernetes.core` Ansible collection

## Example Playbook

### Basic Installation

```yaml
---
- name: Install ArgoCD
  hosts: k8s_master
  become: no
  roles:
    - argocd_install
```

### Install Specific Version

```yaml
---
- name: Install ArgoCD v2.12.0
  hosts: k8s_master
  become: no
  vars:
    requested_version: "v2.12.0"
  roles:
    - argocd_install
```

### Uninstall ArgoCD

```yaml
---
- name: Remove ArgoCD
  hosts: k8s_master
  become: no
  vars:
    addon_state: absent
  roles:
    - argocd_install
```

### Custom Namespace

```yaml
---
- name: Install ArgoCD in GitOps namespace
  hosts: k8s_master
  become: no
  vars:
    argocd_namespace: "gitops"
  roles:
    - argocd_install
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Set Target Version              │
│ (requested_version or default)  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create/Delete Namespace         │
│ kubectl create ns argocd        │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Apply/Delete ArgoCD Manifest    │
│ kubectl apply -f <url>          │
└────────────┬────────────────────┘
             │
             ▼ (if addon_state == present)
┌─────────────────────────────────┐
│ Wait for ArgoCD Server Ready    │
│ kubectl wait --for=condition... │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Retrieve Admin Password         │
│ from argocd-initial-admin-secret│
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Verify Running Pods             │
│ kubectl get pods -n argocd      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Display Results                 │
│ - State (present/absent)        │
│ - Version                       │
│ - Admin password (if installed) │
└─────────────────────────────────┘
```

## Post-Installation Steps

### 1. Access ArgoCD UI

#### Port Forward Method

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access at: https://localhost:8080

#### Ingress Method

Create Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
```

### 2. Login with Admin Credentials

```bash
# Get initial password (also displayed in Ansible output)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Login via CLI
argocd login <ARGOCD_SERVER> --username admin --password <password>
```

### 3. Change Admin Password

```bash
argocd account update-password
```

### 4. Delete Initial Secret (Security Best Practice)

```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

## ArgoCD Components

This role deploys the following components:

| Component | Purpose | Type |
|-----------|---------|------|
| argocd-server | Web UI and API server | Deployment |
| argocd-repo-server | Repository service for Git interactions | Deployment |
| argocd-application-controller | Monitors applications and syncs state | StatefulSet |
| argocd-dex-server | SSO/OIDC authentication | Deployment |
| argocd-redis | Cache for application state | Deployment |
| argocd-applicationset-controller | Multi-cluster application generation | Deployment |
| argocd-notifications-controller | Event notifications | Deployment |

## Configuration Files

### Verify Installation

```bash
# Check all ArgoCD pods
kubectl get pods -n argocd

# Check services
kubectl get svc -n argocd

# Check ArgoCD version
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].spec.containers[0].image}'
```

## Usage Examples

### Deploy Application via ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/example/my-app.git
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Apply with:

```bash
kubectl apply -f application.yaml
```

### Create ArgoCD Project

```bash
argocd proj create my-project \
  --description "My Project" \
  --dest https://kubernetes.default.svc,my-namespace \
  --src https://github.com/example/*
```

## Troubleshooting

### Issue: Pods Not Starting

**Symptom**: ArgoCD pods stuck in Pending or CrashLoopBackOff

**Solution**:

```bash
# Check pod events
kubectl describe pod -n argocd <pod-name>

# Check logs
kubectl logs -n argocd <pod-name>

# Verify resource availability
kubectl top nodes
kubectl describe nodes
```

### Issue: Cannot Access UI

**Symptom**: Port-forward works but UI doesn't load

**Solution**:

```bash
# Check service
kubectl get svc argocd-server -n argocd

# Verify TLS certificate
kubectl get secret argocd-server-tls -n argocd

# Check server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Issue: Initial Admin Secret Not Found

**Symptom**: Secret `argocd-initial-admin-secret` doesn't exist

**Cause**: Secret is deleted after first password change (security feature)

**Solution**: Reset admin password:

```bash
# Get current admin password hash
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.admin\.password}' | base64 -d

# Or reset to new password
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "'$(htpasswd -nbBC 10 "" <new-password> | tr -d ':\n' | sed 's/$2y/$2a/')'"}}'
```

### Issue: Application Sync Fails

**Symptom**: ArgoCD cannot sync application from Git

**Solution**:

```bash
# Check repo-server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server

# Verify Git credentials (if private repo)
kubectl get secret -n argocd

# Test Git connectivity
kubectl exec -n argocd <repo-server-pod> -- git ls-remote <repo-url>
```

## Security Considerations

### RBAC Configuration

ArgoCD creates these service accounts:
- `argocd-server`
- `argocd-application-controller`
- `argocd-dex-server`

Ensure proper RBAC policies are configured for your cluster.

### Network Policies

Recommended NetworkPolicy for ArgoCD:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-network-policy
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: argocd
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector: {}
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: argocd-redis
```

### SSO Integration

Configure SSO for production environments:

```bash
kubectl edit configmap argocd-cm -n argocd
```

Example with GitHub:

```yaml
data:
  url: https://argocd.example.com
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: $GITHUB_CLIENT_ID
        clientSecret: $GITHUB_CLIENT_SECRET
        orgs:
        - name: your-org
```

## High Availability

For production, use HA mode with replicas:

```bash
# Scale components
kubectl scale deployment argocd-server -n argocd --replicas=3
kubectl scale deployment argocd-repo-server -n argocd --replicas=3
kubectl scale statefulset argocd-application-controller -n argocd --replicas=3
```

Consider using Redis HA mode and external database (PostgreSQL) for production.

## Monitoring

### Prometheus Metrics

ArgoCD exposes metrics on port 8082:

```yaml
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: argocd
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-server-metrics
  endpoints:
  - port: metrics
```

### Useful Metrics

- `argocd_app_sync_total`: Total number of syncs
- `argocd_app_health_status`: Application health status
- `argocd_cluster_api_resource_objects`: Objects per cluster

## Related Roles

- **k8s_cluster_manager**: Must run first to create cluster
- **ingress_nginx_install**: For exposing ArgoCD UI
- **cert_manager_install**: For TLS certificate automation

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD GitHub](https://github.com/argoproj/argo-cd)
- [GitOps Principles](https://opengitops.dev/)

## Changelog

- **2025-11**: Updated to ArgoCD v2.13.2
- **2024**: Initial role creation

## Author

Platform Infrastructure Team

## License

Internal use only.
