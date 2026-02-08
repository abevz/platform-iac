# Role: k8s_cluster_manager

## Description

Manages Kubernetes cluster lifecycle operations including control plane initialization, worker node joining, and Harbor registry integration. This role orchestrates the complete cluster setup using kubeadm with support for DNS-based endpoints, automatic CSR approval, and private registry configuration.

## Requirements

- Debian 11/12 or Ubuntu 20.04/22.04
- **k8s_bootstrap_node** role applied to all nodes (installs kubeadm, kubelet, kubectl)
- Root or sudo access
- Container runtime installed (containerd/CRI-O)
- Network connectivity between all cluster nodes
- Harbor private registry (optional, for registry-creds secret)

## Role Variables

### defaults/main.yml

```yaml
# Pod network CIDR (must match CNI plugin configuration)
pod_cidr: "192.168.0.0/16"

# Kubernetes version (full semantic version)
kubernetes_version: "{{ k8s_short_version | default('1.33.0') }}"

# Harbor registry configuration (optional)
# harbor_hostname: "harbor.<your-domain>.com"
# harbor_robot_username: "robot$k8s-pull"
# harbor_robot_token: ""  # Pass via -e or SOPS
# target_namespaces: ["default", "production"]
```

### Override Variables

```yaml
# Custom pod CIDR for Calico/Cilium
pod_cidr: "10.244.0.0/16"

# Specific Kubernetes version
kubernetes_version: "1.31.0"

# Harbor configuration
harbor_hostname: "registry.example.com"
harbor_robot_username: "robot$cluster-pull"
harbor_robot_token: "{{ vault_harbor_token }}"
target_namespaces:
  - default
  - kube-system
  - production
  - staging
```

### Group Variables (group_vars/k8s_master.yml)

```yaml
# Recommended: Define pod_cidr in group_vars
pod_cidr: "192.168.0.0/16"

# Kubernetes version
k8s_short_version: "1.31"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `kubeadm_init` | Initialize control plane only |
| `kubeadm_join` | Join worker nodes only |
| `harbor_secret` | Create Harbor registry secrets |

## Dependencies

- **k8s_bootstrap_node**: Must be applied first to install kubeadm/kubelet/kubectl
- **Container Runtime**: containerd or CRI-O configured on all nodes

## Example Playbook

### Complete Cluster Setup

```yaml
---
- name: Initialize Kubernetes Cluster
  hosts: k8s_cluster
  become: yes
  vars:
    k8s_short_version: "1.31"
    pod_cidr: "192.168.0.0/16"
  roles:
    - k8s_bootstrap_node      # Install kubeadm/kubelet/kubectl
    - k8s_cluster_manager     # Initialize cluster
```

### Control Plane Only

```yaml
---
- name: Initialize Control Plane
  hosts: k8s_master
  become: yes
  roles:
    - role: k8s_cluster_manager
      tags: [kubeadm_init]
```

### Worker Nodes Only

```yaml
---
- name: Join Worker Nodes
  hosts: k8s_worker
  become: yes
  roles:
    - role: k8s_cluster_manager
      tags: [kubeadm_join]
```

### With Harbor Registry

```yaml
---
- name: Setup Cluster with Harbor Integration
  hosts: k8s_cluster
  become: yes
  vars:
    harbor_hostname: "harbor.<your-domain>.com"
    harbor_robot_username: "robot$k8s-pull"
    harbor_robot_token: "{{ lookup('env', 'HARBOR_ROBOT_TOKEN') }}"
    target_namespaces:
      - default
      - production
  roles:
    - k8s_bootstrap_node
    - k8s_cluster_manager
```

### Multi-Environment Setup

```yaml
---
- name: Deploy Production Kubernetes Cluster
  hosts: k8s_prod
  become: yes
  vars:
    pod_cidr: "192.168.0.0/16"
    k8s_short_version: "1.31"
  roles:
    - k8s_cluster_manager

- name: Deploy Staging Kubernetes Cluster
  hosts: k8s_staging
  become: yes
  vars:
    pod_cidr: "10.244.0.0/16"
    k8s_short_version: "1.30"
  roles:
    - k8s_cluster_manager
```

## Task Workflow

```
┌─────────────────────────────────┐
│ CONTROL PLANE (k8s_master)      │
├─────────────────────────────────┤
│ 1. Check if already initialized │
│    (stat /etc/kubernetes/       │
│     admin.conf)                 │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 2. Generate kubeadm config      │
│    - Control plane endpoint     │
│    - Pod/Service CIDR           │
│    - API server cert SANs       │
│    - ServerTLSBootstrap enabled │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 3. Initialize cluster           │
│    kubeadm init --config=...    │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 4. Configure kubeconfig         │
│    - /root/.kube/config         │
│    - /home/user/.kube/config    │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 5. Generate join command        │
│    kubeadm token create         │
│    --print-join-command         │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 6. Fetch join command to local  │
│    /tmp/kubeadm_join_command.sh │
└─────────────────────────────────┘
             │
             │
             ▼
┌─────────────────────────────────┐
│ WORKER NODES (k8s_worker)       │
├─────────────────────────────────┤
│ 1. Check if already joined      │
│    (stat /etc/kubernetes/       │
│     kubelet.conf)               │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 2. Copy join command from local │
│    /tmp/kubeadm_join_command.sh │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 3. Execute join command         │
│    kubeadm join <endpoint>      │
└─────────────────────────────────┘
             │
             │
             ▼
┌─────────────────────────────────┐
│ HARBOR INTEGRATION (optional)   │
├─────────────────────────────────┤
│ 1. Validate Harbor token        │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ 2. Create registry-creds secret │
│    in target namespaces         │
│    (dockerconfigjson type)      │
└─────────────────────────────────┘
```

## kubeadm Configuration

### Generated kubeadm-config.yaml

The role generates a comprehensive kubeadm configuration:

```yaml
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: <K8S-INGRESS-IP>
  bindPort: 6443
nodeRegistration:
  kubeletExtraArgs:
    node-ip: <K8S-INGRESS-IP>
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v1.31.0"
controlPlaneEndpoint: "k8s-master.example.com:6443"
apiServer:
  certSANs:
  - <K8S-INGRESS-IP>
  - k8s-master
  - k8s-master.example.com
  - localhost
  - 127.0.0.1
  - kubernetes
  - kubernetes.default
  - kubernetes.default.svc
  - kubernetes.default.svc.cluster.local
networking:
  dnsDomain: cluster.local
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
serverTLSBootstrap: true
```

### Key Features

- **DNS-based control plane endpoint**: Uses FQDN for HA compatibility
- **Certificate SANs**: Includes IP, hostname, FQDN, and Kubernetes defaults
- **ServerTLSBootstrap**: Enables automatic kubelet certificate rotation
- **Node IP binding**: Explicitly binds kubelet to primary network interface

## Post-Installation Verification

### On Control Plane

```bash
# Check cluster status
kubectl get nodes -o wide

# Expected output:
# NAME         STATUS   ROLES           AGE   VERSION   INTERNAL-IP
# k8s-master   Ready    control-plane   5m    v1.31.0   <K8S-INGRESS-IP>
# k8s-worker1  Ready    <none>          3m    v1.31.0   <K8S-WORKER-1-IP>
# k8s-worker2  Ready    <none>          3m    v1.31.0   <K8S-WORKER-2-IP>

# Check component status
kubectl get pods -n kube-system

# Verify cluster info
kubectl cluster-info
```

### Check Certificates

```bash
# List certificates
kubeadm certs check-expiration

# Verify kubelet serving CSRs (if ServerTLSBootstrap enabled)
kubectl get csr

# Approve pending CSRs (if any)
kubectl certificate approve <csr-name>
```

### Test Harbor Integration

```bash
# Verify registry-creds secret
kubectl get secret registry-creds -n default -o yaml

# Test image pull from Harbor
kubectl run test-pod --image=harbor.<your-domain>.com/library/nginx:latest \
  --image-pull-policy=Always \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"registry-creds"}]}}'

# Cleanup
kubectl delete pod test-pod
```

## Harbor Registry Integration

### What is Created

The role creates a `registry-creds` secret in specified namespaces:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: registry-creds
  namespace: default
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-docker-config>
```

### Usage in Deployments

Reference the secret in pod specs:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  imagePullSecrets:
  - name: registry-creds
  containers:
  - name: app
    image: harbor.<your-domain>.com/library/myapp:latest
```

### Generate Harbor Robot Account

1. Log in to Harbor UI
2. Go to **Projects → library → Robot Accounts**
3. Click **+ New Robot Account**
4. Configure:
   - Name: `k8s-pull`
   - Expiration: 1 year
   - Permissions: Pull artifacts
5. Copy generated token

### Pass Token to Role

```bash
# Via command line
ansible-playbook playbooks/setup_k8s.yml \
  -e "harbor_robot_token=YOUR_TOKEN_HERE"

# Via environment variable
export HARBOR_ROBOT_TOKEN="YOUR_TOKEN"
ansible-playbook playbooks/setup_k8s.yml \
  -e "harbor_robot_token=${HARBOR_ROBOT_TOKEN}"

# Via SOPS encrypted file
# In config/secrets/ansible/extra_vars.sops.yml
harbor:
  robot_token: "YOUR_TOKEN"
```

## Troubleshooting

### Issue: Control plane initialization fails

**Symptom**: `kubeadm init` exits with error

**Solution**:
```bash
# Check kubeadm logs
journalctl -u kubelet -n 100

# Reset and retry
kubeadm reset -f
systemctl restart kubelet
# Re-run ansible role

# Verify prerequisites
kubeadm init phase preflight
```

### Issue: Worker nodes fail to join

**Symptom**: `kubeadm join` times out or fails

**Solution**:
```bash
# On control plane: Verify API server is accessible
kubectl get nodes

# On worker: Test connectivity to control plane
telnet k8s-master.example.com 6443
curl -k https://k8s-master.example.com:6443

# Check firewall rules
iptables -L -n | grep 6443

# Regenerate join command
kubeadm token create --print-join-command
```

### Issue: Nodes stuck in NotReady state

**Symptom**: `kubectl get nodes` shows NotReady

**Solution**:
```bash
# Check kubelet status
systemctl status kubelet
journalctl -u kubelet -n 50

# Verify CNI plugin is installed
ls -la /etc/cni/net.d/
ls -la /opt/cni/bin/

# Install CNI (e.g., Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Check pod network
kubectl get pods -n kube-system -o wide
```

### Issue: Certificate SANs missing

**Symptom**: API server certificate doesn't include required SANs

**Solution**:
```bash
# Add SANs to kubeadm-config.yaml template
# Then regenerate certificates
kubeadm init phase certs apiserver --config=/tmp/kubeadm-config.yaml

# Or edit existing certificate (requires cluster downtime)
kubeadm certs renew apiserver
systemctl restart kubelet
```

### Issue: Harbor image pull fails

**Symptom**: `ImagePullBackOff` errors in pod status

**Solution**:
```bash
# Verify secret exists
kubectl get secret registry-creds -n default

# Check secret content
kubectl get secret registry-creds -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Test Harbor login manually
docker login harbor.<your-domain>.com -u robot$k8s-pull -p YOUR_TOKEN

# Verify pod uses imagePullSecrets
kubectl describe pod <pod-name> | grep -A5 "Image Pull"

# Recreate secret if needed
kubectl delete secret registry-creds -n default
# Re-run ansible role with harbor_secret tag
```

### Issue: Token expired

**Symptom**: Worker join fails with "token not found"

**Solution**:
```bash
# On control plane: List tokens
kubeadm token list

# Create new token
kubeadm token create --print-join-command

# Update /tmp/kubeadm_join_command.sh
# Re-run ansible role on workers
```

## Network Configuration

### Pod Network CIDR

The `pod_cidr` variable must match your CNI plugin:

| CNI Plugin | Default CIDR | Configuration |
|------------|--------------|---------------|
| Calico | 192.168.0.0/16 | pod_cidr: "192.168.0.0/16" |
| Cilium | 10.244.0.0/16 | pod_cidr: "10.244.0.0/16" |
| Flannel | 10.244.0.0/16 | pod_cidr: "10.244.0.0/16" |
| Weave Net | 10.32.0.0/12 | pod_cidr: "10.32.0.0/12" |

### Service Network

Fixed at `10.96.0.0/12` (default Kubernetes service CIDR).

### Firewall Rules

Required ports:

**Control Plane:**
- 6443/tcp - Kubernetes API server
- 2379-2380/tcp - etcd
- 10250/tcp - kubelet API
- 10251/tcp - kube-scheduler
- 10252/tcp - kube-controller-manager

**Worker Nodes:**
- 10250/tcp - kubelet API
- 30000-32767/tcp - NodePort services

**All Nodes:**
- CNI plugin specific ports (varies by plugin)

## High Availability Setup

This role supports HA control plane setups:

### Load Balancer Configuration

```yaml
# Use load balancer FQDN as control plane endpoint
# In kubeadm-config.yaml.j2:
controlPlaneEndpoint: "k8s-lb.example.com:6443"
```

### Additional Control Plane Nodes

```yaml
# On first master: Generate certificate key
kubeadm init phase upload-certs --upload-certs

# Join additional masters
kubeadm join k8s-lb.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key>
```

## Upgrade Considerations

### Kubernetes Version Upgrade

To upgrade cluster version:

1. Update `kubernetes_version` variable
2. Upgrade control plane first:
```bash
kubeadm upgrade plan
kubeadm upgrade apply v1.32.0
```
3. Upgrade worker nodes:
```bash
kubeadm upgrade node
```

### Container Runtime Migration

If migrating from Docker to containerd:

1. Update k8s_bootstrap_node role to install new runtime
2. Drain and reboot each node individually
3. Verify pods are rescheduled correctly

## Security Considerations

### ServerTLSBootstrap

This role enables `serverTLSBootstrap: true`, which:
- Automatically rotates kubelet serving certificates
- Requires manual CSR approval (or automatic with cert-manager)
- Improves security by using short-lived certificates

### RBAC

Kubeadm creates default RBAC policies. Additional restrictions should be applied:

```yaml
# Restrict default service account
kubectl patch serviceaccount default -n default \
  -p '{"automountServiceAccountToken":false}'
```

### Network Policies

After CNI installation, implement network policies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

## Performance Tuning

### Kubelet Configuration

For high-load environments, tune kubelet:

```yaml
# In kubeadm-config.yaml.j2
nodeRegistration:
  kubeletExtraArgs:
    node-ip: {{ ansible_default_ipv4.address }}
    max-pods: "200"
    kube-reserved: "cpu=500m,memory=1Gi"
    system-reserved: "cpu=500m,memory=1Gi"
```

### etcd Optimization

For large clusters (50+ nodes):

```yaml
# Increase etcd quota
apiServer:
  extraArgs:
    etcd-compaction-interval: "5m"
```

## Related Roles

- **k8s_bootstrap_node**: Installs kubeadm, kubelet, kubectl (required)
- **calico_install_manifest**: Deploy Calico CNI
- **cilium_install_helm**: Deploy Cilium CNI
- **metallb_install**: LoadBalancer for bare-metal
- **ingress_nginx_install**: Ingress controller
- **cert_manager_install**: Certificate management

## Related Playbooks

- `config/playbooks/setup_k8s-lab-01.yml`: Complete cluster deployment
- `config/playbooks/install_calico_manifest.yml`: CNI installation
- `config/playbooks/install_metallb.yml`: LoadBalancer setup

## References

- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/)
- [HA Cluster Setup](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [Harbor Documentation](https://goharbor.io/docs/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## Changelog

- **2025-11**: Initial role creation for platform-iac
- **2025-11**: Added ServerTLSBootstrap support
- **2025-11**: Added Harbor registry integration
- **2025-11**: DNS-based control plane endpoint

## Author

Platform Infrastructure Team

## License

Internal use only.
