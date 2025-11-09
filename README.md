# platform-iac

## Overview

`platform-iac` is a comprehensive **Infrastructure as Code (IaC)** and **Configuration Management (CM)** solution for deploying a hardened, CKS-ready (Certified Kubernetes Security Specialist) Kubernetes lab on **Proxmox VE**.

This project uses a hybrid approach:

  * **[OpenTofu](https://opentofu.org/)** (Terraform) provisions the virtual machines, storage, and networking on Proxmox.
  * **[Ansible](https://www.ansible.com/)** performs the complete system configuration, from bootstrapping nodes to deploying security tooling.

The entire process is orchestrated by a master wrapper script (`tools/iac-wrapper.sh`) for seamless, one-command deployment.

## Features

  * **Infrastructure as Code:** Fully automated VM provisioning on Proxmox VE using Tofu.
  * **Dynamic Inventory:** Tofu automatically generates an Ansible inventory, which is read by a Python script, eliminating manual inventory management.
  * **Secure Secret Management:** All secrets (API keys, tokens, passwords) are encrypted using **`sops`**.
  * **Automated DNS:** The `iac-wrapper.sh` script automatically registers the new VMs with a Pi-hole DNS server via its API.
  * **Harbor Proxy Cache:** All nodes are configured to use a central Harbor registry as a pull-through cache for `docker.io`, `quay.io`, `registry.k8s.io`, etc., saving bandwidth and improving reliability.
  * **CKS Hardening:**
      * **CNI:** Deploys **Cilium** via Helm.
      * **Security Tooling:** Installs **Falco** (package) and **Trivy** (package + operator).
      * **Kubelet Security:** Automatically enables `serverTLSBootstrap: true` in `kubeadm` for secure API server-to-kubelet communication and auto-approves the resulting CSRs.
      * **Kernel Security:** Deploys custom **AppArmor** and **Seccomp** profiles to nodes.
  * **Robust Provisioning:**
      * `cloud-init` handles initial node setup, including correct `systemd-resolved` configuration to fix common DNS `SERVFAIL` errors.
      * Ansible playbook gracefully waits for `unattended-upgrades` (apt locks) to finish before proceeding, preventing race conditions.

-----

## Prerequisites

Before running the deployment, ensure you have the following:

**Software Dependencies:**
The `iac-wrapper.sh` script requires these tools on your local machine:

  * `tofu`
  * `ansible-playbook`
  * `sops`
  * `yq`
  * `jq`
  * `nc` (netcat)
  * `python3`

**Infrastructure:**

1.  **Proxmox VE:** A running Proxmox server.
2.  **VM Template:** A prepared Ubuntu Cloud-Init VM template (e.g., ID `9420` as referenced in `variables.tf`).
3.  **Pi-hole:** A running Pi-hole instance (e.g., at `10.10.10.100`) for internal DNS.
4.  **Harbor:** A running Harbor instance (e.g., at `harbor.bevz.net`) for container proxy caching.
5.  **S3 Backend:** An S3-compatible bucket (like MinIO) for storing Tofu state.
6.  **SSH Key:** An SSH key pair for Ansible access (e.g., `cpc_deployment_key`).

-----

## Directory Structure

```
platform-iac/
├── config/
│   ├── ansible.cfg            # Ansible configuration
│   ├── group_vars/            # Group variables (e.g., k8s_master.yml)
│   ├── inventory/             # Static inventory (for localhost tasks)
│   ├── playbooks/             # Main playbooks (e.g., setup_k8s-lab-01.yml)
│   ├── roles/                 # All Ansible logic (k8s_bootstrap_node, cilium_install_helm, etc.)
│   └── secrets/               # SOPS-encrypted secret files
├── infra/
│   └── dev/
│       └── k8s-lab-01/        # Tofu project for the k8s-lab-01 environment
├── kubernetes/
│   └── cks-prep/              # Manifests for CKS security examples
└── tools/
    ├── iac-wrapper.sh         # Master orchestration script
    ├── tofu_inventory.py      # Tofu dynamic inventory script
    └── add_pihole_dns.py      # Pi-hole integration script
```

-----

## Configuration

All secrets are managed by `sops` and stored in `config/secrets/`. The `iac-wrapper.sh` script automatically decrypts them in-memory for Tofu and Ansible.

  * `config/secrets/proxmox/provider.sops.yml`: Holds Proxmox API and SSH credentials for Tofu.
  * `config/secrets/minio/backend.sops.yml`: Holds AWS keys for the MinIO S3 Tofu state backend.
  * `config/secrets/ansible/extra_vars.sops.yml`: Holds credentials for Ansible, primarily the `pihole.web_password` and `harbor.robot_token`.

Non-secret configuration (like IPs, VM specs, and domains) is managed in `infra/dev/k8s-lab-01/variables.tf` and Ansible `group_vars`.

-----

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

  * **`./tools/iac-wrapper.sh plan dev k8s-lab-01`**: Runs `tofu plan` to see infrastructure changes.
  * **`./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 <playbook_name.yml> <limit>`**: Runs an ad-hoc playbook (e.g., `setup_dns.yml`) against the dynamic inventory.
  * **`./tools/iac-wrapper.sh get-inventory dev k8s-lab-01`**: Caches and prints the dynamic JSON inventory.

-----

## Deployment Phased Flow

The `apply` command triggers the main `setup_k8s-lab-01.yml` playbook, which executes in distinct phases:

1.  **Phase 1: Bootstrap Nodes (`k8s_bootstrap_node`)**

      * Waits for `apt` locks to be free (handles `unattended-upgrades`).
      * Disables swap.
      * Loads kernel modules (`overlay`, `br_netfilter`) and sets `sysctl` rules.
      * Installs `containerd`.
      * Configures `containerd` to use Harbor as a proxy mirror for all major registries.
      * Installs `kubelet`, `kubeadm`, and `kubectl`.
      * Copies CKS security profiles (AppArmor, Seccomp).

2.  **Phase 2: Manage Cluster (`k8s_cluster_manager`)**

      * Runs `kubeadm init` on the control plane using a template that enables `serverTLSBootstrap: true`.
      * Copies `admin.conf` to user and root directories.
      * Fetches the `kubeadm join` command.
      * Runs `kubeadm join` on all worker nodes.
      * Creates the `registry-creds` secret (for Harbor) in `default` and `kube-system` namespaces.

3.  **Phase 3: Deploy CNI (`cilium_install_helm`)**

      * Installs the `helm` binary on the control plane.
      * Adds the Cilium Helm repository.
      * Deploys the `cilium` chart into `kube-system` with `kubeProxyReplacement=true`.

4.  **Phase 3.5: Verify Cluster**

      * Waits for all nodes to report `Ready` status.
      * Waits for all worker nodes to create `kubernetes.io/kubelet-serving` CSRs.
      * Approves all pending `kubelet-serving` CSRs.
      * Prints the final `kubectl get nodes -o wide` status.

5.  **Phase 4: Deploy Security Tooling**

      * Installs the `falco` package on the control plane host (`k8s_master`).

<!-- end list -->

  * Installs the `trivy` package on the control plane host.
      * Deploys the `trivy-operator` into the cluster via Helm.
