# Role: ingress_nginx_install

## Description

Installs and configures **NGINX Ingress Controller** - the most popular Kubernetes Ingress controller for routing external HTTP/HTTPS traffic to services. Provides advanced load balancing, SSL/TLS termination, name-based virtual hosting, and path-based routing for bare-metal Kubernetes clusters.

## Requirements

- Running Kubernetes cluster (v1.22+)
- kubectl configured on control plane
- Root or sudo access on control plane node
- **MetalLB** or cloud LoadBalancer (for LoadBalancer-type Service)
- Certificate management (cert-manager recommended for TLS)

## Role Variables

### defaults/main.yml

```yaml
# NGINX Ingress Controller version
ingress_nginx_version: "v1.12.0"

# Deploy manifest URL (baremetal configuration)
ingress_nginx_deploy_url: "https://raw.githubusercontent.com/kubernetes/ingress-nginx/8ee4384271e081578bb8f08eccf2f3b5a78ada25/deploy/static/provider/baremetal/deploy.yaml"
```

### Override Variables

```yaml
# Custom version
ingress_nginx_version: "v1.11.0"

# Custom deploy URL (e.g., for cloud provider)
ingress_nginx_deploy_url: "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `ingress_nginx` | All NGINX Ingress tasks |

## Dependencies

- **k8s_cluster_manager**: Cluster must be initialized
- **metallb_install**: Recommended for LoadBalancer IP assignment (bare-metal)
- **cert_manager_install**: Recommended for automatic TLS certificate management

## Example Playbook

### Basic Installation

```yaml
---
- name: Install NGINX Ingress Controller
  hosts: k8s_master
  become: yes
  roles:
    - ingress_nginx_install
```

### Complete Stack with MetalLB

```yaml
---
- name: Deploy Ingress Stack
  hosts: k8s_master
  become: yes
  roles:
    - metallb_install          # LoadBalancer support
    - ingress_nginx_install    # Ingress controller
    - cert_manager_install     # TLS automation
```

### Declarative Install/Uninstall

```yaml
# Install NGINX Ingress
- hosts: k8s_master
  become: yes
  roles:
    - role: ingress_nginx_install
      vars:
        addon_state: present

# Uninstall NGINX Ingress
- hosts: k8s_master
  become: yes
  roles:
    - role: ingress_nginx_install
      vars:
        addon_state: absent
```

### Custom Version

```yaml
---
- name: Install Specific Ingress Version
  hosts: k8s_master
  become: yes
  vars:
    requested_version: "v1.11.0"
  roles:
    - ingress_nginx_install
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
│ Check Current Version           │
│ kubectl get pods -n ingress-    │
│ nginx -o jsonpath='..image'     │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Apply NGINX Ingress Manifest    │
│ (baremetal configuration)       │
│ - Namespace: ingress-nginx      │
│ - Deployment: controller        │
│ - Service: LoadBalancer         │
│ - RBAC, ConfigMap, etc.         │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Wait for Pods Ready             │
│ kubectl wait --for=condition=   │
│ ready pod -l app.kubernetes.io/ │
│ name=ingress-nginx              │
│ --timeout=300s                  │
└─────────────────────────────────┘
```

## What Gets Installed

### Kubernetes Resources

**Namespace:**
- `ingress-nginx`

**Deployments:**
- `ingress-nginx-controller`
  - NGINX reverse proxy and Kubernetes Ingress controller
  - Watches Ingress resources and configures NGINX
  - 1+ replicas (configurable for HA)

**Services:**
- `ingress-nginx-controller` (LoadBalancer type)
  - External access to Ingress controller
  - Ports: 80 (HTTP), 443 (HTTPS)
  - MetalLB assigns external IP (on bare-metal)

- `ingress-nginx-controller-admission` (ClusterIP)
  - Validating webhook for Ingress resources

**ConfigMap:**
- `ingress-nginx-controller`
  - NGINX configuration tunables
  - SSL settings, timeouts, buffer sizes, etc.

**ServiceAccount & RBAC:**
- `ingress-nginx` ServiceAccount
- ClusterRoles and ClusterRoleBindings for API access
- Role/RoleBindings for namespace-specific access

**Webhook:**
- ValidatingWebhookConfiguration
  - Validates Ingress manifests before admission

**Jobs:**
- `ingress-nginx-admission-create`
- `ingress-nginx-admission-patch`
  - Generate and patch webhook certificates

## Post-Installation Verification

### Check Ingress Controller Pods

```bash
# Verify pods are running
kubectl get pods -n ingress-nginx

# Expected output:
# NAME                                       READY   STATUS      RESTARTS   AGE
# ingress-nginx-admission-create-xxxxx       0/1     Completed   0          2m
# ingress-nginx-admission-patch-xxxxx        0/1     Completed   1          2m
# ingress-nginx-controller-xxxxxxxxxx-yyyyy  1/1     Running     0          2m
```

### Check LoadBalancer Service

```bash
kubectl get svc -n ingress-nginx

# Expected output:
# NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
# ingress-nginx-controller             LoadBalancer   10.96.45.123    <K8S-INGRESS-IP>    80:31234/TCP,443:32345/TCP
# ingress-nginx-controller-admission   ClusterIP      10.96.67.89     <none>          443/TCP
```

**Note**: `EXTERNAL-IP` should show IP from MetalLB pool (not `<pending>`).

### Check Controller Logs

```bash
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### Test Ingress Controller

```bash
# Access LoadBalancer IP (should return 404 - no backends yet)
curl http://<K8S-INGRESS-IP>

# Expected: "404 Not Found" from NGINX (means controller is working)
```

## Usage Examples

### Simple HTTP Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

Test:
```bash
curl -H "Host: app.example.com" http://<K8S-INGRESS-IP>/
```

### HTTPS Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - secure.example.com
    secretName: secure-tls
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 443
```

### Path-Based Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-based-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
  - host: multi.example.com
    http:
      paths:
      - path: /app1(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: app1-service
            port:
              number: 80
      - path: /app2(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: app2-service
            port:
              number: 80
```

### WebSocket Support

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: websocket-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
  - host: ws.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: websocket-service
            port:
              number: 8080
```

### Basic Authentication

```yaml
# Create auth secret
htpasswd -c auth myuser
kubectl create secret generic basic-auth --from-file=auth -n default

# Ingress with basic auth
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: auth-ingress
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
spec:
  ingressClassName: nginx
  rules:
  - host: protected.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: protected-service
            port:
              number: 80
```

### Rate Limiting

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rate-limited-ingress
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "10"
    nginx.ingress.kubernetes.io/limit-connections: "5"
spec:
  ingressClassName: nginx
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8000
```

## Annotations Reference

Common NGINX Ingress annotations:

| Annotation | Purpose | Example |
|------------|---------|---------|
| `nginx.ingress.kubernetes.io/rewrite-target` | URL rewriting | `/$2` |
| `nginx.ingress.kubernetes.io/ssl-redirect` | Force HTTPS redirect | `"true"` |
| `nginx.ingress.kubernetes.io/proxy-body-size` | Max request body size | `"100m"` |
| `nginx.ingress.kubernetes.io/proxy-read-timeout` | Backend read timeout | `"3600"` |
| `nginx.ingress.kubernetes.io/whitelist-source-range` | IP whitelist | `"10.0.0.0/8"` |
| `nginx.ingress.kubernetes.io/cors-allow-origin` | CORS headers | `"*"` |
| `cert-manager.io/cluster-issuer` | Auto TLS certs | `"letsencrypt-prod"` |

Full list: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/

## Troubleshooting

### Issue: Ingress controller pod not running

**Symptom**: Pod stuck in Pending/CrashLoopBackOff

**Solution**:
```bash
# Check pod events
kubectl describe pod -n ingress-nginx <pod-name>

# Check logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Common causes:
# 1. Insufficient resources
kubectl describe nodes | grep -A5 "Allocated resources"

# 2. Image pull issues
kubectl get events -n ingress-nginx | grep Pull

# 3. Admission webhook certificate issue
kubectl get validatingwebhookconfiguration
```

### Issue: LoadBalancer Service stuck in Pending

**Symptom**: `EXTERNAL-IP` shows `<pending>`

**Solution**:
```bash
# Verify MetalLB is installed and running
kubectl get pods -n metallb-system

# Check MetalLB IP pool
kubectl get ipaddresspool -n metallb-system

# Check service events
kubectl describe svc ingress-nginx-controller -n ingress-nginx

# Manual workaround: Use NodePort instead
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"NodePort"}}'
```

### Issue: 404 Not Found on valid hostname

**Symptom**: `curl -H "Host: app.example.com" http://<IP>/` returns 404

**Solution**:
```bash
# Verify Ingress resource exists
kubectl get ingress -A

# Check Ingress status
kubectl describe ingress <ingress-name>

# Verify ingressClassName is set
kubectl get ingress <ingress-name> -o yaml | grep ingressClassName

# Check backend service exists
kubectl get svc <backend-service-name>

# Check controller logs for errors
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep <hostname>
```

### Issue: SSL/TLS certificate not working

**Symptom**: HTTPS returns certificate errors

**Solution**:
```bash
# Verify TLS secret exists
kubectl get secret <tls-secret-name>

# Check secret content
kubectl get secret <tls-secret-name> -o yaml

# Verify cert-manager is installed (if using)
kubectl get pods -n cert-manager

# Check certificate resource
kubectl get certificate
kubectl describe certificate <cert-name>

# Test with openssl
openssl s_client -connect <hostname>:443 -servername <hostname>
```

### Issue: Backend service unreachable (502/503 errors)

**Symptom**: Ingress returns 502 Bad Gateway or 503 Service Unavailable

**Solution**:
```bash
# Verify backend pods are running
kubectl get pods -l app=<backend-app>

# Check pod readiness
kubectl get pods -o wide

# Test backend service directly
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://<service-name>:<port>

# Check controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep upstream

# Verify service selector matches pods
kubectl get svc <service-name> -o yaml
kubectl get pods --show-labels
```

### Issue: High memory/CPU usage

**Symptom**: Ingress controller consuming excessive resources

**Solution**:
```bash
# Check current resource usage
kubectl top pod -n ingress-nginx

# Increase resource limits
kubectl edit deployment ingress-nginx-controller -n ingress-nginx
# Update resources.limits.memory and resources.limits.cpu

# Scale horizontally
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=3

# Enable connection limiting in ConfigMap
kubectl edit configmap ingress-nginx-controller -n ingress-nginx
# Add: limit-conn-zone-variable: "$binary_remote_addr"
```

## High Availability

### Horizontal Scaling

```bash
# Scale to 3 replicas
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=3

# Verify distribution
kubectl get pods -n ingress-nginx -o wide
```

### Anti-Affinity

Add pod anti-affinity to spread replicas across nodes:

```yaml
kubectl edit deployment ingress-nginx-controller -n ingress-nginx

# Add under spec.template.spec:
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - ingress-nginx
        topologyKey: kubernetes.io/hostname
```

### Health Checks

NGINX Ingress exposes health endpoints:

- `/healthz` - Liveness probe
- `/metrics` - Prometheus metrics (port 10254)

## Performance Tuning

### ConfigMap Tuning

```yaml
kubectl edit configmap ingress-nginx-controller -n ingress-nginx

# Add performance optimizations:
data:
  worker-processes: "auto"
  worker-connections: "65535"
  keep-alive: "75"
  keep-alive-requests: "1000"
  upstream-keepalive-connections: "320"
  proxy-buffer-size: "16k"
  proxy-buffers-number: "8"
  client-body-buffer-size: "16k"
```

### Resource Limits

```yaml
kubectl edit deployment ingress-nginx-controller -n ingress-nginx

# Update resources:
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

### HPA (Horizontal Pod Autoscaler)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ingress-nginx-controller
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Monitoring

### Prometheus Metrics

NGINX Ingress exposes metrics on port 10254:

```yaml
# ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
  endpoints:
  - port: metrics
    interval: 30s
```

Key metrics:
- `nginx_ingress_controller_requests` - Request rate
- `nginx_ingress_controller_request_duration_seconds` - Latency
- `nginx_ingress_controller_response_size` - Response size
- `nginx_ingress_controller_ssl_expire_time_seconds` - Cert expiry

### Grafana Dashboard

Import NGINX Ingress dashboard:
- Dashboard ID: 9614
- URL: https://grafana.com/grafana/dashboards/9614

### Logs

```bash
# Follow controller logs
kubectl logs -f -n ingress-nginx deployment/ingress-nginx-controller

# JSON log format (easier parsing)
kubectl edit configmap ingress-nginx-controller -n ingress-nginx
# Add: log-format-escape-json: "true"
```

## Security

### SSL/TLS Configuration

```yaml
kubectl edit configmap ingress-nginx-controller -n ingress-nginx

# Harden SSL
data:
  ssl-protocols: "TLSv1.2 TLSv1.3"
  ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256"
  ssl-prefer-server-ciphers: "true"
  hsts: "true"
  hsts-max-age: "31536000"
```

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  egress:
  - to:
    - namespaceSelector: {}
```

### WAF (ModSecurity)

Enable Web Application Firewall:

```yaml
kubectl edit configmap ingress-nginx-controller -n ingress-nginx

# Enable ModSecurity
data:
  enable-modsecurity: "true"
  enable-owasp-modsecurity-crs: "true"
```

## Related Roles

- **metallb_install**: LoadBalancer IP assignment (required for bare-metal)
- **cert_manager_install**: Automatic TLS certificate management
- **traefik_install**: Alternative Ingress controller
- **istio_install**: Service mesh with advanced routing

## Related Playbooks

- `config/playbooks/install_ingress_nginx.yml`: Main Ingress deployment
- `config/playbooks/install_metallb.yml`: LoadBalancer setup
- `config/playbooks/install_cert_manager.yml`: TLS automation

## References

- [NGINX Ingress Controller Docs](https://kubernetes.github.io/ingress-nginx/)
- [Ingress Controller GitHub](https://github.com/kubernetes/ingress-nginx)
- [Annotations Reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Bare-Metal Considerations](https://kubernetes.github.io/ingress-nginx/deploy/baremetal/)

## Changelog

- **2025-11**: Initial role creation for platform-iac
- **2025-11**: Bare-metal configuration with MetalLB integration
- **2025-11**: Declarative addon_state support

## Author

Platform Infrastructure Team

## License

Internal use only.
