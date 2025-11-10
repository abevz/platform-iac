# Role: kube_bench_run

## Description

Runs kube-bench CIS Kubernetes Benchmark tests to evaluate cluster security posture against CIS (Center for Internet Security) hardening guidelines. Essential for CKS exam preparation and production security audits.

## Requirements

- Kubernetes cluster (1.20+)
- kubectl configured with cluster admin access
- Control plane node accessible
- `kubernetes.core` Ansible collection

## Role Variables

### defaults/main.yml

```yaml
# Kube-bench version (Docker image tag)
kube_bench_version: "v0.9.0"

# Namespace for running kube-bench job
kube_bench_namespace: "kube-bench"

# CIS Benchmark version to test against
kube_bench_cis_benchmark: "cis-1.33"  # Options: cis-1.20, cis-1.23, cis-1.24, cis-1.33, etc.

# State management
addon_state: present  # Options: present, absent
```

### Override Variables

```yaml
# Use specific kube-bench version
requested_version: "v0.8.0"

# Test specific CIS version
kube_bench_cis_benchmark: "cis-1.24"

# Custom namespace
kube_bench_namespace: "security-audit"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `kube_bench` | All kube-bench related tasks |

## Dependencies

None - standalone security audit role.

## Example Playbook

### Basic Usage

```yaml
---
- name: Run Kube-bench CIS Audit
  hosts: k8s_master
  become: no
  roles:
    - kube_bench_run
```

### Specific CIS Version

```yaml
---
- name: Run CIS 1.24 Benchmark
  hosts: k8s_master
  become: no
  vars:
    kube_bench_cis_benchmark: "cis-1.24"
  roles:
    - kube_bench_run
```

### With Custom Version

```yaml
---
- name: Run Kube-bench v0.8.0
  hosts: k8s_master
  become: no
  vars:
    requested_version: "v0.8.0"
    kube_bench_cis_benchmark: "cis-1.23"
  roles:
    - kube_bench_run
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Set Target Version              │
│ (requested_version or default)  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create/Delete Namespace         │
│ kubectl create ns kube-bench    │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create/Delete Kube-bench Job    │
│ - hostPID access                │
│ - Mount host directories        │
│ - Run on control plane node     │
└────────────┬────────────────────┘
             │
             ▼ (if addon_state == present)
┌─────────────────────────────────┐
│ Wait for Job Completion         │
│ kubectl wait --for=condition... │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Retrieve Job Logs               │
│ kubectl logs job/kube-bench     │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Parse and Display Results       │
│ - PASS count                    │
│ - FAIL count                    │
│ - WARN count                    │
│ - INFO count                    │
└─────────────────────────────────┘
```

## Kube-bench Test Sections

| Section | Component | Tests |
|---------|-----------|-------|
| 1 | Control Plane | API server, Controller Manager, Scheduler, etcd |
| 2 | etcd | Configuration and security |
| 3 | Control Plane Configuration | Config files, RBAC, admission controllers |
| 4 | Worker Nodes | Kubelet configuration and security |
| 5 | Policies | Pod Security Standards, Network Policies |

## Post-Execution Analysis

### View Results

```bash
# Check job status
kubectl get jobs -n kube-bench

# View full report
kubectl logs -n kube-bench job/kube-bench

# Get summary
kubectl logs -n kube-bench job/kube-bench | grep "\[.*\]"
```

### Results Format

```
[INFO] 1 Control Plane Security Configuration
[PASS] 1.1.1 Ensure that the API server pod specification file permissions are set to 644 or more restrictive
[FAIL] 1.1.2 Ensure that the API server pod specification file ownership is set to root:root
[WARN] 1.2.1 Ensure that the --anonymous-auth argument is set to false

== Summary ==
45 checks PASS
3 checks FAIL
5 checks WARN
2 checks INFO
```

## Common Failures and Fixes

### 1. API Server Anonymous Auth Enabled

**Finding**: `1.2.1 FAIL - anonymous-auth should be false`

**Fix**: Edit API server manifest:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --anonymous-auth=false
```

### 2. Kubelet Config Permissions

**Finding**: `4.1.1 FAIL - kubelet config file permissions are 777`

**Fix**: On worker nodes:

```bash
sudo chmod 600 /var/lib/kubelet/config.yaml
sudo chown root:root /var/lib/kubelet/config.yaml
```

### 3. Pod Security Policy Not Enabled

**Finding**: `1.2.15 WARN - PodSecurityPolicy admission controller not enabled`

**Fix**: Use Pod Security Standards (PSS) instead:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 4. Audit Logging Not Configured

**Finding**: `1.2.19 FAIL - audit-log-path not set`

**Fix**: Configure audit logging:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-log-path=/var/log/kubernetes/audit.log
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
```

Audit policy:

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
```

### 5. RBAC Not Enabled

**Finding**: `1.2.7 FAIL - authorization-mode does not include RBAC`

**Fix**:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --authorization-mode=Node,RBAC
```

## CIS Benchmark Categories

### Critical Fixes (FAIL)

Address these immediately for security:

1. Disable anonymous authentication
2. Enable RBAC authorization
3. Configure audit logging
4. Restrict kubelet permissions
5. Enable admission controllers (NodeRestriction, PodSecurity)

### Warnings (WARN)

Assess risk and implement if applicable:

1. Rotate certificates regularly
2. Enable encryption at rest for etcd
3. Configure network policies
4. Use Pod Security Standards
5. Enable security contexts

### Informational (INFO)

Best practices for consideration:

1. Regular security updates
2. Monitoring and alerting
3. Backup and disaster recovery
4. Security training for operators

## Automated Remediation

### Create Remediation Playbook

Based on kube-bench output, create fixes:

```yaml
---
- name: Remediate CIS Benchmark Failures
  hosts: k8s_master
  become: yes
  tasks:
    - name: Fix API server anonymous auth
      ansible.builtin.lineinfile:
        path: /etc/kubernetes/manifests/kube-apiserver.yaml
        regexp: '^\s*- --anonymous-auth='
        line: '    - --anonymous-auth=false'
        insertafter: '^\s*- kube-apiserver'
      
    - name: Restart kubelet to apply changes
      ansible.builtin.systemd:
        name: kubelet
        state: restarted
```

## Scheduling Regular Audits

### CronJob for Continuous Compliance

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: kube-bench-audit
  namespace: kube-bench
spec:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          hostPID: true
          containers:
          - name: kube-bench
            image: aquasec/kube-bench:v0.9.0
            command: ["kube-bench"]
            args: ["--benchmark", "cis-1.33", "--json"]
            volumeMounts:
            - name: var-lib-etcd
              mountPath: /var/lib/etcd
              readOnly: true
            # ... other mounts
          restartPolicy: OnFailure
          volumes:
          - name: var-lib-etcd
            hostPath:
              path: /var/lib/etcd
```

## Integration with CI/CD

### GitLab CI Example

```yaml
kube-bench-audit:
  stage: security
  script:
    - ansible-playbook -i inventory playbooks/run_kube_bench.yml
    - |
      FAIL_COUNT=$(kubectl logs -n kube-bench job/kube-bench | grep -c "\[FAIL\]")
      if [ $FAIL_COUNT -gt 0 ]; then
        echo "Found $FAIL_COUNT CIS failures"
        exit 1
      fi
  only:
    - schedules
```

## Troubleshooting

### Issue: Job Fails to Schedule

**Symptom**: Job stuck in Pending state

**Solution**: Check node taints and tolerations:

```bash
kubectl describe job kube-bench -n kube-bench
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

Add missing tolerations in job spec.

### Issue: Permission Denied Errors

**Symptom**: Kube-bench cannot read configuration files

**Solution**: Verify volume mounts and hostPath access:

```bash
kubectl logs -n kube-bench job/kube-bench

# Ensure correct paths on control plane node
ls -la /etc/kubernetes/manifests/
ls -la /var/lib/etcd/
```

### Issue: Wrong CIS Version

**Symptom**: Tests fail because benchmark doesn't match K8s version

**Solution**: Match CIS benchmark to Kubernetes version:

```bash
# Check Kubernetes version
kubectl version --short

# Use appropriate benchmark
# K8s 1.20-1.22 -> cis-1.20
# K8s 1.23      -> cis-1.23
# K8s 1.24-1.32 -> cis-1.24
# K8s 1.33+     -> cis-1.33
```

### Issue: etcd Tests Fail

**Symptom**: Section 2 (etcd) all FAIL

**Cause**: etcd running as static pod with different paths

**Solution**: Update volume mounts for your etcd configuration:

```yaml
- name: etcd-config
  hostPath:
    path: /etc/kubernetes/pki/etcd  # Adjust path
```

## Performance Considerations

### Resource Usage

Kube-bench is lightweight:
- CPU: ~100m
- Memory: ~50Mi
- Duration: 30-60 seconds

### Impact on Cluster

- Read-only operations
- No changes to cluster state
- Safe to run on production

## Security Considerations

### Privileged Access

Kube-bench requires:
- `hostPID: true` for process inspection
- Read access to host filesystem
- Control plane node access

### Least Privilege

Job runs as read-only except for hostPID requirement.

## CKS Exam Relevance

This role covers CKS exam domains:

- ✅ Cluster hardening (25%)
- ✅ CIS benchmark compliance
- ✅ Security auditing
- ✅ Configuration validation
- ✅ Control plane security

## Report Formats

### JSON Output

```bash
kubectl run kube-bench --rm -it --image=aquasec/kube-bench:v0.9.0 \
  -- kube-bench --benchmark cis-1.33 --json > report.json
```

### JUnit Format (for CI)

```bash
kube-bench --benchmark cis-1.33 --junit > report.xml
```

## Related Roles

- **k8s_bootstrap_node**: Cluster setup with security in mind
- **apparmor_configure**: Mandatory access control
- **falco_install_helm**: Runtime security monitoring
- **trivy_operator_deploy**: Vulnerability scanning

## References

- [Kube-bench GitHub](https://github.com/aquasecurity/kube-bench)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [Kubernetes Hardening Guide](https://kubernetes.io/docs/concepts/security/hardening/)
- [CKS Exam Curriculum](https://github.com/cncf/curriculum)

## Changelog

- **2025-11**: Updated to CIS 1.33 benchmark
- **2024**: Initial role creation

## Author

Platform Infrastructure Team

## License

Internal use only.
