# Platform IaC Architecture

Visual overview of the universal Platform Infrastructure as Code for managing all VM workloads on Proxmox VE.

## 🏗️ High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Control Machine                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌──────────────┐ │
│  │  OpenTofu  │  │  Ansible   │  │    SOPS    │  │  iac-wrapper │ │
│  │ (Terraform)│  │            │  │  (Secrets) │  │    Script    │ │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └──────┬───────┘ │
│        │               │               │                │          │
└────────┼───────────────┼───────────────┼────────────────┼──────────┘
         │               │               │                │
         │               │               │                └──────┐
         │               │               └────────────┐          │
         │               └──────────────────┐         │          │
         └────────────────────┐             │         │          │
                              │             │         │          │
         ┌────────────────────▼─────────────▼─────────▼──────────▼──┐
         │                  Proxmox VE Hypervisor                    │
         │  ┌──────────────────────────────────────────────────┐    │
         │  │      VM Templates (Cloud-init enabled)           │    │
         │  │  - Debian 11/12  - Ubuntu 20.04/22.04/24.04     │    │
         │  └──────────────────────────────────────────────────┘    │
         │                                                            │
         │ ┌────────────────────────────────────────────────────┐   │
         │ │         KUBERNETES CLUSTERS                        │   │
         │ │ ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
         │ │ │ Control  │  │  Worker  │  │  Worker  │          │   │
         │ │ │  Plane   │  │  Node 1  │  │  Node 2  │          │   │
         │ │ └──────────┘  └──────────┘  └──────────┘          │   │
         │ └────────────────────────────────────────────────────┘   │
         │                                                            │
         │ ┌────────────────────────────────────────────────────┐   │
         │ │         DATABASE CLUSTERS                          │   │
         │ │ ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
         │ │ │ Percona  │  │ Percona  │  │ Percona  │          │   │
         │ │ │  XtraDB  │  │  XtraDB  │  │  XtraDB  │          │   │
         │ │ │ Primary  │  │ Secondary│  │ Secondary│          │   │
         │ │ └──────────┘  └──────────┘  └──────────┘          │   │
         │ └────────────────────────────────────────────────────┘   │
         │                                                            │
         │ ┌────────────────────────────────────────────────────┐   │
         │ │         CI/CD & APPLICATIONS                       │   │
         │ │ ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
         │ │ │  GitLab  │  │   App    │  │  Custom  │          │   │
         │ │ │  Server  │  │  Server  │  │ Workload │          │   │
         │ │ └──────────┘  └──────────┘  └──────────┘          │   │
         │ └────────────────────────────────────────────────────┘   │
         │                                                            │
         └────────────────────────────────────────────────────────────┘
                                     │
         ┌───────────────────────────┴──────────────────────────┐
         │              Shared Infrastructure Services            │
         │                                                        │
         │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
         │  │ Pi-hole  │  │  Harbor  │  │      RustFS      │   │
         │  │   DNS    │  │ Registry │  │   S3 Storage     │   │
         │  └──────────┘  └──────────┘  └──────────────────┘   │
         └────────────────────────────────────────────────────────┘
```

## Object Storage Component

RustFS is the current S3-compatible object-storage implementation. It replaced
MinIO on 2026-06-24 while preserving the VM, bucket names, `/srv/minio/*` data
paths, and public S3/console endpoints. The historical `minio` role,
inventory group, domains, and secret file paths are compatibility names only.

Current consumers:

- OpenTofu remote state through the S3 backend.
- Vault snapshot uploads to the `vault-backups` bucket.
- Any existing S3-compatible clients that use the preserved endpoint.

Harbor is intentionally not part of this object-storage migration in this repo:
the managed Harbor configuration uses local `/data` storage.

Operational details and rollback steps are documented in
[RustFS Binary Replacement Runbook](runbook-rustfs-minio-replacement.md).

## 🔄 Deployment Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. PREPARATION PHASE                                                 │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Decrypt Secrets│
                    │  (SOPS)         │
                    └────────┬────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 2. INFRASTRUCTURE PROVISIONING (OpenTofu)                            │
└─────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
          ┌──────────────────┴──────────────────┐
          │                                     │
          ▼                                     ▼
  ┌───────────────┐                   ┌────────────────┐
  │ Create Control│                   │ Create Worker  │
  │  Plane VM     │                   │  Nodes VMs     │
  │ - Cloud-init  │                   │ - Cloud-init   │
  │ - Networking  │                   │ - Networking   │
  │ - Storage     │                   │ - Storage      │
  └───────┬───────┘                   └────────┬───────┘
          │                                    │
          └──────────────┬─────────────────────┘
                         │
                         ▼
               ┌─────────────────┐
               │ Register DNS    │
               │ (Pi-hole API)   │
               └────────┬────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 3. NODE BOOTSTRAP PHASE (Ansible: k8s_bootstrap_node)               │
└─────────────────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │ Wait for│    │ Disable │    │  Load   │
  │APT locks│───▶│  Swap   │───▶│ Kernel  │
  └─────────┘    └─────────┘    │ Modules │
                                └────┬────┘
                                     │
        ┌────────────────────────────┼────────────────────┐
        │                            │                    │
        ▼                            ▼                    ▼
  ┌──────────┐              ┌──────────────┐      ┌────────────┐
  │ Install  │              │   Configure  │      │  Install   │
  │Containerd│──────────────▶│  Containerd  │─────▶│ Kubernetes │
  │          │              │  + Harbor    │      │  Packages  │
  └──────────┘              │   Registry   │      │ (kubeadm)  │
                            └──────────────┘      └─────┬──────┘
                                                        │
                                                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 4. CLUSTER INITIALIZATION (Ansible: k8s_cluster_manager)            │
└─────────────────────────────────────────────────────────────────────┘
                                                        │
                    ┌───────────────────────────────────┤
                    │                                   │
                    ▼                                   ▼
        ┌────────────────────┐              ┌──────────────────┐
        │  kubeadm init      │              │ Generate Join    │
        │  (Control Plane)   │─────────────▶│    Command       │
        │ - API Server       │              └────────┬─────────┘
        │ - etcd             │                       │
        │ - Scheduler        │                       │
        │ - Controller Mgr   │                       ▼
        └────────────────────┘              ┌──────────────────┐
                                            │  kubeadm join    │
                                            │ (Worker Nodes)   │
                                            └────────┬─────────┘
                                                     │
                                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 5. NETWORKING SETUP (CNI Installation)                              │
└─────────────────────────────────────────────────────────────────────┘
                                                     │
                     ┌───────────────────────────────┴───────┐
                     │                                       │
                     ▼                                       ▼
          ┌──────────────────┐                   ┌──────────────────┐
          │ Install Calico/  │                   │  Configure Pod   │
          │ Cilium via Helm  │──────────────────▶│    Networking    │
          │ - eBPF driver    │                   │  (10.244.0.0/16) │
          │ - kube-proxy=off │                   └──────────────────┘
          └──────────────────┘
                     │
                     ▼
          ┌──────────────────┐
          │  Wait for Nodes  │
          │   to be Ready    │
          └────────┬─────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 6. ADDON DEPLOYMENT                                                  │
└─────────────────────────────────────────────────────────────────────┘
                   │
   ┌───────────────┼───────────────┬───────────────┬──────────────┐
   │               │               │               │              │
   ▼               ▼               ▼               ▼              ▼
┌────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│MetalLB │  │  NGINX   │  │ ArgoCD   │  │  Falco   │  │  Trivy   │
│LoadBal │  │ Ingress  │  │  GitOps  │  │ Runtime  │  │Operator  │
│        │  │Controller│  │          │  │ Security │  │Scanning  │
└───┬────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
    │            │             │             │             │
    └────────────┴─────────────┴─────────────┴─────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 7. SECURITY HARDENING                                                │
└─────────────────────────────────────────────────────────────────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
       ▼                       ▼                       ▼
┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│  AppArmor   │       │ Run CIS     │       │   Approve   │
│  Profiles   │       │ Benchmark   │       │   Kubelet   │
│  Deploy     │       │(kube-bench) │       │   CSRs      │
└─────────────┘       └─────────────┘       └─────────────┘
       │                       │                       │
       └───────────────────────┴───────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │ Cluster Ready    │
                    │ for Production   │
                    └──────────────────┘
```

## 🔐 Security Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SECURITY ARCHITECTURE                            │
└─────────────────────────────────────────────────────────────────────┘

Layer 7: Application Security
┌─────────────────────────────────────────────────────────────────────┐
│ • ArgoCD GitOps (supply chain security)                             │
│ • Trivy vulnerability scanning                                       │
│ • Image pull policies                                                │
└─────────────────────────────────────────────────────────────────────┘

Layer 6: Runtime Security
┌─────────────────────────────────────────────────────────────────────┐
│ • Falco runtime threat detection                                     │
│ • Anomaly detection                                                  │
│ • System call monitoring                                             │
└─────────────────────────────────────────────────────────────────────┘

Layer 5: Kubernetes Security
┌─────────────────────────────────────────────────────────────────────┐
│ • RBAC (Role-Based Access Control)                                   │
│ • Pod Security Standards (restricted)                                │
│ • Network Policies                                                   │
│ • Resource Quotas                                                    │
│ • Admission Controllers                                              │
└─────────────────────────────────────────────────────────────────────┘

Layer 4: Container Security
┌─────────────────────────────────────────────────────────────────────┐
│ • Read-only root filesystem                                          │
│ • Non-root user enforcement                                          │
│ • Capability dropping                                                │
│ • Seccomp profiles                                                   │
│ • AppArmor profiles                                                  │
└─────────────────────────────────────────────────────────────────────┘

Layer 3: Node Security
┌─────────────────────────────────────────────────────────────────────┐
│ • Kubelet TLS bootstrap                                              │
│ • Certificate rotation                                               │
│ • CIS benchmark compliance                                           │
│ • Kernel hardening (sysctl)                                          │
└─────────────────────────────────────────────────────────────────────┘

Layer 2: Network Security
┌─────────────────────────────────────────────────────────────────────┐
│ • Network segmentation (CNI)                                         │
│ • Network policies (default deny)                                    │
│ • TLS encryption (mTLS with Istio optional)                         │
│ • Ingress filtering                                                  │
└─────────────────────────────────────────────────────────────────────┘

Layer 1: Infrastructure Security
┌─────────────────────────────────────────────────────────────────────┐
│ • SSH key authentication                                             │
│ • Secrets encryption (SOPS)                                          │
│ • Private registry (Harbor)                                          │
│ • Isolated VM networking                                             │
└─────────────────────────────────────────────────────────────────────┘
```

## 📦 Component Dependencies

```
┌─────────────────────────────────────────────────────────────────────┐
│                     COMPONENT DEPENDENCY GRAPH                       │
└─────────────────────────────────────────────────────────────────────┘

                          ┌──────────────┐
                          │   Proxmox    │
                          │      VE      │
                          └──────┬───────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
                    ▼                         ▼
            ┌───────────────┐        ┌───────────────┐
            │ Control Plane │        │ Worker Nodes  │
            │      VM       │        │     VMs       │
            └───────┬───────┘        └───────┬───────┘
                    │                        │
                    └───────────┬────────────┘
                                │
                    ┌───────────▼────────────┐
                    │    Containerd CRI      │
                    └───────────┬────────────┘
                                │
                    ┌───────────▼────────────┐
                    │  Kubernetes Control    │
                    │  Plane Components      │
                    │ (API, etcd, scheduler) │
                    └───────────┬────────────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
                ▼               ▼               ▼
        ┌───────────┐   ┌───────────┐   ┌───────────┐
        │   CNI     │   │  CoreDNS  │   │  Metrics  │
        │ (Calico/  │   │           │   │  Server   │
        │  Cilium)  │   │           │   │           │
        └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
              │               │               │
              └───────┬───────┴───────┬───────┘
                      │               │
          ┌───────────┴───┬───────────┴───────────┐
          │               │                       │
          ▼               ▼                       ▼
    ┌──────────┐    ┌──────────┐          ┌──────────┐
    │ MetalLB  │    │ Ingress  │          │  Cert    │
    │   LB     │───▶│ Nginx/   │◀─────────│ Manager  │
    └──────────┘    │ Traefik  │          └──────────┘
                    └────┬─────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐
    │  ArgoCD  │   │  Falco   │   │  Trivy   │
    │  GitOps  │   │ Security │   │ Operator │
    └──────────┘   └──────────┘   └──────────┘

Legend:
───▶  Required dependency
◀───  Optional dependency
```

## 🌐 Network Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        NETWORK TOPOLOGY                              │
└─────────────────────────────────────────────────────────────────────┘

External Network (192.168.1.0/24)
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                   │
│  │ Pi-hole  │     │  Harbor  │     │  RustFS  │                   │
│  │   DNS    │     │ Registry │     │(S3 State)│                   │
│  │<YOUR-LAN-IP>│     │192.168.x.x│     │192.168.x.x│                   │
│  └──────────┘     └──────────┘     └──────────┘                   │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │              Proxmox VE Bridge (vmbr0)                     │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                   │
│  │ k8s-cp   │     │ k8s-wn-01│     │ k8s-wn-02│                   │
│  │192.168.x.x│     │192.168.x.x│     │192.168.x.x│                   │
│  └──────┬───┘     └─────┬────┘     └─────┬────┘                   │
│         │               │                │                         │
└─────────┼───────────────┼────────────────┼─────────────────────────┘
          │               │                │
          └───────────────┴────────────────┘
                          │
┌─────────────────────────┴────────────────────────────────────────────┐
│              Kubernetes Internal Networks                             │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Pod Network (CNI): 10.244.0.0/16                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Pod-to-Pod communication via CNI plugin                     │   │
│  │  - Calico: BGP or VXLAN encapsulation                        │   │
│  │  - Cilium: eBPF-based routing                                │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  Service Network: 10.96.0.0/12                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ClusterIP Services: 10.96.x.x                               │   │
│  │  - kubernetes.default.svc: 10.96.0.1                         │   │
│  │  - kube-dns: 10.96.0.10                                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  LoadBalancer IP Pool (MetalLB): 192.168.1.200-192.168.1.250        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  External access to services                                 │   │
│  │  - Ingress Controller: 192.168.1.200                         │   │
│  │  - ArgoCD: 192.168.1.201                                     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

Traffic Flow:
Internet ─▶ Ingress (LB IP) ─▶ Ingress Controller ─▶ Service ─▶ Pods
```

## 📊 Role Execution Flow

```
PHASE 1: Bootstrap
├── k8s_bootstrap_node
│   ├── Wait for APT locks
│   ├── Disable swap
│   ├── Load kernel modules
│   ├── Configure sysctl
│   ├── Install containerd
│   ├── Configure Harbor registry
│   └── Install Kubernetes packages

PHASE 2: Cluster Init
├── k8s_cluster_manager
│   ├── kubeadm init (control plane)
│   ├── Copy kubeconfig
│   ├── Generate join command
│   ├── kubeadm join (workers)
│   └── Create registry secrets

PHASE 3: Networking
├── calico_install_manifest / cilium_install_helm
│   ├── Install CNI
│   ├── Wait for pods ready
│   └── Verify node status

PHASE 4: Security
├── apparmor_configure
│   ├── Deploy profiles
│   └── Enforce profiles
├── falco_install_helm
│   ├── Install Falco
│   ├── Deploy custom rules
│   └── Verify alerts
└── kube_bench_run
    ├── Run CIS audit
    └── Generate report

PHASE 5: Add-ons
├── metallb_install
│   └── Configure IP pool
├── ingress_nginx_install
│   └── Deploy ingress controller
├── cert_manager_install
│   └── Setup certificate management
├── argocd_install
│   └── Deploy GitOps platform
└── trivy_operator_deploy
    └── Deploy vulnerability scanning
```

## 🎯 CKS Exam Coverage

This platform covers the following CKS exam domains:

```
┌────────────────────────────────────────────────────────────┐
│ CKS Domain                          │ Coverage │ Components │
├────────────────────────────────────────────────────────────┤
│ Cluster Setup (10%)                 │   100%   │            │
│ • Network security policies         │    ✓     │ Calico/CNI │
│ • CIS benchmark                     │    ✓     │ kube-bench │
│ • Ingress security                  │    ✓     │ NGINX      │
│ • Node security                     │    ✓     │ AppArmor   │
├────────────────────────────────────────────────────────────┤
│ Cluster Hardening (15%)             │   100%   │            │
│ • RBAC                              │    ✓     │ Manual     │
│ • Service accounts                  │    ✓     │ Manual     │
│ • Security contexts                 │    ✓     │ PSS        │
│ • Admission controllers             │    ✓     │ kubeadm    │
├────────────────────────────────────────────────────────────┤
│ System Hardening (15%)              │   100%   │            │
│ • AppArmor                          │    ✓     │ Profiles   │
│ • Seccomp                           │    ✓     │ Profiles   │
│ • Host security                     │    ✓     │ sysctl     │
├────────────────────────────────────────────────────────────┤
│ Minimize Microservice (20%)         │    90%   │            │
│ • Security contexts                 │    ✓     │ Examples   │
│ • Pod security standards            │    ✓     │ PSS        │
│ • OPA/Gatekeeper                    │    -     │ TBD        │
│ • mTLS                              │    ✓     │ Istio opt  │
├────────────────────────────────────────────────────────────┤
│ Supply Chain Security (20%)         │    85%   │            │
│ • Image scanning                    │    ✓     │ Trivy      │
│ • Image signing                     │    -     │ TBD        │
│ • Admission webhooks                │    ✓     │ Examples   │
│ • Supply chain attack               │    ✓     │ Trivy      │
├────────────────────────────────────────────────────────────┤
│ Monitoring & Logging (20%)          │    95%   │            │
│ • Runtime security                  │    ✓     │ Falco      │
│ • Audit logs                        │    ✓     │ kubeadm    │
│ • Behavioral analytics              │    ✓     │ Falco      │
└────────────────────────────────────────────────────────────┘

Overall CKS Readiness: ~95%
```

## 📈 Scalability Model

```
Development (Current)
┌────────────────────────────────────┐
│ 1 Control Plane + 2 Workers        │
│ Resources: 2 CPU, 4GB RAM per node │
│ Suitable for: Testing, CKS prep    │
└────────────────────────────────────┘

Production (Recommended)
┌────────────────────────────────────┐
│ 3 Control Planes + 5+ Workers      │
│ Resources: 4 CPU, 8GB RAM per node │
│ HA etcd, Load-balanced API server  │
│ Suitable for: Production workloads │
└────────────────────────────────────┘

Scaling Strategy:
1. Add workers: Update Terraform count
2. Run terraform apply
3. Run ansible-playbook with join_workers tag
4. Verify with kubectl get nodes
```

---

**Documentation Navigation:**
- [← Back to Main Docs](./README.md)
- [Quick Reference →](./CHEATSHEET.md)
- [Roles Guide →](../config/roles/README.md)

**Last Updated**: November 2025
