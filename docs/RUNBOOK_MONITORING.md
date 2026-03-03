# Monitoring Runbook

Operational runbook for the Homelab monitoring stack:

- VM: `10.10.10.108` (`monitoring`)
- Components: Prometheus, Grafana, Alertmanager, Node Exporter, Proxmox Exporter, Blackbox Exporter
- Public UI: `https://grafana.bevz.net`

## Quick Health Checks

Run from your workstation:

```bash
ssh 10.10.10.108 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
ssh 10.10.10.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9090/-/ready"
ssh 10.10.10.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9093/-/ready"
ssh 10.10.10.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/login"
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
ssh 10.10.10.108 "sudo sed -n '1,200p' /srv/monitoring/alertmanager/alertmanager.yml"
```

Look for `receiver: telegram` and `telegram_configs`.

## Common Incidents

### 1) Grafana returns 502/Bad Gateway

Checks:

```bash
ssh 10.10.10.105 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
ssh 10.10.10.105 "sudo docker exec reverseproxy nginx -T | grep -n 'grafana.bevz.net'"
ssh 10.10.10.108 "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/login"
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
ssh 10.10.10.108 "sudo docker logs --tail 120 monitoring-pve-exporter"
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
ssh 10.10.10.105 "systemctl status certbot-renew.timer"
ssh 10.10.10.105 "systemctl list-timers | grep certbot-renew"
```

Manual renewal (if required):

```bash
ssh 10.10.10.105 "sudo certbot renew --force-renewal"
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
