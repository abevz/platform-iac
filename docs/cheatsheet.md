# Platform IaC Cheat Sheet

Quick reference for common operations in the Platform Infrastructure as Code project.

## 🚀 Quick Commands

### Deployment

```bash
# Full stack deployment
./tools/iac-wrapper.sh deploy dev k8s-lab-01

# Infrastructure only
cd infra/dev/k8s-lab-01 && terraform apply

# Kubernetes only
ansible-playbook -i config/inventory/static.ini \
  config/playbooks/setup_k8s-lab-01.yml

# Single role
ansible-playbook playbook.yml --tags argocd
```

### Cluster Operations

```bash
# Get cluster info
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Get kubeconfig
scp root@k8s-lab-01-cp:/etc/kubernetes/admin.conf ~/.kube/config

# Join token (valid 24h)
kubeadm token create --print-join-command

# Drain node for maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Uncordon node
kubectl uncordon <node-name>
```

### Add-ons Management

```bash
# Install add-on
ansible-playbook -i inventory config/playbooks/install_<addon>.yml

# Remove add-on
ansible-playbook -i inventory playbook.yml -e "addon_state=absent"

# Update add-on
ansible-playbook -i inventory playbook.yml -e "requested_version=v2.0.0"
```

## 📋 Ansible Tags

### Bootstrap Tags
```bash
--tags bootstrap_prereqs    # System setup only
--tags containerd           # Containerd only
--tags k8s_packages         # K8s packages only
--tags init_cluster         # Cluster init only
--tags join_workers         # Join workers only
```

### Add-on Tags
```bash
--tags calico               # CNI networking
--tags argocd               # GitOps
--tags ingress              # Ingress controller
--tags falco                # Runtime security
--tags kube_bench           # CIS audit
--tags cert_manager         # Certificate management
```

### Skip Tags
```bash
--skip-tags k8s_packages    # Skip package install
--skip-tags containerd      # Skip containerd setup
```

## 🔍 Debugging

### Ansible

```bash
# Verbose mode
ansible-playbook playbook.yml -vvv

# Check mode (dry-run)
ansible-playbook playbook.yml --check

# Limit to specific hosts
ansible-playbook playbook.yml --limit k8s-lab-01-cp

# List tasks
ansible-playbook playbook.yml --list-tasks

# List tags
ansible-playbook playbook.yml --list-tags
```

### Kubernetes

```bash
# Describe resources
kubectl describe node <node-name>
kubectl describe pod <pod-name> -n <namespace>

# Get events
kubectl get events -A --sort-by='.lastTimestamp'
kubectl get events -n <namespace> --watch

# Logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl logs <pod-name> -n <namespace> -c <container-name>
kubectl logs -f <pod-name> -n <namespace>  # Follow

# Shell into pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Port forward
kubectl port-forward svc/<service-name> 8080:80 -n <namespace>
```

### System Logs

```bash
# Kubelet
journalctl -u kubelet -f
journalctl -u kubelet -n 100 --no-pager

# Containerd
journalctl -u containerd -f
crictl ps
crictl logs <container-id>

# System
dmesg | tail
tail -f /var/log/syslog
```

## 🔒 Security Operations

### CIS Benchmark

```bash
# Run audit
ansible-playbook -i inventory config/playbooks/run_kube_bench.yml

# View results
kubectl logs -n kube-bench job/kube-bench

# Filter failures
kubectl logs -n kube-bench job/kube-bench | grep "\[FAIL\]"

# Get summary
kubectl logs -n kube-bench job/kube-bench | grep "== Summary =="
```

### Falco Alerts

```bash
# View real-time alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Filter by priority
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep WARNING
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep CRITICAL

# Check Falco status
kubectl get pods -n falco
kubectl describe pod -n falco <falco-pod>
```

### Trivy Scanning

```bash
# Scan image
trivy image nginx:latest

# Get vulnerability reports
kubectl get vulnerabilityreports -A
kubectl describe vulnerabilityreport <report-name> -n <namespace>

# Get config audit reports
kubectl get configauditreports -A
```

### RBAC

```bash
# Check permissions
kubectl auth can-i create deployments --as=system:serviceaccount:default:mysa

# List roles
kubectl get roles -A
kubectl get clusterroles

# Describe role
kubectl describe role <role-name> -n <namespace>
kubectl describe clusterrole <clusterrole-name>

# List role bindings
kubectl get rolebindings -A
kubectl get clusterrolebindings
```

## 🌐 Networking

### Service & Endpoints

```bash
# List services
kubectl get svc -A

# Service endpoints
kubectl get endpoints -A
kubectl describe svc <service-name> -n <namespace>

# Test service
kubectl run test --rm -it --image=busybox -- wget -O- <service-name>.<namespace>
```

### Network Policies

```bash
# List policies
kubectl get networkpolicies -A

# Describe policy
kubectl describe networkpolicy <policy-name> -n <namespace>

# Test connectivity
kubectl run test --rm -it --image=nicolaka/netshoot -- curl <url>
```

### DNS

```bash
# Test DNS resolution
kubectl run test --rm -it --image=busybox -- nslookup kubernetes.default

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# DNS debug pod
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
kubectl exec -it dnsutils -- nslookup kubernetes.default
```

### Ingress

```bash
# List ingresses
kubectl get ingress -A

# Describe ingress
kubectl describe ingress <ingress-name> -n <namespace>

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

## 💾 Storage

### PV/PVC

```bash
# List volumes
kubectl get pv
kubectl get pvc -A

# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl get storageclass
```

## 📊 Monitoring

### Resource Usage

```bash
# Node metrics
kubectl top nodes

# Pod metrics
kubectl top pods -A
kubectl top pods -n <namespace> --sort-by=cpu
kubectl top pods -n <namespace> --sort-by=memory

# Container metrics
kubectl top pod <pod-name> -n <namespace> --containers
```

### Cluster Status

```bash
# Component health
kubectl get componentstatuses
kubectl get --raw /healthz
kubectl get --raw /readyz

# API server
kubectl cluster-info
kubectl version

# Node conditions
kubectl get nodes -o wide
kubectl describe node <node-name> | grep Conditions -A 10
```

## 🔧 Maintenance

### Certificate Management

```bash
# Check certificate expiration
kubeadm certs check-expiration

# Renew certificates
kubeadm certs renew all
systemctl restart kubelet

# Manual renewal (specific cert)
kubeadm certs renew apiserver
```

### Backup & Restore

```bash
# Backup etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify snapshot
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db

# Restore etcd (requires cluster downtime)
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db
```

### Upgrade

```bash
# Upgrade control plane
ansible-playbook -i inventory config/playbooks/upgrade_k8s.yml \
  --limit k8s_master

# Upgrade workers (one by one)
kubectl drain <node-name> --ignore-daemonsets
ansible-playbook -i inventory config/playbooks/upgrade_k8s.yml \
  --limit <node-name>
kubectl uncordon <node-name>
```

## 🛠️ Configuration

### ConfigMap

```bash
# Create from file
kubectl create configmap my-config --from-file=config.yaml

# Create from literal
kubectl create configmap my-config --from-literal=key=value

# Get ConfigMap
kubectl get configmap my-config -o yaml
```

### Secret

```bash
# Create generic secret
kubectl create secret generic my-secret --from-literal=password=abc123

# Create TLS secret
kubectl create secret tls tls-secret --cert=cert.pem --key=key.pem

# Create docker registry secret
kubectl create secret docker-registry regcred \
  --docker-server=harbor.example.com \
  --docker-username=user \
  --docker-password=pass

# Decode secret
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d
```

## 📝 Quick Manifests

### Debug Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: debug
spec:
  containers:
  - name: debug
    image: nicolaka/netshoot
    command: ["/bin/bash"]
    args: ["-c", "sleep 3600"]
```

```bash
kubectl apply -f debug-pod.yaml
kubectl exec -it debug -- /bin/bash
```

### NetworkPolicy (Deny All)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Pod Security Context

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

## 🔗 Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Kubectl
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias kaf='kubectl apply -f'
alias kdelf='kubectl delete -f'
alias kgpa='kubectl get pods -A'
alias kctx='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'

# Ansible
alias ap='ansible-playbook'
alias apc='ansible-playbook --check'
alias apv='ansible-playbook -vvv'
alias ai='ansible-inventory'
alias ag='ansible-galaxy'

# Terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfo='terraform output'
```

## 📚 Quick Links

- **Main Docs**: [docs/README.md](./README.md)
- **Roles**: [config/roles/README.md](../config/roles/README.md)
- **k8s_bootstrap**: [config/roles/k8s_bootstrap_node/README.md](../config/roles/k8s_bootstrap_node/README.md)
- **ArgoCD**: [config/roles/argocd_install/README.md](../config/roles/argocd_install/README.md)
- **Falco**: [config/roles/falco_install_helm/README.md](../config/roles/falco_install_helm/README.md)
- **Kube-bench**: [config/roles/kube_bench_run/README.md](../config/roles/kube_bench_run/README.md)

## 🆘 Emergency Procedures

### Cluster Unresponsive

```bash
# Check control plane components
ssh root@k8s-lab-01-cp
systemctl status kubelet
systemctl status containerd
crictl ps | grep kube-apiserver

# Restart kubelet
systemctl restart kubelet

# Check logs
journalctl -u kubelet -n 100
```

### Pod Stuck in Terminating

```bash
# Force delete pod
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# Remove finalizers
kubectl patch pod <pod-name> -n <namespace> \
  -p '{"metadata":{"finalizers":null}}'
```

### Node Not Ready

```bash
# Check node
kubectl describe node <node-name>

# SSH to node
ssh root@<node-ip>

# Check kubelet
systemctl status kubelet
journalctl -u kubelet -f

# Restart kubelet
systemctl restart kubelet
```

---

**Quick Tip**: Use `kubectl explain <resource>` to get inline documentation!

```bash
kubectl explain pod.spec.securityContext
kubectl explain networkpolicy.spec
```
