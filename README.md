# platform-iac

> **Platform Infrastructure as Code** - Universal IaC solution for managing all virtual machines on Proxmox VE with automated provisioning, configuration management, and security hardening.

> [!WARNING]
> **Example Configuration**
> This repository contains example IP addresses (`10.10.10.x`) and domain names (`bevz.net`) for demonstration purposes.
> **Before deployment:**
> 1. Copy `config/platform.conf.example` to `config/platform.conf`.
> 2. Update `config/platform.conf` with your specific infrastructure details (IPs, domains, SSH ports).
> 3. Ensure your SSH keys are placed in `keys/` directory (or update the path in config).

## Overview

`platform-iac` is a comprehensive **Infrastructure as Code (IaC)** and **Configuration Management (CM)** solution for managing **all virtual infrastructure** on **Proxmox VE**. This includes Kubernetes clusters, database servers (Percona XtraDB, PostgreSQL), GitLab instances, mail servers, application servers, and any other VM-based workloads.

This project uses a hybrid approach:

- **[OpenTofu](https://opentofu.org/)** (Terraform) provisions the virtual machines, storage, and networking on Proxmox.
- **[Ansible](https://www.ansible.com/)** performs the complete system configuration, from bootstrapping nodes to deploying security tooling.

The entire process is orchestrated by a master wrapper script (`tools/iac-wrapper.sh`) for seamless, one-command deployment.

## 📚 Documentation

> **4,297 lines** of comprehensive documentation covering all aspects of the platform

### 🎯 Quick Access

- **[📖 Complete Documentation](docs/README.md)** - Full platform guide with workflows
- **[🛠️ IAC Wrapper Guide](docs/IAC_WRAPPER.md)** ⭐ - Central orchestration script reference
- **[⚡ Quick Reference](docs/CHEATSHEET.md)** - Command cheat sheet for daily use
- **[🏗️ Architecture](docs/ARCHITECTURE.md)** - Visual diagrams and system design
- **[📑 Documentation Index](docs/INDEX.md)** - Complete documentation catalog

### 🎭 Role Documentation

- **[All Roles Overview](config/roles/README.md)** - Complete role catalog
- **[Quick Reference](config/roles/QUICK_REFERENCE.md)** - Fast role lookup
- **[k8s_bootstrap_node](config/roles/k8s_bootstrap_node/README.md)** - Node bootstrap (500+ lines)
- **[argocd_install](config/roles/argocd_install/README.md)** - GitOps deployment (550+ lines)
- **[falco_install_helm](config/roles/falco_install_helm/README.md)** - Runtime security (600+ lines)
- **[kube_bench_run](config/roles/kube_bench_run/README.md)** - CIS compliance (650+ lines)

## Features

### Universal Infrastructure Management

- **Multi-Environment Support:** Separate environments (dev, staging, production, interview-prep)
- **Flexible VM Types:** Support for any workload:
  - Kubernetes clusters (k8s-lab)
  - Databases (PostgreSQL, Percona)
  - Mail servers (Docker Mailserver)
  - CI/CD (GitLab, Jenkins)
  - Web servers (Nginx, Traefik)
- **Infrastructure as Code:** Fully automated VM provisioning on Proxmox VE using OpenTofu/Terraform
- **Dynamic Inventory:** Tofu automatically generates Ansible inventory, eliminating manual management
- **Modular Design:** Reusable Terraform modules and Ansible roles for different infrastructure types

### Security & Compliance

- **Secure Secret Management:** All secrets (API keys, tokens, passwords) encrypted with **SOPS**
- **CKS-Ready Kubernetes:** Full security hardening for Certified Kubernetes Security Specialist exam
  - **CNI:** Calico/Cilium with network policies
  - **Security Tooling:** Falco runtime security, Trivy vulnerability scanning, kube-bench CIS audits
  - **Kernel Security:** AppArmor and Seccomp profiles
- **Database Security:** Encryption at rest, secure backups, replication configurations

### Automation & Integration

- **Automated DNS:** Pi-hole integration for automatic DNS record management
- **Harbor Registry:** Private container registry with proxy cache for Docker Hub, Quay.io, etc.
- **CI/CD Ready:** GitLab integration, interview preparation environments
- **Robust Provisioning:**
  - Cloud-init for initial setup
  - Handles APT locks and unattended-upgrades gracefully
  - Idempotent Ansible playbooks for reliable re-runs

---

## Prerequisites

Before running the deployment, ensure you have the following:

**Software Dependencies:**
The `iac-wrapper.sh` script requires these tools on your local machine:

- `tofu`
- `ansible-playbook`
- `sops`
- `yq`
- `jq`
- `nc` (netcat)
- `python3`

**Infrastructure:**

1. **Proxmox VE:** A running Proxmox server.
2. **VM Template:** A prepared Ubuntu Cloud-Init VM template (e.g., ID `9420` as referenced in `variables.tf`).
3. **Pi-hole:** A running Pi-hole instance (e.g., at `10.10.10.100`) for internal DNS.
4. **Harbor:** A running Harbor instance (e.g., at `harbor.bevz.net`) for container proxy caching.
5. **S3 Backend:** An S3-compatible bucket (like MinIO) for storing Tofu state.
6. **SSH Key:** An SSH key pair for Ansible access (e.g., `cpc_deployment_key`).

---

## Directory Structure

```
platform-iac/
├── config/
│   ├── ansible.cfg            # Ansible configuration
│   ├── group_vars/            # Group variables for different VM types
│   ├── inventory/             # Static inventory definitions
│   ├── playbooks/             # Playbooks for all infrastructure types
│   ├── roles/                 # Reusable Ansible roles (K8s, databases, apps, etc.)
│   └── secrets/               # SOPS-encrypted secrets (Proxmox, MinIO, Harbor, etc.)
├── infra/                     # Terraform/OpenTofu projects
│   ├── dev/                   # Development environment
│   │   └── k8s-lab-01/       # Kubernetes cluster infrastructure
│   └── interview-prep/        # Interview preparation environments
│       ├── brainrocket-pxc/  # Percona XtraDB Cluster
│       └── softswiss-gitlab/ # GitLab instance
├── kubernetes/                # Kubernetes-specific manifests
│   ├── apps/                 # Application deployments
│   ├── cks-prep/             # CKS exam preparation examples
│   ├── exam-prep/            # General K8s exam resources
│   └── policies/             # Network policies, PSS, RBAC
├── modules/                   # Reusable Terraform modules
│   └── terraform/
│       └── proxmox-vm-cloudinit/  # Generic VM provisioning module
├── scripts/                   # Helper scripts
│   └── vm_template/          # VM template creation scripts
│       └── debian/           # Debian-based templates
└── tools/
    ├── iac-wrapper.sh        # Universal deployment orchestrator
    ├── tofu_inventory.py     # Dynamic inventory generator
    └── add_pihole_dns.py     # DNS automation for all VMs
```

---

## Configuration

### Global Configuration (`config/platform.conf`)

Core infrastructure settings (IPs, domains, SSH paths) are managed in `config/platform.conf`. This file is git-ignored for security.

```bash
cp config/platform.conf.example config/platform.conf
vim config/platform.conf
```

### Secrets Management (`sops`)

All secrets are managed by `sops` and stored in `config/secrets/`. The `iac-wrapper.sh` script automatically decrypts them in-memory for Tofu and Ansible.

- `config/secrets/proxmox/provider.sops.yml`: Holds Proxmox API and SSH credentials for Tofu.
- `config/secrets/minio/backend.sops.yml`: Holds AWS keys for the MinIO S3 Tofu state backend.
- `config/secrets/ansible/extra_vars.sops.yml`: Holds credentials for Ansible, primarily the `pihole.web_password` and `harbor.robot_token`.

Non-secret configuration (like IPs, VM specs, and domains) is managed in `infra/dev/k8s-lab-01/variables.tf` and Ansible `group_vars`.

---

## Usage

All operations are handled by the central `tools/iac-wrapper.sh` script.

**Note:** The environment (`dev`) and component (`k8s-lab-01`) are hardcoded in the script's examples but are required arguments.

### Full Deployment (Create and Configure)

This is the primary command. It creates the VMs, registers DNS, and runs the full Ansible configuration.

```bash
# Usage: ./tools/iac-wrapper.sh apply <env> <component>
./tools/iac-wrapper.sh apply dev k8s-lab-01
```

### Run Ansible Only (Configure Existing VMs)

If you have made a change to an Ansible role and want to re-run the configuration without destroying the VMs, use `configure`.
# Test diff

```bash
# Usage: ./tools/iac-wrapper.sh configure <env> <component> [limit]
./tools/iac-wrapper.sh configure dev k8s-lab-01
```

### Destroy Environment

This command will first run the `add_pihole_dns.py` script in `unregister-dns` mode to clean up Pi-hole, then call `tofu destroy`.

```bash
# Usage: ./tools/iac-wrapper.sh destroy <env> <component>
./tools/iac-wrapper.sh destroy dev k8s-lab-01
```

### Other Commands

- **`./tools/iac-wrapper.sh plan dev k8s-lab-01`**: Runs `tofu plan` to see infrastructure changes.
- **`./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 <playbook_name.yml> <limit>`**: Runs an ad-hoc playbook (e.g., `setup_dns.yml`) against the dynamic inventory.
- **`./tools/iac-wrapper.sh get-inventory dev k8s-lab-01`**: Caches and prints the dynamic JSON inventory.

## Testing & Validation

The project includes several layers of testing to ensure code quality and security:

### Static Analysis (Pre-commit)
Running automatically on commit or via `pre-commit run -a`:
- **Terraform:** `terraform fmt`, `tflint`, `tfsec` (Trivy)
- **Ansible:** `ansible-lint`
- **Shell:** `shellcheck`
- **Secrets:** `detect-secrets`

### Infrastructure Tests
- **Terraform Tests:** Native `terraform test` framework (coming soon)
- **Ansible Molecule:** Role testing in isolation (coming soon)

---

## Deployment Phased Flow

The `apply` command triggers the main `setup_k8s-lab-01.yml` playbook, which executes in distinct phases:

1. **Phase 1: Bootstrap Nodes (`k8s_bootstrap_node`)**
   - Waits for `apt` locks to be free (handles `unattended-upgrades`).
   - Disables swap.
   - Loads kernel modules (`overlay`, `br_netfilter`) and sets `sysctl` rules.
   - Installs `containerd`.
   - Configures `containerd` to use Harbor as a proxy mirror for all major registries.
   - Installs `kubelet`, `kubeadm`, and `kubectl`.
   - Copies CKS security profiles (AppArmor, Seccomp).

2. **Phase 2: Manage Cluster (`k8s_cluster_manager`)**
   - Runs `kubeadm init` on the control plane using a template that enables `serverTLSBootstrap: true`.
   - Copies `admin.conf` to user and root directories.
   - Fetches the `kubeadm join` command.
   - Runs `kubeadm join` on all worker nodes.
   - Creates the `registry-creds` secret (for Harbor) in `default` and `kube-system` namespaces.

3. **Phase 3: Deploy CNI (`cilium_install_helm`)**
   - Installs the `helm` binary on the control plane.
   - Adds the Cilium Helm repository.
   - Deploys the `cilium` chart into `kube-system` with `kubeProxyReplacement=true`.

4. **Phase 3.5: Verify Cluster**
   - Waits for all nodes to report `Ready` status.
   - Waits for all worker nodes to create `kubernetes.io/kubelet-serving` CSRs.
   - Approves all pending `kubelet-serving` CSRs.
   - Prints the final `kubectl get nodes -o wide` status.

5. **Phase 4: Deploy Security Tooling**
   - Installs the `falco` package on the control plane host (`k8s_master`).

<!-- end list -->

- Installs the `trivy` package on the control plane host.
  - Deploys the `trivy-operator` into the cluster via Helm.

- Documentation updated via worktree
