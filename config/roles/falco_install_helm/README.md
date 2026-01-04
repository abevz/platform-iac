# Role: falco_install_helm

## Description

Deploys Falco runtime security monitoring tool using Helm. Falco is a CNCF graduated project that detects unexpected behavior, intrusions, and data theft in real-time by monitoring system calls and Kubernetes audit logs.

## Requirements

- Kubernetes cluster (1.24+)
- Helm 3.x installed
- Kernel headers installed on nodes (for eBPF probe)
- `kubernetes.core` Ansible collection

## Role Variables

### defaults/main.yml

```yaml
# Falco Helm configuration
falco_helm_release_name: falco
falco_namespace: falco
falco_helm_repo_url: https://falcosecurity.github.io/charts
falco_helm_chart_name: falco

# State management
addon_state: present  # Options: present, absent
```

### Helm Values (templates/values.yaml.j2)

```yaml
driver:
  kind: modern_ebpf  # modern_ebpf, ebpf, or module

falco:
  grpc:
    enabled: true
  grpc_output:
    enabled: true
  json_output: true
  json_include_output_property: true
  log_level: info

tty: true

falcosidekick:
  enabled: false  # Enable for alert forwarding
```

## Tags

| Tag | Purpose |
|-----|---------|
| `falco` | All Falco-related tasks |

## Dependencies

None - standalone security monitoring role.

## Example Playbook

### Basic Installation

```yaml
---
- name: Install Falco Runtime Security
  hosts: k8s_master
  become: no
  roles:
    - falco_install_helm
```

### With Custom Namespace

```yaml
---
- name: Install Falco in Security Namespace
  hosts: k8s_master
  become: no
  vars:
    falco_namespace: security
  roles:
    - falco_install_helm
```

### Uninstall Falco

```yaml
---
- name: Remove Falco
  hosts: k8s_master
  become: no
  vars:
    addon_state: absent
  roles:
    - falco_install_helm
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Add Falco Helm Repository      │
│ helm repo add falcosecurity     │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install/Uninstall Falco Chart   │
│ helm install/uninstall falco    │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Deploy Custom Rules ConfigMap   │
│ - Secret access detection       │
│ - Privilege escalation alerts   │
│ - Suspicious process execution  │
└─────────────────────────────────┘
```

## Custom Falco Rules

This role includes custom rules for Kubernetes security:

### 1. Kubernetes Secret Access

Detects when users access Kubernetes secrets:

```yaml
- rule: Kubernetes Secret Access
  desc: Detect access to Kubernetes secrets
  condition: >
    ka and
    ka.verb in (get, list) and
    ka.objectResource.resource=secrets
  output: >
    Kubernetes secret accessed (user=%ka.user.name verb=%ka.verb
    resource=%ka.target.resource object=%ka.target.name
    namespace=%ka.target.namespace)
  priority: WARNING
```

### 2. Container Privilege Escalation

Alerts on privilege escalation attempts in containers:

```yaml
- rule: Container Privilege Escalation
  desc: Detect containers running with privilege escalation
  condition: >
    spawned_process and
    proc.name in (sudo, su, doas) and
    container
  output: >
    Privilege escalation in container (user=%user.name
    command=%proc.cmdline container=%container.name
    image=%container.image.repository)
  priority: WARNING
```

## Post-Installation Verification

### Check Falco Pods

```bash
kubectl get pods -n falco
```

Expected output:
```
NAME          READY   STATUS    RESTARTS   AGE
falco-xxxxx   1/1     Running   0          1m
falco-yyyyy   1/1     Running   0          1m
```

### View Falco Logs

```bash
# View real-time alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Check for specific events
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep WARNING
```

### Test Falco Detection

#### Test 1: Read Sensitive File

```bash
kubectl run test --rm -it --image=alpine -- cat /etc/shadow
```

Expected Falco alert:
```json
{
  "output": "File below / opened for reading (user=root command=cat /etc/shadow file=/etc/shadow)",
  "priority": "Warning",
  "rule": "Read sensitive file untrusted"
}
```

#### Test 2: Execute Shell in Container

```bash
kubectl exec -it <pod-name> -- /bin/sh
```

Expected alert for interactive shell spawning.

## Falco Components

| Component | Purpose | Type |
|-----------|---------|------|
| falco | Main daemon for syscall monitoring | DaemonSet |
| falco-exporter | Prometheus metrics exporter | Deployment |
| falcosidekick | Alert forwarding to external systems | Deployment (optional) |

## Alert Integration

### Enable Falcosidekick

Edit `templates/values.yaml.j2`:

```yaml
falcosidekick:
  enabled: true
  config:
    slack:
      webhookurl: "https://hooks.slack.com/services/XXX"
      minimumpriority: "warning"
    elasticsearch:
      hostport: "http://elasticsearch:9200"
```

### Supported Outputs

- Slack
- Microsoft Teams
- PagerDuty
- Email (SMTP)
- Elasticsearch
- Loki
- Prometheus (metrics)
- Webhook (custom)

## Rule Management

### Add Custom Rules

Create ConfigMap with additional rules:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-custom-rules
  namespace: falco
data:
  custom_rules.yaml: |
    - rule: Unauthorized Process
      desc: Detect unauthorized processes in production containers
      condition: >
        spawned_process and
        container and
        k8s.ns.name = "production" and
        not proc.name in (node, nginx, java)
      output: >
        Unauthorized process in production (command=%proc.cmdline
        container=%container.name namespace=%k8s.ns.name)
      priority: CRITICAL
```

Apply custom rules:

```bash
kubectl apply -f custom-rules.yaml
kubectl rollout restart daemonset/falco -n falco
```

### Rule Priority Levels

- `EMERGENCY`: System is unusable
- `ALERT`: Action must be taken immediately
- `CRITICAL`: Critical conditions
- `ERROR`: Error conditions
- `WARNING`: Warning conditions
- `NOTICE`: Normal but significant
- `INFORMATIONAL`: Informational messages
- `DEBUG`: Debug-level messages

## Troubleshooting

### Issue: Falco Pods Not Starting

**Symptom**: Pods stuck in CrashLoopBackOff

**Solution**: Check kernel module/eBPF support:

```bash
# Check Falco logs
kubectl logs -n falco <pod-name>

# Verify kernel headers (on nodes)
uname -r
ls /usr/src/linux-headers-$(uname -r)/

# Install kernel headers (Debian/Ubuntu)
sudo apt-get install linux-headers-$(uname -r)

# Install kernel headers (Rocky Linux)
sudo dnf install kernel-devel-$(uname -r)
```

### Issue: No Alerts Generated

**Symptom**: Falco running but not generating alerts

**Solution**:

```bash
# Check Falco configuration
kubectl exec -n falco <pod-name> -- falco --list

# Verify rules are loaded
kubectl exec -n falco <pod-name> -- cat /etc/falco/falco_rules.yaml

# Test with known-bad action
kubectl run test --rm -it --image=alpine -- sh -c "cat /etc/shadow"
```

### Issue: High CPU Usage

**Symptom**: Falco consuming excessive CPU

**Solution**: Tune buffering and syscall filtering:

```yaml
# In values.yaml.j2
falco:
  syscall_event_drops:
    threshold: .1
    actions:
      - log
      - alert

  # Reduce syscall monitoring
  rules:
    - rule: ...
      condition: ... and not container.image.repository contains "system"
```

### Issue: eBPF Probe Fails

**Symptom**: Modern eBPF probe cannot load

**Solution**: Fallback to kernel module:

```yaml
driver:
  kind: module  # Or 'ebpf' for older eBPF
```

## Performance Tuning

### Resource Limits

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1024Mi
  requests:
    cpu: 100m
    memory: 512Mi
```

### Syscall Filtering

Exclude low-risk syscalls:

```yaml
falco:
  syscall_event_drops:
    rate: .03333  # Allow 1 drop per 30 events
    max_burst: 1000
```

## Security Considerations

### RBAC Permissions

Falco requires these permissions:
- Read all pods, namespaces, events
- Watch all resources for audit logs
- Host filesystem access (read-only)

### AppArmor/SELinux

Falco needs unconfined access for syscall monitoring:

```yaml
securityContext:
  privileged: true
```

Consider using custom AppArmor profiles for production.

## Monitoring

### Prometheus Metrics

Falco exposes metrics on port 8765:

```yaml
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: falco
  namespace: falco
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: falco
  endpoints:
  - port: metrics
```

### Key Metrics

- `falco_events_total`: Total events processed
- `falco_drops_total`: Dropped events (buffer overflow)
- `falco_alerts_total`: Total alerts generated
- `falco_rule_matches_total`: Rule matches by priority

## CKS Exam Relevance

This role covers CKS exam topics:

- ✅ Runtime security with Falco
- ✅ System call monitoring
- ✅ Anomaly detection
- ✅ Audit logging integration
- ✅ Container behavior analysis

## Related Roles

- **trivy_operator_deploy**: Vulnerability scanning (complementary)
- **apparmor_configure**: Mandatory access control
- **kube_bench_run**: CIS benchmark compliance

## References

- [Falco Documentation](https://falco.org/docs/)
- [Falco Rules](https://github.com/falcosecurity/rules)
- [CNCF Falco Project](https://www.cncf.io/projects/falco/)
- [Falco Helm Chart](https://github.com/falcosecurity/charts)

## Changelog

- **2025-11**: Updated to modern eBPF driver
- **2024**: Initial Helm-based deployment

## Author

Platform Infrastructure Team

## License

Internal use only.
