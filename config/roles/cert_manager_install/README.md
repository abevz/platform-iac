# Role: cert_manager_install

## Description

Installs and configures **cert-manager** - a Kubernetes add-on to automate the management and issuance of TLS certificates from various sources including Let's Encrypt, HashiCorp Vault, Venafi, and self-signed certificates. Provides automatic certificate renewal, ACME DNS-01 challenge support, and seamless integration with Ingress controllers.

## Requirements

- Running Kubernetes cluster (v1.22+)
- kubectl configured on control plane
- Helm 3 installed
- Root or sudo access on control plane node
- Cloudflare account with API token (for DNS-01 validation, optional)
- SOPS-encrypted secrets for sensitive data

## Role Variables

### defaults/main.yml

```yaml
# cert-manager version
cert_manager_version: "v1.16.2"

# Namespace for cert-manager components
cert_manager_namespace: "cert-manager"

# Let's Encrypt ACME server URL
letsencrypt_server: "https://acme-v02.api.letsencrypt.org/directory"
# Staging: https://acme-staging-v02.api.letsencrypt.org/directory
```

### Override Variables

```yaml
# Use staging server for testing
letsencrypt_server: "https://acme-staging-v02.api.letsencrypt.org/directory"

# Custom namespace
cert_manager_namespace: "certificate-management"

# Specific version
cert_manager_version: "v1.15.0"
```

### Required Secrets (via SOPS)

In `config/secrets/ansible/extra_vars.sops.yml`:

```yaml
cloudflare:
  email: "user@example.com"
  api_token: "YOUR_CLOUDFLARE_API_TOKEN"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `cert_manager` | All cert-manager tasks |

## Dependencies

- **Helm 3**: For chart installation
- **Cloudflare DNS**: For DNS-01 challenge (optional)
- **Ingress Controller**: For automatic certificate issuance (recommended)

## Example Playbook

### Basic Installation

```yaml
---
- name: Install cert-manager
  hosts: k8s_master
  become: yes
  roles:
    - cert_manager_install
```

### With Cloudflare Integration

```yaml
---
- name: Install cert-manager with Let's Encrypt
  hosts: k8s_master
  become: yes
  vars_files:
    - ../secrets/ansible/extra_vars.sops.yml
  roles:
    - cert_manager_install
```

### Declarative Install/Uninstall

```yaml
# Install cert-manager
- hosts: k8s_master
  become: yes
  roles:
    - role: cert_manager_install
      vars:
        addon_state: present

# Uninstall cert-manager
- hosts: k8s_master
  become: yes
  roles:
    - role: cert_manager_install
      vars:
        addon_state: absent
```

### Complete Stack

```yaml
---
- name: Deploy Full Ingress Stack with TLS
  hosts: k8s_master
  become: yes
  vars_files:
    - ../secrets/ansible/extra_vars.sops.yml
  roles:
    - metallb_install          # LoadBalancer support
    - cert_manager_install     # TLS automation
    - ingress_nginx_install    # Ingress controller
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
│ Add Jetstack Helm Repository    │
│ https://charts.jetstack.io      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install cert-manager via Helm   │
│ - Create namespace              │
│ - Install CRDs                  │
│ - Deploy controller pods        │
│ - Enable Gateway API support    │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create Cloudflare API Secret    │
│ (if cloudflare.api_token set)   │
│ apiVersion: v1                  │
│ kind: Secret                    │
│ stringData:                     │
│   api-token: <token>            │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create ClusterIssuer            │
│ (if cloudflare credentials set) │
│ apiVersion: cert-manager.io/v1  │
│ kind: ClusterIssuer             │
│ spec:                           │
│   acme:                         │
│     solvers:                    │
│     - dns01:                    │
│         cloudflare: ...         │
└─────────────────────────────────┘
```

## What Gets Installed

### Helm Chart Components

**Namespace:**
- `cert-manager` (or custom via `cert_manager_namespace`)

**Deployments:**
- `cert-manager` - Main controller
  - Watches Certificate, CertificateRequest resources
  - Issues and renews certificates automatically
  - Integrates with Ingress annotations

- `cert-manager-webhook` - Validating webhook
  - Validates cert-manager custom resources
  - Prevents invalid configurations

- `cert-manager-cainjector` - CA injector
  - Injects CA data into ValidatingWebhookConfiguration
  - Enables secure webhook communication

**Custom Resource Definitions (CRDs):**
- `Certificate` - Request a certificate
- `CertificateRequest` - Low-level certificate request
- `Issuer` - Namespace-scoped certificate issuer
- `ClusterIssuer` - Cluster-wide certificate issuer
- `Challenge` - ACME challenge tracking
- `Order` - ACME order tracking

**Service Accounts & RBAC:**
- Service accounts for controller, webhook, cainjector
- ClusterRoles and ClusterRoleBindings

**Additional Resources (created by role):**
- `cloudflare-api-token` Secret (if Cloudflare configured)
- `letsencrypt-cloudflare` ClusterIssuer (if Cloudflare configured)

## Post-Installation Verification

### Check cert-manager Pods

```bash
# Verify all pods are running
kubectl get pods -n cert-manager

# Expected output:
# NAME                                      READY   STATUS    RESTARTS   AGE
# cert-manager-xxxxxxxxxx-yyyyy             1/1     Running   0          2m
# cert-manager-cainjector-xxxxxxxxxx-yyyyy  1/1     Running   0          2m
# cert-manager-webhook-xxxxxxxxxx-yyyyy     1/1     Running   0          2m
```

### Check CRDs

```bash
# List cert-manager CRDs
kubectl get crd | grep cert-manager

# Expected:
# certificates.cert-manager.io
# certificaterequests.cert-manager.io
# challenges.acme.cert-manager.io
# clusterissuers.cert-manager.io
# issuers.cert-manager.io
# orders.acme.cert-manager.io
```

### Check ClusterIssuer

```bash
kubectl get clusterissuer

# Expected:
# NAME                      READY   AGE
# letsencrypt-cloudflare    True    2m
```

### Check Controller Logs

```bash
kubectl logs -n cert-manager deployment/cert-manager
```

### Test Certificate Issuance

```bash
# Create test certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
  - test.example.com
EOF

# Check certificate status
kubectl get certificate test-cert
kubectl describe certificate test-cert

# Verify secret created
kubectl get secret test-tls
```

## Usage Examples

### Automatic Certificate with Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls  # cert-manager creates this automatically
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

Result: cert-manager automatically:
1. Detects the Ingress annotation
2. Creates a Certificate resource
3. Initiates ACME DNS-01 challenge via Cloudflare
4. Issues the certificate
5. Stores it in `app-tls` Secret
6. Renews automatically before expiry

### Manual Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: manual-cert
  namespace: production
spec:
  secretName: manual-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
  - www.example.com
  - api.example.com
  duration: 2160h  # 90 days
  renewBefore: 360h  # Renew 15 days before expiry
```

### Wildcard Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
  namespace: default
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
  - "*.example.com"
  - "example.com"
```

### HTTP-01 Challenge (Alternative)

For HTTP-01 challenge (no DNS API required):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http01
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-http01
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Note**: HTTP-01 cannot issue wildcard certificates.

### Self-Signed Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-cert
spec:
  secretName: selfsigned-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - dev.internal.local
```

## Cloudflare Configuration

### Generate API Token

1. Log in to Cloudflare dashboard
2. Go to **My Profile → API Tokens**
3. Click **Create Token**
4. Use **Edit zone DNS** template
5. Configure:
   - **Permissions**: Zone → DNS → Edit
   - **Zone Resources**: Include → All zones (or specific zone)
6. Copy the generated token

### Store in SOPS

```bash
# Edit SOPS file
cd config/secrets/ansible
sops extra_vars.sops.yml

# Add credentials
cloudflare:
  email: "admin@example.com"
  api_token: "YOUR_TOKEN_HERE"
```

## ClusterIssuer vs Issuer

### ClusterIssuer (Cluster-wide)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # ...
```

- Works across **all namespaces**
- Single configuration for entire cluster
- Recommended for most use cases

### Issuer (Namespace-scoped)

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt-dev
  namespace: development
spec:
  acme:
    # ...
```

- Works only in **specific namespace**
- Isolated credentials per namespace
- Use for multi-tenant environments

## Troubleshooting

### Issue: cert-manager pods not running

**Symptom**: Pods stuck in Pending/CrashLoopBackOff

**Solution**:
```bash
# Check pod events
kubectl describe pod -n cert-manager <pod-name>

# Check logs
kubectl logs -n cert-manager deployment/cert-manager

# Common causes:
# 1. CRDs not installed
kubectl get crd | grep cert-manager

# 2. Webhook certificate issue
kubectl delete secret cert-manager-webhook-ca -n cert-manager
kubectl rollout restart deployment cert-manager-webhook -n cert-manager
```

### Issue: Certificate stuck in Pending

**Symptom**: `kubectl get certificate` shows status=False

**Solution**:
```bash
# Check certificate details
kubectl describe certificate <cert-name>

# Check CertificateRequest
kubectl get certificaterequest
kubectl describe certificaterequest <request-name>

# Check Order (ACME)
kubectl get order
kubectl describe order <order-name>

# Check Challenge
kubectl get challenge
kubectl describe challenge <challenge-name>

# Common issues:
# 1. ClusterIssuer not ready
kubectl get clusterissuer
kubectl describe clusterissuer <issuer-name>

# 2. DNS validation failed
# Verify Cloudflare token has DNS edit permissions

# 3. Rate limit (Let's Encrypt)
# Wait or use staging server for testing
```

### Issue: Cloudflare DNS challenge failing

**Symptom**: Challenge stuck in pending state

**Solution**:
```bash
# Check Cloudflare API token
kubectl get secret cloudflare-api-token -n cert-manager -o yaml

# Test token manually
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager | grep cloudflare

# Verify domain is in Cloudflare
# Check DNS propagation
dig TXT _acme-challenge.example.com

# Recreate secret if needed
kubectl delete secret cloudflare-api-token -n cert-manager
# Re-run ansible role
```

### Issue: Certificate not renewing

**Symptom**: Certificate expired or near expiry

**Solution**:
```bash
# Check certificate status
kubectl get certificate
kubectl describe certificate <cert-name>

# Check renewBefore setting
kubectl get certificate <cert-name> -o yaml | grep renewBefore

# Force renewal
kubectl delete secret <tls-secret-name>
# cert-manager will recreate it

# Check cert-manager logs for renewal errors
kubectl logs -n cert-manager deployment/cert-manager | grep renew
```

### Issue: Ingress annotation not working

**Symptom**: Certificate not created automatically from Ingress

**Solution**:
```bash
# Verify annotation is correct
kubectl get ingress <ingress-name> -o yaml | grep cert-manager

# Should be:
# annotations:
#   cert-manager.io/cluster-issuer: "letsencrypt-cloudflare"

# Check if Certificate was created
kubectl get certificate

# Verify ClusterIssuer exists and is ready
kubectl get clusterissuer <issuer-name>

# Check ingress-shim logs
kubectl logs -n cert-manager deployment/cert-manager | grep ingress-shim
```

### Issue: Webhook validation failing

**Symptom**: "Internal error occurred: failed calling webhook"

**Solution**:
```bash
# Check webhook pod
kubectl get pods -n cert-manager -l app=webhook

# Check webhook service
kubectl get svc -n cert-manager cert-manager-webhook

# Check ValidatingWebhookConfiguration
kubectl get validatingwebhookconfiguration | grep cert-manager

# Restart webhook
kubectl rollout restart deployment cert-manager-webhook -n cert-manager

# If persistent, reinstall
kubectl delete validatingwebhookconfiguration cert-manager-webhook
# Re-run ansible role
```

## Monitoring

### Certificate Expiry

```bash
# Check all certificates
kubectl get certificate --all-namespaces

# Check specific certificate details
kubectl get certificate <cert-name> -o jsonpath='{.status.notAfter}'
```

### Prometheus Metrics

cert-manager exposes metrics on port 9402:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cert-manager-metrics
  namespace: cert-manager
spec:
  selector:
    app: cert-manager
  ports:
  - port: 9402
```

Key metrics:
- `certmanager_certificate_expiration_timestamp_seconds` - Cert expiry time
- `certmanager_certificate_ready_status` - Certificate ready status
- `certmanager_controller_sync_call_count` - Controller sync count

### Grafana Dashboard

Import cert-manager dashboard:
- Dashboard ID: 11001
- URL: https://grafana.com/grafana/dashboards/11001

### Alerting

```yaml
# Prometheus alert rule
- alert: CertificateExpiryIn7Days
  expr: (certmanager_certificate_expiration_timestamp_seconds - time()) < 604800
  for: 1h
  annotations:
    summary: "Certificate {{ $labels.name }} expires in < 7 days"
```

## Performance Considerations

### Resource Limits

```bash
# Edit cert-manager deployment
kubectl edit deployment cert-manager -n cert-manager

# Update resources:
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Controller Tuning

```bash
# Edit deployment
kubectl edit deployment cert-manager -n cert-manager

# Add controller flags:
args:
- --max-concurrent-challenges=60
- --dns01-recursive-nameservers-only
- --dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53
```

### Certificate Caching

cert-manager automatically caches certificates and only renews when necessary (default: 2/3 through certificate lifetime).

## Security Considerations

### API Token Permissions

Cloudflare token should have **minimal permissions**:
- ✅ Zone → DNS → Edit (required)
- ❌ Zone → Zone → Edit (not needed)
- ❌ Account → Account Settings (not needed)

### Secret Encryption

- Use SOPS for encrypting sensitive data
- Never commit plaintext tokens to git
- Rotate tokens periodically

### RBAC

cert-manager requires ClusterRole permissions. Review and restrict if needed:

```bash
kubectl get clusterrole cert-manager-controller
kubectl get clusterrole cert-manager-webhook
```

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  podSelector:
    matchLabels:
      app: cert-manager
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # Let's Encrypt API
    - protocol: TCP
      port: 53   # DNS
    - protocol: UDP
      port: 53
```

## Rate Limits

Let's Encrypt has rate limits:
- **50 certificates** per registered domain per week
- **5 duplicate certificates** per week
- **300 pending authorizations** per account per week

**Best practices:**
- Use **staging server** for testing
- Avoid recreating certificates unnecessarily
- Use wildcard certificates to reduce count

## Integration Examples

### With NGINX Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls
  rules:
  - host: app.example.com
    # ...
```

### With Istio Gateway

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateway-cert
  namespace: istio-system
spec:
  secretName: gateway-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
  - "*.example.com"
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: gateway-tls
    hosts:
    - "*.example.com"
```

## Upgrade Path

### Upgrade cert-manager

```yaml
# Update version
cert_manager_version: "v1.17.0"

# Re-run role
ansible-playbook playbooks/install_cert_manager.yml
```

### Migrate from CRD v1alpha2 to v1

cert-manager v1.0+ uses `cert-manager.io/v1` API. If upgrading from older versions:

```bash
# Backup existing certificates
kubectl get certificate -A -o yaml > certificates-backup.yaml

# Upgrade cert-manager (Ansible role handles this)

# Certificates are automatically migrated
```

## Related Roles

- **ingress_nginx_install**: NGINX Ingress Controller (uses cert-manager)
- **traefik_install**: Traefik Ingress (alternative)
- **istio_install**: Service mesh with Gateway API
- **certbot_setup**: Alternative certificate management for VMs

## Related Playbooks

- `config/playbooks/install_cert_manager.yml`: Main cert-manager deployment
- `config/playbooks/install_ingress_nginx.yml`: Ingress + TLS stack

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [cert-manager GitHub](https://github.com/cert-manager/cert-manager)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [ACME DNS-01 Challenge](https://cert-manager.io/docs/configuration/acme/dns01/)
- [Cloudflare API Tokens](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)

## Changelog

- **2025-11**: Initial role creation for platform-iac
- **2025-11**: Helm-based installation with CRD support
- **2025-11**: Cloudflare DNS-01 ClusterIssuer integration
- **2025-11**: Gateway API support enabled

## Author

Platform Infrastructure Team

## License

Internal use only.
