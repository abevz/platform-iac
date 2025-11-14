# Role: calico_install

## Description

Alternative Calico CNI installation method using Kubernetes manifests with custom configuration. Provides flexibility for specific Calico deployment scenarios.

## Requirements

- Kubernetes cluster v1.22+
- kubectl configured
- No existing CNI plugin

## Role Variables

### defaults/main.yml

```yaml
# Calico manifest URL
calico_manifest_url: "https://docs.projectcalico.org/manifests/calico.yaml"

# Pod CIDR
pod_cidr: "192.168.0.0/16"
```

## Example Playbook

```yaml
---
- name: Install Calico CNI
  hosts: k8s_master
  become: yes
  roles:
    - calico_install
```

## Features

- **Direct manifest application**
- **Lightweight installation**
- **Standard Calico features**

## Post-Installation

```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Verify nodes Ready
kubectl get nodes
```

## Related Roles

- **calico_install_manifest**: Operator-based installation (recommended)
- **calico_install_helm**: Helm-based installation

## References

- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)

## Author

Platform Infrastructure Team

## License

Internal use only.
