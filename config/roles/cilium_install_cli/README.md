# Role: cilium_install_cli

## Description

Installs **Cilium CLI** tool for managing Cilium CNI without Helm. Provides direct installation using Cilium CLI with simplified configuration for quick deployments and testing environments.

## Requirements

- Kubernetes cluster v1.22+
- Linux kernel 4.19+
- kubectl configured
- No existing CNI plugin

## Role Variables

### defaults/main.yml

```yaml
# Cilium CLI installation path
cilium_cli_path: "/usr/local/bin/cilium"

# Installation method: cli
cilium_install_method: "cli"
```

## Example Playbook

```yaml
---
- name: Install Cilium via CLI
  hosts: k8s_master
  become: yes
  roles:
    - cilium_install_cli
```

## Installation

The role installs Cilium CLI from GitHub releases and uses it to deploy Cilium:

```bash
# CLI automatically downloads and installs
cilium install

# Check status
cilium status
```

## Features

- **Simple installation**: No Helm required
- **Quick setup**: Fast deployment for dev/test
- **CLI management**: Built-in troubleshooting commands

## Post-Installation

```bash
# Verify installation
cilium status

# Run connectivity test
cilium connectivity test

# Enable Hubble
cilium hubble enable
```

## Related Roles

- **cilium_install_helm**: Production Helm-based installation

## References

- [Cilium CLI](https://github.com/cilium/cilium-cli)

## Author

Platform Infrastructure Team

## License

Internal use only.
