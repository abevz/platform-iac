# Monitoring Runbook

Operational runbook for the Homelab monitoring stack:

- VM: `192.0.2.108` (`monitoring`)
- Components: Prometheus, Grafana, Alertmanager, Node Exporter, Proxmox Exporter, Blackbox Exporter
- Public UI: `https://grafana.example.com`

## Quick Health Checks

Run from your workstation:

```bash
ssh 192.0.2.108 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
ssh 192.0.2.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9090/-/ready"
ssh 192.0.2.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9093/-/ready"
ssh 192.0.2.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/login"
```

Expected: all containers `Up`, all endpoints return `200`.

## Telegram Notifications

Alertmanager sends alerts to Telegram when these vars are present in `config/secrets/ansible/extra_vars.sops.yml`:

```yaml
monitoring:
  telegram_bot_token: "<bot-token>"
  telegram_chat_id: "<chat-id>"
```

Verify live config:

```bash
ssh 192.0.2.108 "sudo sed -n '1,200p' /srv/monitoring/alertmanager/alertmanager.yml"
```

Look for `receiver: telegram` and `telegram_configs`.

## Common Incidents

### 0) Vault Agent for Kubernetes discovery tokens

The monitoring VM uses Vault Agent to render short-lived Kubernetes
service-account tokens for Prometheus pod and endpoints discovery.

Split of responsibilities:

- `platform-iac-gitops` manages Kubernetes objects:
  `prometheus-external` ServiceAccount, its RBAC, and
  `vault-token-creator-rbac`.
- `platform-iac` manages Vault and the monitoring VM:
  Kubernetes secrets engine config, AppRole policy, Vault Agent config,
  and Prometheus mounts.

Required Ansible vars in `config/secrets/ansible/extra_vars.sops.yml`:

```yaml
monitoring:
  vault_agent_enabled: true
  vault_agent_role_id: "<approle-role-id>"
  vault_agent_secret_id: "<approle-secret-id>"
  vault_agent_vault_addr: "https://vault.bevz.net"

vault_k8s_secrets_enabled: true
vault_k8s_secrets_path: "kubernetes"
vault_k8s_secrets_host: "https://10.10.10.200:6443"
vault_k8s_secrets_ca_cert: |
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----
vault_k8s_secrets_service_account_jwt: "<vault-auth-jwt>"
vault_k8s_secrets_roles:
  - name: prometheus-external
    allowed_namespaces: "monitoring"
    service_account_name: "prometheus-external"
    token_ttl: "1h"
    token_max_ttl: "4h"

vault_approle_enabled: true
vault_approle_roles:
  - name: monitoring-k8s-read
    policy: |
      path "kubernetes/creds/prometheus-external" {
        capabilities = ["create", "update"]
      }
```

Apply order:

```bash
./tools/iac-wrapper.sh run-playbook dev vault setup_vault_config.yml all
./tools/iac-wrapper.sh configure dev monitoring
```

Verify live state:

```bash
ssh 192.0.2.108 "sudo docker logs --tail 60 monitoring-vault-agent"
ssh 192.0.2.108 "sudo ls -la /srv/monitoring/vault-agent/tokens"
ssh 192.0.2.108 "sudo docker exec monitoring-prometheus ls -la /etc/prometheus/k8s-tokens"
```

Expected:

- `monitoring-vault-agent` is `Up`
- `.vault-token` exists
- `dev-k8s-lab-01.token` exists both on the host and inside Prometheus

### 1) Grafana returns 502/Bad Gateway

Checks:

```bash
ssh 192.0.2.105 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
ssh 192.0.2.105 "sudo docker exec reverseproxy nginx -T | grep -n 'grafana.example.com'"
ssh 192.0.2.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/login"
```

Action:

- Restart reverse proxy if needed.
- Re-apply nginx role:

```bash
./tools/iac-wrapper.sh run-static setup_nginx-proxy.yml nginx_proxies
```

### 2) Proxmox metrics fail (`pve-exporter` 401)

Symptom: `pve-exporter` target is down, logs show unauthorized.

Check:

```bash
ssh 192.0.2.108 "sudo docker logs --tail 120 monitoring-pve-exporter"
```

Action:

- Ensure token is valid in `extra_vars.sops.yml`:

```yaml
monitoring:
  proxmox_token_id: "monitoring@pve"
  proxmox_token_name: "prometheus"
  proxmox_token_secret: "<token-secret>"
```

- Re-apply monitoring:

```bash
./tools/iac-wrapper.sh configure dev monitoring monitoring_servers
```

### 3) Certificate expiry alerts

Check certbot timer on `nginx-proxy`:

```bash
ssh 192.0.2.105 "systemctl status certbot-renew.timer"
ssh 192.0.2.105 "systemctl list-timers | grep certbot-renew"
```

Manual renewal (if required):

```bash
ssh 192.0.2.105 "sudo certbot renew --force-renewal"
```

## Operational Commands

Apply monitoring stack config:

```bash
./tools/iac-wrapper.sh configure dev monitoring monitoring_servers
```

Apply nginx-proxy config:

```bash
./tools/iac-wrapper.sh run-static setup_nginx-proxy.yml nginx_proxies
```

## Dashboard Notes

Main dashboard: `Homelab Pulse` (`uid: homelab-overview`)

- Top row: Host status, VM count, failed units, CPU/RAM/Disk usage, cert days, firing alerts
- Middle: CPU/RAM/Network/Disk trends
- Lower: temperatures, fan RPM, Proxmox VM CPU/RAM, failed unit details, alert timeline

If dashboard looks stale, hard refresh browser (`Ctrl+Shift+R`).

## Next Week Backlog

- Implement VM/LXC log aggregation into Grafana (Loki + Promtail or Promtail-compatible agent).
- Add log labels for `vm_name`, `service`, `severity`, and `environment` to support filtering.
- Create Grafana log dashboards with links from `Homelab Pulse` panels to related logs.
- Add alert-to-log correlation workflow (from alert labels to pre-filtered log queries).
- Define retention policy for logs (hot window, archive strategy, and storage budget).
