# Observability — Directory Contract

Centralized observability artifacts for the lab. See
[ADR-002](../docs/decisions/ADR-002-observability-stack-architecture.md)
for the architectural decision; this README is the operational contract.

The platform has two observability layers:

- **Monitoring VM**: outside-Kubernetes infrastructure monitoring,
  deployed by `infra/dev/monitoring` and `config/roles/monitoring_stack`.
- **kube-prometheus-stack**: inside-Kubernetes workload/platform
  monitoring for HCRO, Vault, ESO, cert-manager, and future consumers.

## Directory Layout

```text
observability/
├── README.md
├── consumers/
│   └── hcro/
│       ├── prometheus/
│       │   ├── rules.yaml
│       │   └── servicemonitor-reference.yaml
│       ├── loki/
│       │   └── pipeline.yaml
│       └── grafana/
│           └── dashboards/
│               └── README.md
└── envs/
    └── dev/
        ├── k8s-lab-01/
        │   └── README.md
        └── monitoring-vm/
            └── README.md
```

`consumers/` answers **what is monitored**. Each consumer package holds
platform-owned rules, dashboards, and log pipelines for one source of
signals.

`envs/` answers **where and how those packages are enabled**. Environment
overlays choose which consumer packages are active, which namespaces and
release labels apply, and which delivery mechanism is used.

## Current Environment Split

### `dev/monitoring-vm`

The existing monitoring VM is the outside view of the lab. It watches
infrastructure even when Kubernetes is unhealthy.

Deploy and update it with the existing wrapper contract:

```bash
./tools/iac-wrapper.sh apply dev monitoring
./tools/iac-wrapper.sh configure dev monitoring monitoring_servers
```

It is responsible for Proxmox, host/node exporter targets, blackbox
checks, Grafana public endpoint checks, and other non-Kubernetes
infrastructure signals.

### `dev/k8s-lab-01`

The Kubernetes-native layer is the target path for HCRO, Vault, ESO,
cert-manager, and cluster workload observability. It is intended to be
installed into `k8s-lab-01` with kube-prometheus-stack and then populated
from the selected `observability/consumers/*` packages.

The intended wrapper shape is:

```bash
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 install_observability.yml k8s_master
./tools/iac-wrapper.sh run-playbook dev k8s-lab-01 apply_observability.yml k8s_master
```

Those playbooks are not implemented yet; do not use a fake
`apply observability` top-level wrapper action.

## Conventions

### Consumer Packages

- Prometheus rules live under
  `observability/consumers/<name>/prometheus/rules.yaml`.
- ServiceMonitor or PodMonitor references live under
  `observability/consumers/<name>/prometheus/`.
- Loki/Promtail pipelines live under
  `observability/consumers/<name>/loki/pipeline.yaml`.
- Grafana dashboards live under
  `observability/consumers/<name>/grafana/dashboards/`.
- Recording rules use
  `slo:<consumer>:<slo-id>:<signal>:<window>`.

### Cardinality Discipline

The platform refuses time-series with labels that an upstream consumer
has not declared in its requirements. Log pipelines explicitly list
which JSON fields become Loki labels. PRs adding new labels must include
cardinality math in the description.

### Source of Truth

Consumer ADRs and NFRs are authoritative for **what** they emit. Files
under `observability/consumers/` are authoritative for **how** the
platform consumes and acts on those signals. Files under
`observability/envs/` are authoritative for **where** those signals are
enabled.

Concretely for HCRO:

- Metric catalog and cardinality budget: [HCRO NFR-002](https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/specs/001-mvp/requirements.md)
- Alert names and severities: [HCRO NFR-006](https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/specs/001-mvp/requirements.md)
- Runbook anchors per alert: [HCRO docs/runbook.md](https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/runbook.md)

If a metric is referenced in `consumers/hcro/prometheus/rules.yaml` but
not in HCRO's NFR-002 catalog, the rule is wrong. If an alert in that
rules file has no matching anchor in HCRO's `runbook.md`, the alert is
wrong.

## Adding a New Consumer

Three actions per consumer:

1. **In the consumer repo:** ship a `ServiceMonitor` or `PodMonitor`
   under `config/observability/`, ship a `runbook.md` with per-alert
   anchors, and define a metric catalog in the consumer's NFR docs.
2. **In this repo:** add `observability/consumers/<name>/` with
   Prometheus rules, dashboards, and a Loki pipeline if the consumer
   emits structured JSON logs with a distinct schema.
3. **In each target env:** update the matching
   `observability/envs/<env>/<target>/` overlay or deployment role to
   enable that consumer package.

## Validation

Before applying Kubernetes-native observability artifacts:

```bash
promtool check rules observability/consumers/*/prometheus/rules.yaml
# Optional: simulate alerts against historical data
promtool test rules observability/consumers/hcro/prometheus/test/rules_test.yaml
```

For the existing monitoring VM, continue validating through the
`monitoring_stack` role and its generated Prometheus/Grafana config.

## Phases

Per [ADR-002](../docs/decisions/ADR-002-observability-stack-architecture.md):

- Phase A — keep monitoring VM as infra baseline; add
  kube-prometheus-stack install playbook
- Phase B — apply first `dev/k8s-lab-01` overlay with HCRO rules
- Phase C — Loki + Promtail pipelines for HCRO and Vault audit logs
- Phase D — alerting routes and runbook integration
- Phase E — SLO recording rules + burn-rate alerts
- Phase F — Tempo + OpenTelemetry Collector
- Phase G — Pyroscope and capacity planning

## References

- [ADR-002](../docs/decisions/ADR-002-observability-stack-architecture.md)
- HCRO ADR-006:
  https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/specs/001-mvp/decisions/ADR-006-observability-stack-integration.md
- HCRO NFR-002 + NFR-006:
  https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/specs/001-mvp/requirements.md
