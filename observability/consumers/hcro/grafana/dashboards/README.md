# HCRO Grafana dashboards

This directory holds the five Grafana dashboards for the HCRO
controller per HCRO B-014 (Phase 6 backlog). Files are checked in as
JSON, deployed by the Grafana Operator (or by `kustomize` jobs against
the Grafana Helm chart's sidecar dashboards mechanism).

This README is a **placeholder** — actual dashboard JSON is implemented
by HCRO B-014. See HCRO ADR-006 for the boundary and HCRO NFR-002 for
the metrics each dashboard should consume.

## Dashboards

| File | Audience | Panels (sketch) |
|---|---|---|
| `overview.json` | quick-glance | pod up, leader held, error rate, SLO burn for SLO-1..SLO-4, recent alert annotations |
| `reconciliation-health.json` | operator on-call | RED breakdown (rate, errors, duration), p50/p95/p99 latency, workqueue depth, per-error-class breakdown |
| `decision-engine.json` | dev / debug | placement distribution (stacked area: proxmox vs aws vs pending over time), flip rate, pending duration by reason |
| `external-dependencies.json` | dep ops | AWS Pricing API: rate + p95 latency + error rate. VPN probe: state heatmap + p95 RTT. K8s Metrics API: rest_client_request_latency_seconds for nodes endpoint |
| `business-outcomes.json` | product / leadership | counterfactual cost saved (from B-002 audit log → B-012 evaluation), decisions/min, hysteresis stability (flip rate over 24h), pending duration distribution |

## Conventions

- **Datasources**: dashboards reference Prometheus by UID
  `${DS_PROMETHEUS}` and Loki by UID `${DS_LOKI}`. Datasource UIDs are
  set by Grafana provisioning in this repo; dashboards remain portable.
- **Variables**: each dashboard exposes a `$namespace` variable
  defaulting to `hcro-system`. SLO dashboards expose `$slo_window`
  with allowed values `5m, 1h, 24h, 30d`.
- **Annotations**: alert firing events from Alertmanager are
  annotated on every dashboard via the `alerts` annotation source
  configured by Grafana Operator.
- **Template format**: edited in Grafana UI for layout, exported via
  "Share → Export → JSON for sharing externally" (anonymized
  datasource UIDs). Committed to git as exported JSON; no manual JSON
  editing.

## Sync wave with HCRO

Dashboards are not coupled to HCRO release. They are platform-owned.
A new HCRO metric in NFR-002 catalog requires:

1. HCRO PR exposes the metric (T023 acceptance).
2. Platform PR adds the panel to the relevant dashboard JSON.
3. The two PRs can merge independently as long as the dashboard PR
   does not silently break on a missing metric (Grafana shows "No
   data" panels — acceptable degraded state).

## Validation

```bash
# Grafana dashboard JSON schema validation
grafana-dash-cli validate observability/consumers/hcro/grafana/dashboards/*.json

# Smoke-test query rendering against the Prometheus instance
for f in observability/consumers/hcro/grafana/dashboards/*.json; do
  jq -r '.panels[].targets[].expr // empty' "$f" \
    | while read q; do
        promtool query instant http://prometheus.monitoring:9090 "$q" \
          || echo "BROKEN: $q in $f"
      done
done
```

## References

- HCRO ADR-006: https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/specs/001-mvp/decisions/ADR-006-observability-stack-integration.md
- HCRO NFR-002 (metric catalog): https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/specs/001-mvp/requirements.md
- HCRO B-014 (task spec): https://github.com/abevz/hybrid-cloud-optimizer/blob/main/docs/specs/001-mvp/tasks.md
- Platform ADR-002: ../../../../../docs/decisions/ADR-002-observability-stack-architecture.md
