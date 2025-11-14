# Ansible Roles - Quick Reference

Quick overview of all available Ansible roles with their primary use cases.

## Infrastructure Roles

### k8s_bootstrap_node
**Purpose:** Bootstrap Kubernetes nodes with containerd and required packages  
**Tags:** `bootstrap_prereqs`, `containerd`, `k8s_packages`  
**Docs:** [Full Documentation](./k8s_bootstrap_node/README.md)

```bash
ansible-playbook playbook.yml --tags k8s_bootstrap
```

### k8s_cluster_manager
**Purpose:** Initialize control plane and join worker nodes  
**Tags:** `init_cluster`, `join_workers`

```bash
ansible-playbook playbook.yml --tags init_cluster,join_workers
```

### set_timezone
**Purpose:** Configure system timezone  
**Tags:** `timezone`

```yaml
vars:
  timezone: "Europe/Kiev"
```

## Networking Roles

### calico_install_manifest
**Purpose:** Install Calico CNI via Kubernetes manifests  
**Tags:** `calico`  
**Default CIDR:** `10.244.0.0/16`

### calico_install_helm
**Purpose:** Install Calico CNI via Helm  
**Tags:** `calico`  
**Recommended for:** Production environments

### cilium_install_helm
**Purpose:** Install Cilium CNI with eBPF-based networking  
**Tags:** `cilium`  
**Features:** kube-proxy replacement, Hubble observability

### metallb_install
**Purpose:** Provide LoadBalancer type services on bare-metal  
**Tags:** `metallb`  
**Requires:** IP address pool configuration

```yaml
metallb_ip_range: "192.168.1.200-192.168.1.250"
```

### ingress_nginx_install
**Purpose:** Install NGINX Ingress Controller  
**Tags:** `ingress`  
**Docs:** [Full Documentation](./ingress_nginx_install/README.md)

```bash
# Access via LoadBalancer (with MetalLB)
kubectl get svc -n ingress-nginx
```

### traefik_install
**Purpose:** Alternative Ingress Controller with built-in dashboard  
**Tags:** `traefik`

### istio_install
**Purpose:** Install Istio Service Mesh  
**Tags:** `istio`  
**Use cases:** mTLS, traffic management, observability

## Security Roles

### falco_install_helm
**Purpose:** Runtime security monitoring with system call analysis  
**Tags:** `falco`  
**Docs:** [Full Documentation](./falco_install_helm/README.md)

```bash
# View alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

### falco_install_package
**Purpose:** Install Falco as system package (alternative to Helm)  
**Tags:** `falco`  
**Use when:** Direct host installation preferred

### trivy_operator_deploy
**Purpose:** Continuous vulnerability and configuration scanning  
**Tags:** `trivy`

```bash
# View vulnerability reports
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A
```

### trivy_package_install
**Purpose:** Install Trivy CLI for manual scanning  
**Tags:** `trivy`

```bash
trivy image nginx:latest
trivy k8s --report summary cluster
```

### kube_bench_run
**Purpose:** Run CIS Kubernetes Benchmark security audit  
**Tags:** `kube_bench`  
**Docs:** [Full Documentation](./kube_bench_run/README.md)

```bash
# Run audit and view results
ansible-playbook playbooks/run_kube_bench.yml
kubectl logs -n kube-bench job/kube-bench
```

### apparmor_configure
**Purpose:** Deploy and configure AppArmor security profiles  
**Tags:** `apparmor`  
**Profiles:** Docker, Kubernetes, custom application profiles

```bash
# Verify AppArmor status
sudo aa-status
```

### cert_manager_install
**Purpose:** Automated TLS certificate management  
**Tags:** `cert_manager`  
**Supports:** Let's Encrypt, self-signed, Vault

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

## Application Delivery

### argocd_install
**Purpose:** GitOps continuous delivery platform  
**Tags:** `argocd`  
**Docs:** [Full Documentation](./argocd_install/README.md)

```bash
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Port forward to UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### bom_install
**Purpose:** Install Bill of Materials (BOM) tooling  
**Tags:** `bom`  
**Use cases:** Supply chain security, SBOM generation

### nginx_proxy_setup
**Purpose:** Configure Nginx reverse proxy with Docker Compose  
**Tags:** `nginx_proxy`  
**Use cases:** Reverse proxy for services, SSL termination

```yaml
vars:
  nginx_proxy_vhosts:
    - domain: "example.com"
      upstream: "http://backend:8080"
```

### certbot_setup
**Purpose:** Setup Certbot for Let's Encrypt SSL certificates  
**Tags:** `certbot`  
**Features:** Automatic certificate renewal, DNS-01 challenge support

```yaml
vars:
  certbot_domains:
    - "example.com"
    - "*.example.com"
```

## Role Usage Patterns

### Install Single Add-on

```bash
ansible-playbook -i inventory playbooks/install_<addon>.yml
```

### Install with Specific Version

```bash
ansible-playbook -i inventory playbooks/install_argocd.yml \
  -e "requested_version=v2.12.0"
```

### Uninstall Add-on

```bash
ansible-playbook -i inventory playbooks/install_<addon>.yml \
  -e "addon_state=absent"
```

### Run with Tags

```bash
# Only prerequisites
ansible-playbook playbook.yml --tags bootstrap_prereqs

# Multiple tags
ansible-playbook playbook.yml --tags "containerd,k8s_packages"

# Skip specific tags
ansible-playbook playbook.yml --skip-tags k8s_packages
```

### Limit to Specific Hosts

```bash
ansible-playbook -i inventory playbook.yml --limit k8s-lab-01-cp
ansible-playbook -i inventory playbook.yml --limit k8s_worker
```

### Dry Run (Check Mode)

```bash
ansible-playbook -i inventory playbook.yml --check
```

### Debug Mode

```bash
ansible-playbook -i inventory playbook.yml -vvv
```

## Common Variables

### Global Settings

```yaml
# Kubernetes version
k8s_version: "1.33"
k8s_short_version: "1.33"

# Network configuration
pod_network_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
cluster_dns: "10.96.0.10"

# Container registry
harbor_url: "harbor.example.com"
harbor_robot_username: "robot$deployer"
harbor_robot_token: "{{ vault_harbor_token }}"
```

### Add-on Control

```yaml
# State management (all add-on roles)
addon_state: present  # Options: present, absent

# Version override
requested_version: "v2.0.0"
```

## Role Dependencies

### Deployment Order

1. **Infrastructure**
   ```
   k8s_bootstrap_node → k8s_cluster_manager
   ```

2. **Networking**
   ```
   CNI (calico/cilium) → metallb_install → ingress_nginx_install
   ```

3. **Security**
   ```
   apparmor_configure → falco_install_helm → trivy_operator_deploy
   ```

4. **Applications**
   ```
   cert_manager_install → argocd_install
   ```

## Troubleshooting Quick Reference

### Check Role Status

```bash
# View role tasks
ansible-playbook playbook.yml --list-tasks

# View role tags
ansible-playbook playbook.yml --list-tags

# Syntax check
ansible-playbook playbook.yml --syntax-check
```

### Common Issues

#### APT Lock Errors
```bash
# Roles handle automatically, but manual fix:
sudo rm /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a
```

#### Helm Installation Fails
```bash
# Check Helm binary
helm version

# Reinstall if needed
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### CNI Pods Not Running
```bash
# Check CNI installation
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl get pods -n kube-system -l k8s-app=cilium

# Restart CNI
kubectl rollout restart daemonset/<cni-daemonset> -n kube-system
```

#### Add-on Already Exists
```bash
# Force reinstall
ansible-playbook playbook.yml -e "addon_state=absent"
ansible-playbook playbook.yml -e "addon_state=present"
```

## Testing Roles

### Molecule (Advanced)

For role development, use Molecule:

```bash
cd config/roles/my_role
molecule init scenario
molecule test
```

### Manual Testing

```bash
# Create test VM
# Run role against test VM
ansible-playbook -i test_inventory playbook.yml --check

# Apply changes
ansible-playbook -i test_inventory playbook.yml

# Verify results
ansible-playbook -i test_inventory playbook.yml --check
```

## Best Practices

### ✅ Do

- Use tags for selective execution
- Define variables in `defaults/main.yml`
- Use handlers for service restarts
- Implement idempotency in tasks
- Document role variables
- Use `addon_state` for installation control

### ❌ Don't

- Hardcode sensitive values
- Skip error handling
- Use `command` without `changed_when`
- Deploy without testing
- Ignore role dependencies

## Related Documentation

- [Main Documentation](../docs/README.md)
- [Cheat Sheet](../docs/CHEATSHEET.md)
- [k8s_bootstrap_node](./k8s_bootstrap_node/README.md)
- [argocd_install](./argocd_install/README.md)
- [falco_install_helm](./falco_install_helm/README.md)
- [kube_bench_run](./kube_bench_run/README.md)

## Support

For detailed role documentation, see individual `README.md` files in each role directory.

---

**Last Updated**: November 2025  
**Platform**: platform-iac
