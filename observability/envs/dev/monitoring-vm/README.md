# dev/monitoring-vm Observability Overlay

Outside-Kubernetes observability target for homelab infrastructure.

The monitoring VM is intentionally separate from the Kubernetes-native
observability stack. It should keep working when `k8s-lab-01` is
unhealthy or unavailable.

## Deployment Contract

Existing wrapper commands:

```bash
./tools/iac-wrapper.sh apply dev monitoring
./tools/iac-wrapper.sh configure dev monitoring monitoring_servers
```

This path provisions and configures:

- `infra/dev/monitoring`
- `config/playbooks/setup_monitoring.yml`
- `config/roles/monitoring_stack`

## Scope

The monitoring VM owns the outside view of:

- Proxmox host and exporter checks
- VM/node exporter targets
- Blackbox checks for public endpoints
- Grafana availability
- future non-Kubernetes infra checks such as MinIO, nginx proxy, and VPN

HCRO and Vault workload/platform observability should move to
`envs/dev/k8s-lab-01` once kube-prometheus-stack is installed.
