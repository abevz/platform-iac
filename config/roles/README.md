# Ansible Roles Documentation

This directory contains Ansible roles for bootstrapping and managing Kubernetes clusters with security-focused configurations.

## 📋 Table of Contents

- [Role Overview](#role-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Role Categories](#role-categories)

## Role Overview

| Role | Purpose | Tags |
|------|---------|------|
| [k8s_bootstrap_node](./k8s_bootstrap_node/README.md) | Bootstrap Kubernetes nodes with containerd and required packages | `bootstrap_prereqs`, `containerd`, `k8s_packages` |
| [k8s_cluster_manager](./k8s_cluster_manager/README.md) | Initialize and join nodes to Kubernetes cluster | `init_cluster`, `join_workers` |
| [argocd_install](./argocd_install/README.md) | Deploy ArgoCD GitOps tool | `argocd` |
| [calico_install_manifest](./calico_install_manifest/README.md) | Install Calico CNI via manifest | `calico` |
| [calico_install_helm](./calico_install_helm/README.md) | Install Calico CNI via Helm | `calico` |
| [cilium_install_helm](./cilium_install_helm/README.md) | Install Cilium CNI via Helm | `cilium` |
| [cert_manager_install](./cert_manager_install/README.md) | Deploy cert-manager for TLS certificate management | `cert_manager` |
| [ingress_nginx_install](./ingress_nginx_install/README.md) | Install NGINX Ingress Controller | `ingress` |
| [traefik_install](./traefik_install/README.md) | Install Traefik Ingress Controller | `traefik` |
| [metallb_install](./metallb_install/README.md) | Deploy MetalLB for LoadBalancer services | `metallb` |
| [istio_install](./istio_install/README.md) | Install Istio Service Mesh | `istio` |
| [falco_install_helm](./falco_install_helm/README.md) | Deploy Falco runtime security via Helm | `falco` |
| [falco_install_package](./falco_install_package/README.md) | Install Falco via system packages | `falco` |
| [trivy_operator_deploy](./trivy_operator_deploy/README.md) | Deploy Trivy Operator for vulnerability scanning | `trivy` |
| [trivy_package_install](./trivy_package_install/README.md) | Install Trivy CLI tool | `trivy` |
| [kube_bench_run](./kube_bench_run/README.md) | Run kube-bench CIS benchmark tests | `kube_bench` |
| [apparmor_configure](./apparmor_configure/README.md) | Configure AppArmor security profiles | `apparmor` |
| [set_timezone](./set_timezone/README.md) | Configure system timezone | `timezone` |
| [bom_install](./bom_install/README.md) | Install Bill of Materials (BOM) tooling | `bom` |
| [nginx_proxy_setup](./nginx_proxy_setup/README.md) | Configure Nginx reverse proxy with Docker Compose | `nginx_proxy` |
| [certbot_setup](./certbot_setup/README.md) | Setup Certbot for Let's Encrypt SSL certificates | `certbot` |

## Prerequisites

### Control Node Requirements
- Ansible 2.9+
- Python 3.8+
- Required collections:
  ```bash
  ansible-galaxy collection install kubernetes.core
  ansible-galaxy collection install community.general
  ```

### Target Node Requirements
- Debian 11/12 or Rocky Linux 8/9
- Minimum 2 CPU cores, 2GB RAM
- Root or sudo access
- Network connectivity to container registries

## Quick Start

### 1. Configure Inventory

Edit `config/inventory/static.ini`:

```ini
[k8s_master]
k8s-lab-01-cp ansible_host=192.168.1.10

[k8s_worker]
k8s-lab-01-wn-01 ansible_host=192.168.1.11
k8s-lab-01-wn-02 ansible_host=192.168.1.12
```

### 2. Set Variables

Edit `config/group_vars/k8s_master.yml`:

```yaml
k8s_version: "1.33"
pod_network_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
```

### 3. Run Playbook

```bash
cd /home/abevz/Projects/platform-iac
ansible-playbook -i config/inventory/static.ini config/playbooks/setup_k8s-lab-01.yml
```

## Role Categories

### 🏗️ Infrastructure Roles
- **k8s_bootstrap_node**: Core Kubernetes node setup
- **k8s_cluster_manager**: Cluster initialization and management
- **set_timezone**: System configuration
- **nginx_proxy_setup**: Nginx reverse proxy with Docker Compose
- **certbot_setup**: Let's Encrypt SSL certificate automation

### 🌐 Networking Roles
- **calico_install_manifest / calico_install_helm**: CNI networking
- **cilium_install_helm**: Advanced CNI with eBPF
- **metallb_install**: LoadBalancer implementation
- **ingress_nginx_install**: Ingress controller
- **traefik_install**: Alternative ingress controller
- **istio_install**: Service mesh

### 🔒 Security Roles
- **falco_install_helm / falco_install_package**: Runtime security monitoring
- **apparmor_configure**: Mandatory access control
- **kube_bench_run**: CIS compliance testing
- **trivy_operator_deploy**: Vulnerability scanning
- **cert_manager_install**: TLS certificate automation

### 🚀 Application Delivery
- **argocd_install**: GitOps continuous delivery
- **bom_install**: Supply chain tooling

## Usage Patterns

### Run Specific Role with Tags

```bash
ansible-playbook playbook.yml --tags "bootstrap_prereqs,containerd"
```

### Skip Specific Tags

```bash
ansible-playbook playbook.yml --skip-tags "k8s_packages"
```

### Check Mode (Dry Run)

```bash
ansible-playbook playbook.yml --check
```

### Limit to Specific Hosts

```bash
ansible-playbook playbook.yml --limit k8s-lab-01-cp
```

## Variable Precedence

From highest to lowest priority:

1. Extra vars (`-e` CLI flag)
2. Task vars
3. Block vars
4. Role vars
5. Play vars
6. Host vars (`host_vars/`)
7. Group vars (`group_vars/`)
8. Role defaults (`defaults/main.yml`)

## Common Variables

### Global Variables (group_vars/all.yml)

```yaml
# Container Registry
harbor_url: "harbor.example.com"
harbor_robot_username: "robot$deployer"
harbor_robot_token: "{{ lookup('env', 'HARBOR_TOKEN') }}"

# Kubernetes Version
k8s_version: "1.33"

# Network Configuration
pod_network_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
```

### Addon State Control

All addon roles support `addon_state` variable:

```yaml
addon_state: present  # Options: present, absent
```

## Troubleshooting

### Common Issues

1. **Lock File Errors**
   - Roles automatically wait for APT/DNF locks
   - Increase `retries` in role if needed

2. **Container Pull Failures**
   - Verify Harbor credentials in `harbor_auth`
   - Check network connectivity to registries

3. **Cluster Join Failures**
   - Verify token validity (24h default)
   - Check firewall rules for Kubernetes ports

### Debug Mode

Enable verbose output:

```bash
ansible-playbook playbook.yml -vvv
```

### Log Locations

- Containerd: `/var/log/containerd/containerd.log`
- Kubelet: `journalctl -u kubelet -f`
- Pods: `kubectl logs -n <namespace> <pod>`

## Contributing

When adding new roles:

1. Create role structure: `ansible-galaxy init role_name`
2. Add README.md with documentation
3. Define defaults in `defaults/main.yml`
4. Add appropriate tags to tasks
5. Test with `molecule` if available
6. Update this main README

## Related Documentation

- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [CKS Exam Preparation](../kubernetes/cks-prep/README.md)

## License

Internal use only - Platform Infrastructure as Code project.
