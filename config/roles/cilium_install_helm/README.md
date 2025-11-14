# Role: cilium_install_helm

## Description

Installs **Cilium** - an advanced eBPF-based CNI plugin providing high-performance networking, security, and observability. Cilium can replace kube-proxy, provides Hubble observability, and offers superior performance through eBPF technology.

## Requirements

- Kubernetes cluster v1.22+
- Linux kernel 4.19+ (5.10+ recommended for full eBPF features)
- Helm 3 installed
- No existing CNI plugin installed

## Role Variables

### defaults/main.yml

```yaml
# Cilium Helm repository
cilium_helm_repo_url: "https://helm.cilium.io/"

# Cilium chart version
cilium_chart_version: "1.18.3"

# Namespace
cilium_namespace: "kube-system"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `cilium` | All Cilium tasks |

## Dependencies

- **k8s_cluster_manager**: Cluster must be initialized

## Example Playbook

### Basic Installation

```yaml
---
- name: Install Cilium CNI
  hosts: k8s_master
  become: yes
  roles:
    - cilium_install_helm
```

### With kube-proxy Replacement

```yaml
---
- name: Install Cilium with Advanced Features
  hosts: k8s_master
  become: yes
  vars:
    cilium_kube_proxy_replacement: "strict"
    cilium_hubble_enabled: true
  roles:
    - cilium_install_helm
```

### Declarative Install/Uninstall

```yaml
# Install Cilium
- hosts: k8s_master
  become: yes
  roles:
    - role: cilium_install_helm
      vars:
        addon_state: present

# Uninstall Cilium
- hosts: k8s_master
  become: yes
  roles:
    - role: cilium_install_helm
      vars:
        addon_state: absent
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Install Helm Dependencies       │
│ (curl, gpg, apt-transport)      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install Helm 3                  │
│ (from Buildkite repository)     │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install Cilium CLI              │
│ (latest stable version)         │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Add Cilium Helm Repository      │
│ https://helm.cilium.io/         │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install Cilium via Helm         │
│ - eBPF dataplane                │
│ - Optional: kube-proxy replace  │
│ - Optional: Hubble observability│
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Wait for Cilium Ready           │
│ cilium status --wait            │
└─────────────────────────────────┘
```

## Post-Installation Verification

```bash
# Check Cilium status
cilium status

# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Expected:
# cilium-xxx    1/1   Running
# cilium-yyy    1/1   Running
# cilium-operator-xxx   1/1   Running

# Test connectivity
cilium connectivity test

# Check nodes are Ready
kubectl get nodes
```

## Features

### eBPF-Based Networking

- **High performance**: In-kernel packet processing
- **Lower latency**: Bypasses iptables overhead
- **Better scalability**: Handles 10k+ services

### kube-proxy Replacement

```yaml
# Enable in Helm values
kubeProxyReplacement: "strict"
```

Benefits:
- Eliminates kube-proxy overhead
- Better load balancing algorithms
- Reduced latency for service routing

### Hubble Observability

```yaml
# Enable Hubble
hubble:
  enabled: true
  ui:
    enabled: true
```

Access Hubble UI:
```bash
cilium hubble ui
# Opens http://localhost:12000
```

### Network Policies

Cilium supports both Kubernetes NetworkPolicies and CiliumNetworkPolicies with advanced features:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-policy
spec:
  endpointSelector:
    matchLabels:
      app: myapp
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api/.*"
```

### Encryption

Enable Wireguard encryption:
```yaml
encryption:
  enabled: true
  type: wireguard
```

## Troubleshooting

### Issue: Cilium pods not starting

**Solution**:
```bash
# Check kernel version
uname -r  # Should be 4.19+

# Check eBPF support
cilium status

# View logs
kubectl logs -n kube-system -l k8s-app=cilium
```

### Issue: Connectivity test fails

**Solution**:
```bash
# Run detailed connectivity test
cilium connectivity test --verbose

# Check Cilium health
cilium status --verbose

# Verify BPF filesystem
mount | grep bpf
```

### Issue: kube-proxy conflict

**Solution**:
```bash
# If kube-proxy is still running, disable it:
kubectl -n kube-system delete ds kube-proxy
kubectl -n kube-system delete cm kube-proxy

# Or use kubeProxyReplacement: "probe" mode
```

## Performance Tuning

### Enable XDP Acceleration

```yaml
# Helm values
bpf:
  masquerade: true
  tproxy: true
```

### Optimize for Large Clusters

```yaml
# Increase operator replicas
operator:
  replicas: 3

# Tune connection tracking
bpf:
  ctAnyMax: 262144
  natMax: 524288
```

## Monitoring

### Hubble Metrics

```bash
# Enable metrics
hubble:
  metrics:
    enabled:
    - dns
    - drop
    - tcp
    - flow
    - icmp
    - http
```

### Prometheus Integration

Cilium exports metrics on port 9962:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cilium-agent-metrics
  namespace: kube-system
spec:
  selector:
    k8s-app: cilium
  ports:
  - port: 9962
```

## Comparison with Calico

| Feature | Cilium | Calico |
|---------|--------|--------|
| Technology | eBPF | iptables/eBPF |
| Performance | Excellent | Good |
| kube-proxy replacement | Yes | No |
| Observability | Hubble (built-in) | External tools |
| Learning curve | Higher | Lower |
| Maturity | Newer | Mature |
| L7 policies | Yes | Limited |

## Related Roles

- **k8s_cluster_manager**: Cluster initialization (required)
- **calico_install_manifest**: Alternative CNI
- **cilium_install_cli**: CLI-only installation

## Related Playbooks

- `config/playbooks/install_cilium.yml`: Main Cilium deployment

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [Cilium GitHub](https://github.com/cilium/cilium)
- [eBPF Introduction](https://ebpf.io/)
- [Hubble Observability](https://docs.cilium.io/en/stable/gettingstarted/hubble/)

## Changelog

- **2025-11**: Initial Helm-based installation
- **2025-11**: Cilium CLI integration
- **2025-11**: Declarative addon_state support

## Author

Platform Infrastructure Team

## License

Internal use only.
