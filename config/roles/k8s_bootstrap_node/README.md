# Role: k8s_bootstrap_node

## Description

Bootstrap Kubernetes nodes by installing and configuring all required components including containerd runtime, Kubernetes packages, and system prerequisites. This role prepares both control plane and worker nodes for cluster initialization.

## Supported Operating Systems

- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Rocky Linux 8/9

## Requirements

- Root or sudo access
- Internet connectivity for package downloads
- Minimum 2GB RAM, 2 CPU cores
- Disabled swap

## Role Variables

### Required Variables

None - all variables have sensible defaults.

### Optional Variables (defaults/main.yml)

```yaml
# Kubernetes version to install
k8s_short_version: "1.33"
k8s_long_version_debian: "1.33.0-1.1"
k8s_long_version_redhat: "1.33.0"

# Harbor registry authentication (set in group_vars)
harbor_url: "harbor.example.com"
harbor_robot_username: "robot$deployer"
harbor_robot_token: ""  # Provided via vault/env
```

### Computed Variables

```yaml
# Automatically encoded Harbor auth
harbor_auth: "{{ [harbor_robot_username, harbor_robot_token] | join(':') | b64encode }}"
```

## Tags

| Tag | Purpose | Tasks Affected |
|-----|---------|----------------|
| `bootstrap_prereqs` | System prerequisites and package updates | APT/DNF cache, swap disable, kernel modules |
| `containerd` | Containerd runtime installation | Download, configure, and start containerd |
| `k8s_packages` | Kubernetes component installation | Install kubelet, kubeadm, kubectl |
| `always` | Tasks that run regardless of tags | Lock waiting, variable setup |

## Dependencies

None - this is a base role.

## Example Playbook

### Basic Usage

```yaml
---
- name: Bootstrap Kubernetes Nodes
  hosts: k8s_master:k8s_worker
  become: yes
  roles:
    - k8s_bootstrap_node
```

### With Custom Variables

```yaml
---
- name: Bootstrap Kubernetes 1.32
  hosts: k8s_nodes
  become: yes
  vars:
    k8s_short_version: "1.32"
    k8s_long_version_debian: "1.32.0-1.1"
  roles:
    - k8s_bootstrap_node
```

### Using Tags

```yaml
# Only install containerd
ansible-playbook playbook.yml --tags containerd

# Install everything except k8s packages
ansible-playbook playbook.yml --skip-tags k8s_packages

# Run only prerequisites
ansible-playbook playbook.yml --tags bootstrap_prereqs
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Wait for Package Manager Locks │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Encode Harbor Credentials       │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ System Prerequisites            │
│ - Update package cache          │
│ - Disable swap                  │
│ - Load kernel modules           │
│ - Configure sysctl              │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install Containerd              │
│ - Download binary               │
│ - Extract to /usr/local/bin     │
│ - Configure CRI settings        │
│ - Create systemd service        │
│ - Start and enable service      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install Kubernetes Packages     │
│ - Add Kubernetes APT/YUM repo   │
│ - Install kubelet               │
│ - Install kubeadm               │
│ - Install kubectl               │
│ - Hold package versions         │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Configure Crictl                │
│ - Set containerd endpoint       │
└─────────────────────────────────┘
```

## Files and Templates

### templates/containerd-config.toml.j2

Containerd configuration with:
- CRI plugin enabled
- SystemdCgroup enabled
- Harbor registry authentication
- Custom sandbox (pause) image

```toml
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.10"
  
[plugins."io.containerd.grpc.v1.cri".registry.configs."{{ harbor_url }}".auth]
  auth = "{{ harbor_auth }}"
```

### files/containerd.service

Systemd unit for containerd service.

### files/crictl.yaml

Crictl configuration for container runtime CLI.

## Handler Definitions

Located in `handlers/main.yml`:

```yaml
- name: Restart containerd
  systemd:
    name: containerd
    state: restarted
    daemon_reload: yes
```

## Post-Installation Verification

### Check Containerd Status

```bash
systemctl status containerd
```

### Verify Kubernetes Packages

```bash
dpkg -l | grep -E 'kubelet|kubeadm|kubectl'  # Debian/Ubuntu
rpm -qa | grep -E 'kubelet|kubeadm|kubectl'  # Rocky Linux
```

### Test Crictl

```bash
crictl info
crictl images
```

### Verify Kernel Modules

```bash
lsmod | grep -E 'overlay|br_netfilter'
```

### Check Sysctl Settings

```bash
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward
```

## Troubleshooting

### Issue: APT Lock Errors

**Symptom**: Task fails with "Could not get lock /var/lib/dpkg/lock-frontend"

**Solution**: Role automatically waits up to 3 minutes for locks to release. If persistent:

```bash
# Manual cleanup (not recommended)
sudo rm /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a
```

### Issue: Containerd Fails to Start

**Symptom**: `systemctl status containerd` shows failed state

**Solution**: Check logs and configuration:

```bash
journalctl -u containerd -n 50
containerd config dump  # Verify config syntax
```

### Issue: Harbor Authentication Fails

**Symptom**: Cannot pull images from private registry

**Solution**: Verify credentials:

```bash
# Test Harbor auth manually
crictl pull harbor.example.com/library/nginx:latest

# Check encoded auth
ansible -i inventory.ini all -m debug -a "var=harbor_auth"
```

### Issue: Kubernetes Packages Not Found

**Symptom**: Package manager cannot find kubelet/kubeadm/kubectl

**Solution**: Verify repository configuration:

```bash
# Debian/Ubuntu
cat /etc/apt/sources.list.d/kubernetes.list
apt update && apt-cache policy kubelet

# Rocky Linux
cat /etc/yum.repos.d/kubernetes.repo
dnf list kubelet --showduplicates
```

## Security Considerations

### Swap Disabled

Kubernetes requires swap to be disabled for performance and stability. This role:
- Disables swap immediately: `swapoff -a`
- Comments out swap entries in `/etc/fstab`

### Kernel Parameters

Required sysctl settings for Kubernetes networking:

```bash
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

### Container Runtime Security

- Containerd runs with SystemdCgroup for better resource management
- Private registry authentication configured securely
- AppArmor/SELinux compatibility maintained

## Performance Tuning

### Containerd Configuration

Edit `templates/containerd-config.toml.j2` for:

- Max concurrent downloads: `max_concurrent_downloads = 10`
- Image pulling timeout
- Storage driver options

### Kubelet Flags

Additional kubelet arguments can be set in `/var/lib/kubelet/kubeadm-flags.env` after cluster initialization.

## Related Roles

- **k8s_cluster_manager**: Next step - initialize cluster with kubeadm
- **calico_install_manifest**: Install CNI after cluster init
- **apparmor_configure**: Enhanced container security

## References

- [Kubernetes Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Containerd Documentation](https://containerd.io/docs/)
- [kubeadm Installation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

## Changelog

- **2025-11**: Support for Kubernetes 1.33
- **2024**: Initial role creation with Debian/Ubuntu/Rocky support

## Author

Platform Infrastructure Team

## License

Internal use only.
