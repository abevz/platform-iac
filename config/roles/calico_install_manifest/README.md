# Role: calico_install_manifest

## Description

Installs **Calico** - a popular Container Network Interface (CNI) plugin using Kubernetes manifests. Calico provides networking and network security for Kubernetes clusters with support for NetworkPolicies, BGP routing, and high-performance data plane using standard Linux networking.

## Requirements

- Kubernetes cluster v1.22+ with control plane initialized
- kubectl configured on control plane
- No existing CNI plugin installed
- Pod CIDR must be configured (default: `192.168.0.0/16`)

## Role Variables

### defaults/main.yml

```yaml
# Calico Operator manifest URL
calico_operator_manifest_url: "https://docs.tigera.io/calico/latest/manifests/tigera-operator.yaml"

# Calico custom resources manifest URL
calico_cr_manifest_url: "https://docs.tigera.io/calico/latest/manifests/custom-resources.yaml"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `calico` | All Calico tasks |

## Dependencies

- **k8s_cluster_manager**: Cluster must be initialized first

## Example Playbook

### Basic Installation

```yaml
---
- name: Install Calico CNI
  hosts: k8s_master
  become: yes
  roles:
    - calico_install_manifest
```

### Declarative Install/Uninstall

```yaml
# Install Calico
- hosts: k8s_master
  become: yes
  roles:
    - role: calico_install_manifest
      vars:
        addon_state: present

# Uninstall Calico
- hosts: k8s_master
  become: yes
  roles:
    - role: calico_install_manifest
      vars:
        addon_state: absent
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Apply Calico Operator Manifest │
│ (tigera-operator)               │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Apply Custom Resources          │
│ (Installation CR)               │
│ - Pod CIDR: 192.168.0.0/16      │
│ - IPIP encapsulation            │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Wait for Deployments Ready      │
│ (calico-system namespace)       │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Wait for DaemonSet Ready        │
│ (calico-node on all nodes)      │
└─────────────────────────────────┘
```

## Post-Installation Verification

```bash
# Check Calico pods
kubectl get pods -n calico-system

# Expected:
# calico-kube-controllers-xxx   1/1   Running
# calico-node-xxx               1/1   Running
# calico-typha-xxx              1/1   Running

# Check nodes are Ready
kubectl get nodes

# Test connectivity
kubectl run test-pod --image=busybox --restart=Never -- sleep 3600
kubectl exec test-pod -- ping -c 4 8.8.8.8
```

## Features

- **NetworkPolicy enforcement**
- **IPIP or VXLAN encapsulation**
- **BGP routing (optional)**
- **Wireguard encryption (optional)**

## Related Roles

- **k8s_cluster_manager**: Cluster initialization
- **calico_install_helm**: Helm-based alternative

## References

- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)

## Changelog

- **2025-11**: Initial manifest-based installation

## Author

Platform Infrastructure Team

## License

Internal use only.
