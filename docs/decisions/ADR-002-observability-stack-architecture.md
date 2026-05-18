# ADR-002: Observability stack architecture

## Status

Accepted — 2026-05-12

## Context

`platform-iac` provisions observability for the lab at two levels:

- an outside-Kubernetes monitoring VM for homelab infrastructure
- an inside-Kubernetes observability stack for workloads and platform
  integrations

Multiple consumer projects emit metrics, logs, and events that need to
be scraped, indexed, visualized, and alerted on consistently.

The first consumer is `hybrid-cloud-optimizer` (HCRO), whose
[ADR-006](https://github.com/abevz/hybrid-cloud-optimizer) defines the
emit-and-integrate boundary: HCRO emits Prometheus metrics, slog JSON
to stdout, and Kubernetes Events; the platform consumes them. The
choice in this ADR governs how the platform consumes these signals and
how dashboards/alerting are organized.

Constraints:

- Self-hosted, on-prem first. The lab cannot route every signal through
  a SaaS vendor.
- Solo operator. Operational overhead matters; cannot afford a complex
  observability fleet.
- DevSecOps career relevance. The stack must match what is used in
  production environments.
- Multi-consumer. HCRO is the first; the platform serves any future
  project the same way.
- Coexist with Vault audit log (per ADR-001) — Vault audit events go
  into the same Loki, queryable with the same Grafana.

## Decision

Keep the existing **monitoring VM** as the outside-Kubernetes
infrastructure baseline, and adopt **kube-prometheus-stack**
(Prometheus Operator + Prometheus + Alertmanager + Grafana) as the
inside-Kubernetes observability backbone for HCRO, Vault, ESO,
cert-manager, and future workload consumers.

Use **Loki** for log aggregation and **Promtail** as the log forwarder
inside the Kubernetes-native layer.

Architecture summary:

- **Monitoring VM** deployed by `infra/dev/monitoring` and configured
  by `config/roles/monitoring_stack`. It watches Proxmox, VM/node
  exporter targets, public endpoint blackbox checks, and other
  non-Kubernetes infrastructure signals.
- **kube-prometheus-stack** in `k8s-lab-01` for Kubernetes-native
  workload/platform observability. Discovery via `ServiceMonitor` and
  `PodMonitor` CRs.
- **Prometheus** inside kube-prometheus-stack, initially lab-sized;
  HA replicas and long-term object storage are later hardening steps.
- **Alertmanager** inside kube-prometheus-stack, routing to Telegram
  by default for the lab; Slack, email, and PagerDuty are optional
  later integrations.
- **Grafana** as the visualization layer. Dashboards committed to git
  and reconciled by the Grafana Operator (or kustomize-based deploy).
  Provisioned datasources for Prometheus, Loki, and (Phase F) Tempo.
- **Loki** in single-binary mode for the lab; clustered mode and
  object-storage chunks are later hardening steps.
- **Promtail** as a DaemonSet on every node, tailing pod stdout/stderr.
  Pipeline stages parse known JSON log formats (HCRO, Vault audit,
  ESO, cert-manager) into Loki labels with bounded cardinality.
- **kube-events-exporter** as a Deployment, converting Kubernetes
  Events into Prometheus metrics (rate-limited counter per
  `(involved_object_kind, reason)`). Visible in dashboards alongside
  controller metrics.
- **Phase 6+: Tempo + OpenTelemetry Collector** for distributed
  tracing. Adopted when first consumer (HCRO B-016) emits traces.
- **Phase 6+: Pyroscope** for continuous profiling. Adopted when HCRO
  B-017 lands `/debug/pprof`.

Repository layout in this project:

```
observability/
  README.md
  consumers/
    hcro/
      prometheus/
        rules.yaml
        servicemonitor-reference.yaml
      loki/
        pipeline.yaml
      grafana/
        dashboards/
          README.md
    vault/                           # future: metrics, audit logs, dashboard
  envs/
    dev/
      k8s-lab-01/                    # kube-prometheus-stack target
      monitoring-vm/                 # existing Docker Compose monitoring VM
```

`consumers/` answers what is monitored. `envs/` answers where and how a
consumer package is enabled.

Future target layout:

```
observability/
  consumers/
    hcro/
      grafana/
        dashboards/
          overview.json
          reconciliation-health.json
          decision-engine.json
          external-dependencies.json
          business-outcomes.json
    vault/
      grafana/
        dashboards/
          operations.json            # Vault metrics + audit log access patterns
    cluster/
      grafana/
        dashboards/
          nodes.json
          kubelet.json
  envs/
    dev/
      k8s-lab-01/
        kustomization.yaml
        values-kube-prometheus-stack.yaml
        alertmanager-routes.yaml
      monitoring-vm/
        prometheus-extra-scrape.yml
        grafana-dashboard-provider.yml
```

Dashboard paths under each consumer expand as the implementation
matures:

```
observability/consumers/hcro/grafana/dashboards/
        overview.json
        reconciliation-health.json
        decision-engine.json
        external-dependencies.json
        business-outcomes.json
```

Consumers (HCRO, future projects) ship:

- Metric definitions and cardinality budgets (in their requirements docs)
- `ServiceMonitor` CR in `config/observability/` of their repo
- Runbook (`docs/runbook.md`) — one anchored section per alert defined
  in this project

The platform ships:

- Alerting rules (this project)
- Recording rules and SLO computations (this project)
- Dashboards (this project)
- Log aggregation pipeline (this project)
- Alert routing (this project)

## Consequences

Positive:

- **Two-layer observability fabric for the lab.** The monitoring VM
  gives an outside view of infrastructure; kube-prometheus-stack gives
  the inside-Kubernetes view for HCRO, Vault, ESO, cert-manager, and
  cluster signals.
- **Dashboards-as-code in this project.** No "mystery dashboards"
  built in the Grafana UI that disappear on disaster recovery.
- **Multi-consumer reuse.** Adding a new project means adding one
  `ServiceMonitor` in the project's repo, one consumer package here,
  and enabling it in the target env overlay. No new infrastructure.
- **Industry standard for DevSecOps.** Prometheus + Grafana + Loki +
  Tempo (LGTM stack) is the open-source default. Skills transfer.
- **Boundary stays clean.** Application repos own metric contracts
  (cardinality budgets, label dimensions, slog field names). Platform
  owns dashboards/alerts/aggregation. Changes don't cascade across
  repos unnecessarily.

Negative / trade-offs:

- **Stack ownership.** Prometheus + Loki + Grafana is one more set of
  components to keep running. Mitigation: kube-prometheus-stack is a
  well-maintained Helm chart with sane defaults.
- **Storage growth.** Time-series and logs scale with consumer count.
  Mitigation: lab-sized retention first; object storage and lifecycle
  policies during Phase G capacity planning.
- **Two-repo coordination.** A new metric in HCRO needs a new panel in
  this repo. Mitigation: HCRO's NFR-002 catalog is the source of
  truth; PRs cross-reference it.
- **Multi-tenant scope creep risk.** Tempting to put non-platform
  dashboards (e.g. team-specific app metrics) here. Mitigation: this
  repo hosts only platform-level and infrastructure dashboards; app
  teams own their app dashboards if/when they have multiple teams.

## Alternatives Considered

### A. Vendor SaaS (Datadog / NewRelic) — rejected

A single hosted observability platform.

Rejected because:

- Pricing scales with host count and metric cardinality. Untenable for
  a long-running self-funded lab.
- Vendor-specific SDKs in consumers — couples HCRO to Datadog.
- Less portable knowledge for DevSecOps interviews focused on open
  source tooling.

### B. Grafana Cloud — rejected for primary use

Hosted Grafana + Loki + Tempo with a free tier.

Rejected because:

- Free tier covers a homelab but introduces cloud dependency on a
  third-party SaaS for the always-on observability path.
- Logs and metrics exit the lab; data residency concerns even at home
  scale.

Considered as a **backup** target: optional remote-write from
Prometheus to Grafana Cloud for cross-region resilience. Not enabled
by default.

### C. ELK (Elasticsearch + Logstash + Kibana) — rejected

Classic logging stack.

Rejected because:

- Elasticsearch is heavy on memory and disk for what the lab needs.
- Less common in cloud-native Kubernetes shops than LGTM stack.
- License complications (Elastic License vs Apache).

### D. Selected — kube-prometheus-stack + LGTM (Loki, Grafana, Tempo, Mimir/Prometheus)

The open-source de-facto standard for Kubernetes observability. Native
operator support, declarative configuration, broad community.

## Implementation Roadmap

- **Phase A** — keep monitoring VM as infra baseline; add
  kube-prometheus-stack install playbook for `k8s-lab-01`
- **Phase B** — apply first `dev/k8s-lab-01` overlay with HCRO rules
- **Phase C** — Loki + Promtail pipelines for HCRO and Vault audit logs
- **Phase D** — alerting routes, SLO recording rules, burn-rate alerts,
  and runbook integration with HCRO
- **Phase E** — Tempo + OpenTelemetry Collector (when HCRO B-016 lands)
- **Phase F** — Pyroscope for continuous profiling (when HCRO B-017
  lands)
- **Phase G** — Capacity planning, long-term storage tuning, multi-team
  dashboard organization

## Forward References

- [observability/README.md](../../observability/README.md) — directory
  structure and operations
- HCRO ADR-006 — consumer boundary (HCRO emits metrics/logs/events; no
  ownership of dashboards or alerting rules)

## References

- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Loki: https://grafana.com/oss/loki/
- Promtail: https://grafana.com/docs/loki/latest/clients/promtail/
- Grafana Operator: https://github.com/grafana-operator/grafana-operator
- Google SRE Workbook (burn-rate alerts): https://sre.google/workbook/alerting-on-slos/
- Consumer example — HCRO: https://github.com/abevz/hybrid-cloud-optimizer
  (see `docs/specs/001-mvp/decisions/ADR-006-observability-stack-integration.md`
  and `requirements.md` NFR-002 + NFR-006)
