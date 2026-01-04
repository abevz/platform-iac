# Platform IaC Documentation

Complete documentation for the Platform Infrastructure as Code project - a universal infrastructure management solution for all VM workloads on Proxmox VE, including Kubernetes clusters, databases, CI/CD systems, and application servers.

## 📚 Documentation Index

### Infrastructure Provisioning
- [Terraform Modules](../modules/terraform/proxmox-vm-cloudinit/README.md) - Proxmox VM provisioning with cloud-init
- [Dynamic Inventory](../tools/tofu_inventory.py) - Terraform output to Ansible inventory conversion

### Ansible Roles
- [Roles Overview](../config/roles/README.md) - Complete guide to all Ansible roles
- [k8s_bootstrap_node](../config/roles/k8s_bootstrap_node/README.md) - Node bootstrap with containerd
- [k8s_cluster_manager](../config/roles/k8s_cluster_manager/README.md) - Cluster initialization
- [argocd_install](../config/roles/argocd_install/README.md) - GitOps with ArgoCD
- [falco_install_helm](../config/roles/falco_install_helm/README.md) - Runtime security monitoring
- [kube_bench_run](../config/roles/kube_bench_run/README.md) - CIS benchmark compliance

### Security & Compliance
- [CKS Preparation](../kubernetes/cks-prep/README.md) - Certified Kubernetes Security Specialist resources
- [Security Policies](../kubernetes/policies/README.md) - Network policies, PSS, RBAC examples

### Tools & Utilities
- **[IAC Wrapper Guide](./IAC_WRAPPER.md)** ⭐ - Complete iac-wrapper.sh reference and command guide
- [IAC Wrapper Script](../tools/iac-wrapper.sh) - The orchestration script itself
- [Pi-hole DNS Integration](../tools/add_pihole_dns.py) - Automatic DNS record management

## 🏗️ Infrastructure Types

This platform supports multiple infrastructure types on Proxmox VE:

| Type | Use Case | Location | Status |
|------|----------|----------|--------|
| **Kubernetes Clusters** | Container orchestration, CKS prep | `infra/dev/k8s-lab-01/` | ✅ Active |
| **Database Clusters** | Percona XtraDB, PostgreSQL, MySQL | `infra/interview-prep/brainrocket-pxc/` | 🔧 In Progress |
| **CI/CD Systems** | GitLab, Jenkins, Drone | `infra/interview-prep/softswiss-gitlab/` | 🔧 In Progress |
| **Application VMs** | Web servers, app servers, microservices | `infra/<env>/<project>/` | 📝 Extensible |
| **Development Labs** | Testing, experimentation, learning | `infra/dev/` | ✅ Active |

### Modular Architecture

The platform uses reusable components that work across all infrastructure types:

- **Terraform Modules**: Generic VM provisioning (`modules/terraform/proxmox-vm-cloudinit/`)
- **Ansible Roles**: Modular roles for different services and configurations
- **Dynamic Inventory**: Automatic generation from Terraform outputs
- **Secret Management**: Unified SOPS encryption for all credentials
- **DNS Automation**: Automatic registration for any VM type

## 🚀 Quick Start

### 1. Prerequisites

**Tools Required:**
```bash
# Package manager tools
sudo apt-get install -y git python3 python3-pip sshpass

# Terraform/OpenTofu
wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform_1.9.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Ansible
pip3 install ansible kubernetes requests

# Ansible collections
ansible-galaxy collection install kubernetes.core community.general
```

**Access Requirements:**
- Proxmox VE API access
- SSH key for VM access
- Harbor container registry credentials (optional)

### 2. Initial Setup

```bash
# Clone repository
git clone https://github.com/abevz/platform-iac.git
cd platform-iac

# Configure secrets (use SOPS for production)
cp config/secrets/ansible/extra_vars.sops.yml.example \
   config/secrets/ansible/extra_vars.sops.yml
# Edit and encrypt with: sops -e -i extra_vars.sops.yml

# Set environment variables
export TF_VAR_pm_api_url="https://proxmox.example.com:8006/api2/json"
export TF_VAR_pm_api_token_id="user@pam!token"
export TF_VAR_pm_api_token_secret="xxx-xxx-xxx"
```

### 3. Deploy Infrastructure

```bash
# Using the wrapper script (recommended)
./tools/iac-wrapper.sh deploy dev k8s-lab-01

# Or manually:
cd infra/dev/k8s-lab-01
terraform init
terraform plan
terraform apply
```

### 4. Bootstrap Kubernetes

```bash
# Generate dynamic inventory
./tools/tofu_inventory.py infra/dev/k8s-lab-01

# Run bootstrap playbook
ansible-playbook -i config/inventory/static.ini \
  config/playbooks/setup_k8s-lab-01.yml
```

### 5. Install Add-ons

```bash
# Install CNI (Calico)
ansible-playbook -i config/inventory/static.ini \
  config/playbooks/install_calico_manifest.yml

# Install Ingress Controller
ansible-playbook -i config/inventory/static.ini \
  config/playbooks/install_ingress_nginx.yml

# Install ArgoCD
ansible-playbook -i config/inventory/static.ini \
  config/playbooks/install_argocd.yml

# Install Falco
ansible-playbook -i config/inventory/static.ini \
  config/playbooks/install_falco.yml

# Run Security Audit
ansible-playbook -i config/inventory/static.ini \
  config/playbooks/run_kube_bench.yml
```

## 📋 Project Structure

```
platform-iac/
├── config/                      # Ansible configuration
│   ├── ansible.cfg             # Ansible settings
│   ├── group_vars/             # Group variables
│   ├── inventory/              # Static inventory files
│   ├── playbooks/              # Ansible playbooks
│   │   ├── setup_k8s-lab-01.yml
│   │   ├── install_argocd.yml
│   │   └── run_kube_bench.yml
│   ├── roles/                  # Ansible roles (see roles/README.md)
│   └── secrets/                # Encrypted secrets (SOPS)
├── infra/                      # Terraform/OpenTofu infrastructure
│   └── dev/
│       └── k8s-lab-01/        # Development K8s cluster
├── kubernetes/                 # Kubernetes manifests
│   ├── apps/                  # Application deployments
│   ├── cks-prep/              # CKS exam preparation
│   └── policies/              # Security policies
├── modules/                    # Terraform modules
│   └── terraform/
│       └── proxmox-vm-cloudinit/
├── tools/                      # Utility scripts
│   ├── iac-wrapper.sh         # Main deployment wrapper
│   ├── tofu_inventory.py      # Dynamic inventory generator
│   └── add_pihole_dns.py      # DNS automation
└── docs/                       # Documentation (this directory)
```

## 🎯 Common Workflows

### Deploy New Cluster

```bash
# 1. Create Terraform workspace
mkdir -p infra/dev/k8s-lab-02
# Copy and modify from k8s-lab-01

# 2. Deploy VMs
./tools/iac-wrapper.sh deploy dev k8s-lab-02

# 3. Bootstrap Kubernetes
ansible-playbook -i <inventory> config/playbooks/setup_k8s-lab-02.yml

# 4. Install add-ons
# Run playbooks from config/playbooks/
```

### Add Worker Node

```bash
# 1. Update Terraform configuration
# Add worker node in infra/dev/k8s-lab-01/main.tf

# 2. Apply changes
cd infra/dev/k8s-lab-01
terraform apply

# 3. Bootstrap new node
ansible-playbook -i <inventory> \
  --limit k8s-lab-01-wn-03 \
  config/playbooks/setup_k8s-lab-01.yml \
  --tags k8s_bootstrap,join_workers
```

### Upgrade Kubernetes Version

```bash
# 1. Update version in group_vars
vim config/group_vars/k8s_master.yml
# Set: k8s_short_version: "1.34"

# 2. Upgrade control plane
ansible-playbook -i <inventory> \
  --limit k8s_master \
  config/playbooks/upgrade_k8s.yml

# 3. Upgrade workers one by one
ansible-playbook -i <inventory> \
  --limit k8s-lab-01-wn-01 \
  config/playbooks/upgrade_k8s.yml
```

### Run Security Audit

```bash
# Run kube-bench CIS benchmark
ansible-playbook -i <inventory> \
  config/playbooks/run_kube_bench.yml

# View results
kubectl logs -n kube-bench job/kube-bench

# Run Trivy vulnerability scan
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A
```

### Backup and Restore

```bash
# Backup etcd
kubectl -n kube-system exec etcd-<control-plane> -- \
  etcdctl snapshot save /var/lib/etcd/snapshot.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Restore from snapshot
# Stop kube-apiserver, restore snapshot, restart cluster
```

## 🔧 Configuration Management

### Variable Precedence

1. **Extra vars** (`-e` CLI flag) - Highest priority
2. **Task/Block vars**
3. **Role vars**
4. **Play vars**
5. **Host vars** (`host_vars/`)
6. **Group vars** (`group_vars/`)
7. **Role defaults** (`defaults/main.yml`) - Lowest priority

### Common Variables

```yaml
# Infrastructure
proxmox_host: "pve01.example.com"
vm_template_id: 9000

# Kubernetes
k8s_version: "1.33"
pod_network_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"

# Container Registry
harbor_url: "harbor.example.com"
harbor_robot_username: "robot$deployer"
harbor_robot_token: "{{ vault_harbor_token }}"

# Add-on states
addon_state: present  # present or absent
```

## 🔒 Security Best Practices

### 1. Secrets Management

```bash
# Use SOPS for encrypting secrets
sops -e -i config/secrets/ansible/extra_vars.sops.yml

# Never commit unencrypted secrets
# Add to .gitignore:
*.secret
*.key
!*.sops.yml
```

### 2. RBAC Least Privilege

```yaml
# Create service accounts with minimal permissions
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: production
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
  namespace: production
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
```

### 3. Network Segmentation

```yaml
# Default deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

### 4. Pod Security Standards

```yaml
# Enforce restricted PSS
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 5. Image Security

```bash
# Scan images with Trivy
trivy image nginx:latest

# Use image pull policies
imagePullPolicy: Always

# Use distroless or minimal base images
FROM gcr.io/distroless/static-debian11
```

## 🐛 Troubleshooting

### Common Issues

#### APT Lock Errors
```bash
# Roles automatically wait, but if manual intervention needed:
sudo rm /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a
```

#### Cluster Join Failures
```bash
# Generate new token (valid for 24h)
kubeadm token create --print-join-command

# Check firewall rules
sudo ufw status
sudo firewall-cmd --list-all
```

#### Pod Networking Issues
```bash
# Check CNI
kubectl get pods -n kube-system -l k8s-app=calico-node

# Restart CNI pods
kubectl rollout restart daemonset/calico-node -n kube-system

# Verify IP routing
ip route
```

#### Certificate Errors
```bash
# Check certificate expiration
kubeadm certs check-expiration

# Renew certificates
kubeadm certs renew all
systemctl restart kubelet
```

### Debug Mode

```bash
# Ansible verbose output
ansible-playbook playbook.yml -vvv

# Kubernetes debug
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
kubectl get events --sort-by='.lastTimestamp'
```

## 📊 Monitoring and Observability

### Logs

```bash
# Container logs
kubectl logs -f <pod-name> -n <namespace>

# System logs
journalctl -u kubelet -f
journalctl -u containerd -f

# Falco security alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

### Metrics

```bash
# Node metrics
kubectl top nodes

# Pod metrics
kubectl top pods -A

# Resource usage
kubectl describe node <node-name>
```

## 🧪 Testing

### Validation Checklist

- [ ] All nodes in Ready state
- [ ] All system pods Running
- [ ] CNI pods healthy
- [ ] CoreDNS responding
- [ ] Ingress controller running
- [ ] No CIS benchmark FAIL results
- [ ] Falco generating alerts
- [ ] No critical vulnerabilities (Trivy)

### Test Commands

```bash
# Node health
kubectl get nodes -o wide

# Pod health
kubectl get pods -A

# DNS resolution
kubectl run test --rm -it --image=busybox -- nslookup kubernetes.default

# Network connectivity
kubectl run test --rm -it --image=nicolaka/netshoot -- ping 8.8.8.8

# Ingress test
curl http://<ingress-ip>/
```

## 📚 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [Terraform Documentation](https://www.terraform.io/docs)
- [CKS Exam Guide](https://github.com/cncf/curriculum)
- [Falco Rules](https://github.com/falcosecurity/rules)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

## 🤝 Contributing

When adding new features:

1. Update relevant documentation
2. Follow existing code patterns
3. Add appropriate tags to playbooks
4. Test in dev environment first
5. Update this README if needed

## 📝 License

Internal use only - Platform Infrastructure Team.

## 👥 Support

For questions or issues:
- Check documentation in `docs/` directory
- Review role-specific READMEs
- Consult team knowledge base

---

**Last Updated**: November 2025
**Project**: platform-iac
**Owner**: abevz
