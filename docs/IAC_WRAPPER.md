# IAC Wrapper Script Guide

Complete guide to the `iac-wrapper.sh` — the central orchestration script for managing all infrastructure on Proxmox.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Commands Reference](#commands-reference)
- [Environment Structure](#environment-structure)
- [Component Management](#component-management)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

The `iac-wrapper.sh` script is a **unified interface** for managing infrastructure lifecycle:

```
iac-wrapper.sh → OpenTofu (provision VMs) → Ansible (configure VMs)
```

**Key Features:**
- ✅ SOPS secrets decryption
- ✅ Dynamic Ansible inventory from Terraform state
- ✅ Environment isolation (dev/staging/prod)
- ✅ Component-based deployment
- ✅ State management and validation
- ✅ Integrated Pi-hole DNS registration

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        iac-wrapper.sh                            │
│                                                                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌──────────┐ │
│  │   SOPS     │  │  OpenTofu  │  │  Ansible   │  │ Pi-hole  │ │
│  │  Decrypt   │─▶│  Plan/     │─▶│  Dynamic   │─▶│   DNS    │ │
│  │  Secrets   │  │  Apply     │  │  Inventory │  │ Register │ │
│  └────────────┘  └────────────┘  └────────────┘  └──────────┘ │
└─────────────────────────────────────────────────────────────────┘
         │                  │                │              │
         ▼                  ▼                ▼              ▼
    credentials.yml    Proxmox VMs    VM Configuration   DNS Records
```

---

## 📖 Commands Reference

### Core Commands

#### 1. **apply** - Full Infrastructure Deployment

Provisions VMs with Terraform and configures them with Ansible.

**Syntax:**
```bash
./tools/iac-wrapper.sh apply <environment> <component> [ansible_tags]
```

**Examples:**

```bash
# Deploy full Kubernetes cluster
./tools/iac-wrapper.sh apply dev k8s-lab-01

# Deploy only control plane bootstrap
./tools/iac-wrapper.sh apply dev k8s-lab-01 bootstrap_control_plane

# Deploy with specific tags
./tools/iac-wrapper.sh apply dev k8s-lab-01 "bootstrap_control_plane,install_cni"
```

**What it does:**
1. Decrypts SOPS secrets
2. Runs `tofu plan` → `tofu apply`
3. Generates dynamic Ansible inventory
4. Registers DNS records in Pi-hole
5. Runs Ansible playbook with specified tags

---

#### 2. **destroy** - Teardown Infrastructure

Destroys VMs and removes DNS records.

**Syntax:**
```bash
./tools/iac-wrapper.sh destroy <environment> <component> [--auto-approve]
```

**Examples:**

```bash
# Destroy with confirmation
./tools/iac-wrapper.sh destroy dev k8s-lab-01

# Destroy without confirmation (dangerous!)
./tools/iac-wrapper.sh destroy dev k8s-lab-01 --auto-approve
```

**What it does:**
1. Removes Pi-hole DNS records
2. Runs `tofu destroy`
3. Cleans up local state cache

---

#### 3. **plan** - Preview Changes

Shows what changes will be made without applying them.

**Syntax:**
```bash
./tools/iac-wrapper.sh plan <environment> <component>
```

**Example:**

```bash
./tools/iac-wrapper.sh plan dev k8s-lab-01
```

**What it does:**
1. Decrypts SOPS secrets
2. Runs `tofu plan`
3. Shows resource changes (create/update/destroy)

---

#### 4. **run-playbook** - Execute Ad-hoc Ansible Playbook

Runs a custom playbook against existing infrastructure.

**Syntax:**
```bash
./tools/iac-wrapper.sh run-playbook <environment> <component> <playbook.yml> <limit_target>
```

**Examples:**

```bash
# Configure timezone on nginx-proxy
./tools/iac-wrapper.sh run-playbook dev nginx-proxy configure_timezone.yml nginx_proxies

# Run security audit on Kubernetes cluster
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 security_audit.yml k8s_master

# Update all workers
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 system_update.yml k8s_worker
```

**Parameters:**
- `<playbook.yml>`: Playbook file in `config/playbooks/`
- `<limit_target>`: Ansible group from dynamic inventory (e.g., `k8s_master`, `k8s_worker`, `nginx_proxies`)

**What it does:**
1. Loads dynamic inventory from Terraform state
2. Runs specified playbook with `--limit <limit_target>`
3. Uses existing VM infrastructure

---

#### 5. **ansible-only** - Run Ansible Without Terraform

Re-runs Ansible configuration without reprovisioning VMs.

**Syntax:**
```bash
./tools/iac-wrapper.sh ansible-only <environment> <component> [ansible_tags]
```

**Examples:**

```bash
# Reconfigure entire cluster
./tools/iac-wrapper.sh ansible-only dev k8s-lab-01

# Only install CNI
./tools/iac-wrapper.sh ansible-only dev k8s-lab-01 install_cni

# Update security settings
./tools/iac-wrapper.sh ansible-only dev k8s-lab-01 "security,apparmor"
```

**Use cases:**
- ✅ Changed Ansible variables
- ✅ Updated role logic
- ✅ Failed Ansible run (retry)
- ✅ Applying new security policies

---

#### 6. **validate** - Validate Configuration

Checks Terraform/Tofu configuration syntax.

**Syntax:**
```bash
./tools/iac-wrapper.sh validate <environment> <component>
```

**Example:**

```bash
./tools/iac-wrapper.sh validate dev k8s-lab-01
```

---

## 📁 Environment Structure

The wrapper expects this directory structure:

```
platform-iac/
├── infra/
│   ├── dev/                    # Development environment
│   │   ├── k8s-lab-01/        # Kubernetes cluster component
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── credentials.sops.yml
│   │   ├── nginx-proxy/       # Nginx proxy component
│   │   └── database-cluster/  # Database cluster component
│   ├── staging/               # Staging environment
│   └── prod/                  # Production environment
├── config/
│   ├── playbooks/             # Ansible playbooks
│   │   ├── setup_k8s.yml
│   │   ├── configure_timezone.yml
│   │   └── security_audit.yml
│   └── roles/                 # Ansible roles
└── tools/
    ├── iac-wrapper.sh         # Main script
    ├── tofu_inventory.py      # Dynamic inventory generator
    └── add_pihole_dns.py      # DNS registration
```

---

## 🧩 Component Management

### Defining a Component

Each component in `infra/<env>/<component>/` must have:

#### 1. **outputs.tf** - Dynamic Inventory Definition

```hcl
# Required for iac-wrapper.sh
output "control_plane_ip" {
  value = proxmox_vm_qemu.k8s_control_plane.default_ipv4_address
}

output "worker_ips" {
  value = proxmox_vm_qemu.k8s_worker[*].default_ipv4_address
}

output "control_plane_hostname" {
  value = proxmox_vm_qemu.k8s_control_plane.name
}

output "worker_hostnames" {
  value = proxmox_vm_qemu.k8s_worker[*].name
}
```

#### 2. **credentials.sops.yml** - Encrypted Secrets

```yaml
# Encrypted with SOPS
proxmox_api_url: "https://proxmox.example.com:8006/api2/json"
proxmox_api_token_id: "root@pam!terraform"
proxmox_api_token_secret: "encrypted-secret-here"
ssh_public_key: "ssh-rsa AAAA..."
```

#### 3. **Playbook Association**

The wrapper looks for `config/playbooks/setup_<component>.yml`:

```bash
# Component: k8s-lab-01
# Playbook:  config/playbooks/setup_k8s.yml

# Component: nginx-proxy
# Playbook:  config/playbooks/setup_nginx.yml
```

---

## 🎯 Component Types

### 1. Kubernetes Cluster

**Structure:**
```
infra/dev/k8s-lab-01/
├── main.tf                 # VM definitions
├── outputs.tf              # IPs and hostnames
├── credentials.sops.yml    # Secrets
└── variables.tf            # Configurable params
```

**Deployment:**
```bash
./tools/iac-wrapper.sh apply dev k8s-lab-01
```

**Dynamic Inventory Groups:**
- `k8s_master` - Control plane nodes
- `k8s_worker` - Worker nodes
- `all` - All nodes

---

### 2. Nginx Proxy

**Structure:**
```
infra/dev/nginx-proxy/
├── main.tf
├── outputs.tf              # nginx_proxies group
└── credentials.sops.yml
```

**Deployment:**
```bash
./tools/iac-wrapper.sh apply dev nginx-proxy
```

**Dynamic Inventory Groups:**
- `nginx_proxies` - All nginx VMs

---

### 3. Database Cluster (Percona XtraDB)

**Structure:**
```
infra/dev/database-cluster/
├── main.tf
├── outputs.tf              # db_primary, db_replicas
└── credentials.sops.yml
```

**Deployment:**
```bash
./tools/iac-wrapper.sh apply dev database-cluster
```

**Dynamic Inventory Groups:**
- `db_primary` - Primary DB node
- `db_replicas` - Replica nodes

---

## 🔧 Advanced Usage

### Selective Deployment with Tags

Ansible tags allow partial deployments:

```bash
# Only bootstrap nodes (skip cluster init)
./tools/iac-wrapper.sh apply dev k8s-lab-01 bootstrap_nodes

# Only install CNI
./tools/iac-wrapper.sh apply dev k8s-lab-01 install_cni

# Multiple tags
./tools/iac-wrapper.sh apply dev k8s-lab-01 "bootstrap_control_plane,install_cni,metallb"

# Security-only update
./tools/iac-wrapper.sh ansible-only dev k8s-lab-01 "security,apparmor,falco"
```

**Available Tags:** See [Roles Quick Reference](../config/roles/QUICK_REFERENCE.md#available-tags)

---

### Environment Variables

Override default behavior:

```bash
# Custom SSH key
SSH_KEY=/path/to/key ./tools/iac-wrapper.sh apply dev k8s-lab-01

# Custom Ansible timeout
ANSIBLE_TIMEOUT=60 ./tools/iac-wrapper.sh ansible-only dev k8s-lab-01

# Skip DNS registration
SKIP_DNS=true ./tools/iac-wrapper.sh apply dev nginx-proxy

# Ansible verbose mode
ANSIBLE_VERBOSE="-vvv" ./tools/iac-wrapper.sh ansible-only dev k8s-lab-01
```

---

### Multi-Environment Workflow

```bash
# Deploy to dev
./tools/iac-wrapper.sh apply dev k8s-lab-01

# Test in dev
kubectl --context dev-k8s-lab-01 get nodes

# Promote to staging
./tools/iac-wrapper.sh apply staging k8s-cluster-01

# Validate staging
./tools/iac-wrapper.sh run-playbook staging k8s-cluster-01 smoke_tests.yml all

# Deploy to production
./tools/iac-wrapper.sh apply prod k8s-prod-01
```

---

## 🔍 Dynamic Inventory Details

### How It Works

`tofu_inventory.py` generates Ansible inventory from Terraform outputs:

```python
# From Terraform outputs.tf
{
  "control_plane_ip": "192.168.1.100",
  "worker_ips": ["192.168.1.101", "192.168.1.102"],
  "control_plane_hostname": "k8s-cp",
  "worker_hostnames": ["k8s-wn-01", "k8s-wn-02"]
}

# Becomes Ansible inventory
{
  "k8s_master": {
    "hosts": ["192.168.1.100"]
  },
  "k8s_worker": {
    "hosts": ["192.168.1.101", "192.168.1.102"]
  },
  "_meta": {
    "hostvars": {
      "192.168.1.100": {"inventory_hostname": "k8s-cp"}
    }
  }
}
```

### Custom Inventory Mappings

Define in `outputs.tf`:

```hcl
# Custom group names
output "custom_group_ips" {
  value = proxmox_vm_qemu.custom[*].default_ipv4_address
}

output "custom_group_hostnames" {
  value = proxmox_vm_qemu.custom[*].name
}
```

Use in playbooks:

```yaml
- hosts: custom_group
  tasks:
    - name: Configure custom VMs
      # ...
```

---

## 🐛 Troubleshooting

### Issue: "No Terraform state found"

**Symptom:**
```bash
ERROR: No Terraform state found in infra/dev/k8s-lab-01
```

**Solution:**
```bash
# Initialize Terraform
cd infra/dev/k8s-lab-01
tofu init
cd -

# Retry wrapper
./tools/iac-wrapper.sh apply dev k8s-lab-01
```

---

### Issue: "SOPS decryption failed"

**Symptom:**
```bash
Failed to get the data key required to decrypt the SOPS file.
```

**Solution:**
```bash
# Verify AGE key is configured
echo $SOPS_AGE_KEY_FILE  # Should print /path/to/keys.txt

# Test decryption manually
sops -d infra/dev/k8s-lab-01/credentials.sops.yml

# Re-encrypt if needed
sops -e -i infra/dev/k8s-lab-01/credentials.sops.yml
```

---

### Issue: "Ansible cannot connect"

**Symptom:**
```bash
UNREACHABLE! => {"changed": false, "msg": "Failed to connect via ssh"}
```

**Solution:**
```bash
# Verify SSH key
ls -la /home/abevz/Projects/platform-iac/cpc_deployment_key

# Test SSH manually
ssh -i /path/to/key root@192.168.1.100

# Check VM cloud-init completed
ssh root@192.168.1.100 'cloud-init status'

# Wait for cloud-init
./tools/iac-wrapper.sh ansible-only dev k8s-lab-01 wait_for_apt
```

---

### Issue: "Pi-hole DNS registration failed"

**Symptom:**
```bash
ERROR: Failed to add DNS record for k8s-cp
```

**Solution:**
```bash
# Check Pi-hole is accessible
curl -I http://10.10.10.x/admin

# Verify credentials in credentials.sops.yml
sops -d infra/dev/k8s-lab-01/credentials.sops.yml | grep pihole

# Skip DNS registration temporarily
SKIP_DNS=true ./tools/iac-wrapper.sh apply dev k8s-lab-01
```

---

### Issue: "Terraform state lock"

**Symptom:**
```bash
Error acquiring the state lock: ConditionalCheckFailedException
```

**Solution:**
```bash
# Force unlock (use with caution!)
cd infra/dev/k8s-lab-01
tofu force-unlock <lock-id>

# Or wait for lock to expire (15 minutes)
```

---

## 📊 Script Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│ START: ./tools/iac-wrapper.sh apply dev k8s-lab-01              │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Parse arguments       │
                │ - env: dev            │
                │ - component: k8s-lab  │
                │ - action: apply       │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Set environment vars  │
                │ - TF_DIR              │
                │ - PLAYBOOK            │
                │ - SSH_KEY             │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Decrypt SOPS secrets  │
                │ credentials.sops.yml  │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Run: tofu init        │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Run: tofu plan        │
                │ Review changes?       │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Run: tofu apply       │
                │ Provision VMs         │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Generate inventory    │
                │ tofu_inventory.py     │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Register Pi-hole DNS  │
                │ add_pihole_dns.py     │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Run: ansible-playbook │
                │ setup_k8s.yml         │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Deployment complete   │
                └───────────────────────┘
```

---

## 🎓 Common Workflows

### 1. New Kubernetes Cluster

```bash
# 1. Create Terraform config
mkdir -p infra/dev/k8s-new
cp -r infra/dev/k8s-lab-01/* infra/dev/k8s-new/

# 2. Update variables
vim infra/dev/k8s-new/variables.tf

# 3. Deploy
./tools/iac-wrapper.sh apply dev k8s-new

# 4. Verify
kubectl --kubeconfig ~/.kube/k8s-new get nodes
```

---

### 2. Update Kubernetes Version

```bash
# 1. Update variables.tf
vim infra/dev/k8s-lab-01/variables.tf  # k8s_version = "1.29"

# 2. Plan changes
./tools/iac-wrapper.sh plan dev k8s-lab-01

# 3. Apply (will recreate VMs)
./tools/iac-wrapper.sh apply dev k8s-lab-01
```

---

### 3. Add Worker Nodes

```bash
# 1. Update worker count
vim infra/dev/k8s-lab-01/variables.tf  # worker_count = 3

# 2. Apply
./tools/iac-wrapper.sh apply dev k8s-lab-01

# 3. Verify
kubectl get nodes
```

---

### 4. Reconfigure Security Settings

```bash
# 1. Update role variables
vim config/roles/falco_install_helm/defaults/main.yml

# 2. Re-run security roles
./tools/iac-wrapper.sh ansible-only dev k8s-lab-01 "falco,apparmor,kube_bench"

# 3. Verify
kubectl -n falco get pods
```

---

## 📚 Related Documentation

- **[Main Documentation](./README.md)** - Platform overview
- **[Architecture Guide](./ARCHITECTURE.md)** - System design
- **[Roles Reference](../config/roles/README.md)** - Ansible roles
- **[Cheat Sheet](./CHEATSHEET.md)** - Quick commands

---

**Last Updated**: November 2025  
**Maintainer**: Platform Team