# dev/k8s-lab-01 Observability Overlay

Kubernetes-native observability target for the `dev` lab cluster.

This overlay is the target path for workload and platform integrations
that run inside Kubernetes:

- HCRO controller metrics, logs, alerts, and dashboards
- Vault metrics and audit-log pipeline after Vault is deployed
- External Secrets Operator and cert-manager metrics
- Cluster-level Prometheus Operator resources

## Deployment Contract

Use the existing component wrapper shape. Do not add a top-level
`apply observability` wrapper action.

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 install_observability.yml k8s_master
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 apply_observability.yml k8s_master
```

Planned responsibilities:

- `install_observability.yml`: install kube-prometheus-stack and any
  required CRDs/operators.
- `apply_observability.yml`: apply selected consumer packages from
  `observability/consumers/*` into the cluster.

## Enabled Consumers

Initial target:

- `consumers/hcro`

Future targets:

- `consumers/vault`
- `consumers/eso`
- `consumers/cert-manager`

## Notes

This overlay is the inside-Kubernetes view. The outside view remains
`envs/dev/monitoring-vm`.
