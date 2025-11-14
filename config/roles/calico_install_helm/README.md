# Role: calico_install_helm

## Description

Installs **Calico CNI** using Helm charts - provides production-grade networking and network security for Kubernetes with fine-grained configuration control, BGP routing, and advanced policy management.

## Requirements

- Kubernetes cluster v1.22+
- Helm 3 installed
- kubectl configured
- No existing CNI plugin

## Role Variables

### defaults/main.yml

```yaml
# Calico Helm repository
calico_helm_repo_url: "https://docs.tigera.io/calico/charts"

# Calico version
calico_version: "v3.28.0"

# Namespace
calico_namespace: "calico-system"

# Pod CIDR
pod_cidr: "192.168.0.0/16"
```

## Example Playbook

```yaml
---
- name: Install Calico via Helm
  hosts: k8s_master
  become: yes
  roles:
    - calico_install_helm
```

## Features

- **Helm-based configuration**
- **Production-ready defaults**
- **Easy version management**
- **Custom values support**

## Related Roles

- **calico_install_manifest**: Manifest-based alternative

## References

- [Calico Helm Charts](https://docs.tigera.io/calico/latest/getting-started/kubernetes/helm)

## Author

Platform Infrastructure Team

## License

Internal use only.
