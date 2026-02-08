# Role: metallb_install

## Description

Installs and configures **MetalLB** - a load balancer implementation for bare-metal Kubernetes clusters. MetalLB provides network load balancing functionality that is typically available only in cloud environments (AWS ELB, GCP Load Balancer, etc.), enabling LoadBalancer-type Services on on-premise infrastructure.

## Requirements

- Running Kubernetes cluster (v1.22+)
- kubectl configured on control plane
- Root or sudo access on control plane node
- Available IP address range for load balancers (not used by DHCP)
- Layer 2 (ARP) or BGP network configuration

## Role Variables

### defaults/main.yml

```yaml
# MetalLB version
metallb_version: "v0.14.8"

# Namespace for MetalLB components
metallb_namespace: "metallb-system"

# MetalLB manifest URL
metallb_install_url: "https://raw.githubusercontent.com/metallb/metallb/{{ metallb_target_version }}/config/manifests/metallb-native.yaml"

# IP address range for LoadBalancer services
metallb_ip_range: "<K8S-INGRESS-IP>-<K8S-IP-END>"
```

### Override Variables

```yaml
# Custom IP range
metallb_ip_range: "192.168.1.100-192.168.1.150"

# Specific version
metallb_version: "v0.14.5"

# Custom namespace
metallb_namespace: "loadbalancer-system"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `metallb` | All MetalLB tasks |

## Dependencies

- **k8s_cluster_manager**: Cluster must be initialized
- **CNI Plugin**: Calico/Cilium/Flannel must be installed and running

## Example Playbook

### Basic Installation

```yaml
---
- name: Install MetalLB LoadBalancer
  hosts: k8s_master
  become: yes
  roles:
    - metallb_install
```

### With Custom IP Range

```yaml
---
- name: Install MetalLB with Custom IPs
  hosts: k8s_master
  become: yes
  vars:
    metallb_ip_range: "10.20.30.100-10.20.30.150"
  roles:
    - metallb_install
```

### Declarative Install/Uninstall

```yaml
# Install MetalLB
- hosts: k8s_master
  become: yes
  roles:
    - role: metallb_install
      vars:
        addon_state: present

# Uninstall MetalLB
- hosts: k8s_master
  become: yes
  roles:
    - role: metallb_install
      vars:
        addon_state: absent
```

### Multi-Environment Setup

```yaml
---
- name: Production Cluster with Large IP Pool
  hosts: k8s_prod_master
  become: yes
  vars:
    metallb_ip_range: "<PIHOLE-IP>-<K8S-INGRESS-IP>"
  roles:
    - metallb_install

- name: Staging Cluster with Small IP Pool
  hosts: k8s_staging_master
  become: yes
  vars:
    metallb_ip_range: "10.10.11.100-10.10.11.110"
  roles:
    - metallb_install
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
│ Apply MetalLB Manifest          │
│ (controller + speaker pods)     │
│ URL: github.com/metallb/metallb │
│ /config/manifests/              │
│ metallb-native.yaml             │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Wait for Pods Ready             │
│ kubectl wait --for=condition=   │
│ ready pod -l app=metallb        │
│ --timeout=300s                  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create IPAddressPool CR         │
│ apiVersion: metallb.io/v1beta1  │
│ kind: IPAddressPool             │
│ addresses:                      │
│ - <K8S-INGRESS-IP>-<K8S-IP-END>     │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create L2Advertisement CR       │
│ apiVersion: metallb.io/v1beta1  │
│ kind: L2Advertisement           │
│ ipAddressPools:                 │
│ - default-pool                  │
└─────────────────────────────────┘
```

## What Gets Installed

### Kubernetes Resources

**Namespace:**
- `metallb-system` (or custom via `metallb_namespace`)

**Deployments:**
- `controller` - Manages IP address allocation
  - 1 replica
  - Assigns LoadBalancer IPs to Services
  - Watches Service and IPAddressPool resources

**DaemonSets:**
- `speaker` - Advertises LoadBalancer IPs on network
  - Runs on all nodes
  - Handles ARP/NDP responses (Layer 2 mode)
  - Or BGP peering (BGP mode)

**Custom Resource Definitions (CRDs):**
- `IPAddressPool` - Defines IP address ranges
- `L2Advertisement` - Configures Layer 2 advertisement
- `BGPPeer` - BGP configuration (if using BGP mode)
- `BGPAdvertisement` - BGP route advertisement

**Service Accounts & RBAC:**
- `controller` and `speaker` service accounts
- ClusterRoles and ClusterRoleBindings for API access

### Configuration Resources

**IPAddressPool:**
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - <K8S-INGRESS-IP>-<K8S-IP-END>  # IP range
```

**L2Advertisement:**
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

## Post-Installation Verification

### Check MetalLB Pods

```bash
# Verify all pods are running
kubectl get pods -n metallb-system

# Expected output:
# NAME                          READY   STATUS    RESTARTS   AGE
# controller-5f98465b6b-xxxxx   1/1     Running   0          2m
# speaker-xxxxx                 1/1     Running   0          2m
# speaker-yyyyy                 1/1     Running   0          2m
# speaker-zzzzz                 1/1     Running   0          2m
```

### Verify CRDs

```bash
# List MetalLB CRDs
kubectl get crd | grep metallb

# Check IPAddressPool
kubectl get ipaddresspool -n metallb-system

# Check L2Advertisement
kubectl get l2advertisement -n metallb-system
```

### Check Controller Logs

```bash
kubectl logs -n metallb-system deployment/controller
```

### Check Speaker Logs

```bash
# On all nodes
kubectl logs -n metallb-system daemonset/speaker
```

## Usage Examples

### Simple LoadBalancer Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
```

Deploy and check:
```bash
kubectl apply -f nginx-lb-service.yaml

# MetalLB will automatically assign an IP from the pool
kubectl get svc nginx-lb
# NAME       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
# nginx-lb   LoadBalancer   10.96.123.45    <K8S-INGRESS-IP>    80:30123/TCP
```

### Request Specific IP

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-lb
spec:
  type: LoadBalancer
  loadBalancerIP: <METALLB-EXAMPLE-IP-1>  # Request specific IP from pool
  selector:
    app: myapp
  ports:
  - port: 443
    targetPort: 8443
```

### Share IP Between Services

```yaml
apiVersion: v1
kind: Service
metadata:
  name: http-service
  annotations:
    metallb.universe.tf/allow-shared-ip: "shared-key"
spec:
  type: LoadBalancer
  loadBalancerIP: <METALLB-EXAMPLE-IP-2>
   ports:
   - port: 80
     targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
   name: https-service
   annotations:
     metallb.universe.tf/allow-shared-ip: "shared-key"
spec:
   type: LoadBalancer
   loadBalancerIP: <METALLB-EXAMPLE-IP-2>  # Same IP as http-service
  ports:
  - port: 443
    targetPort: 8443
```

## Layer 2 (ARP) Mode

This role configures MetalLB in **Layer 2 mode** by default.

### How L2 Mode Works

1. MetalLB assigns LoadBalancer IP to a Service
2. One `speaker` pod (on one node) becomes the "leader" for that IP
3. Leader responds to ARP requests for the LoadBalancer IP
4. Network traffic is directed to that node
5. Kubernetes routes traffic to the correct pod (may be on another node)

### Advantages

- ✅ Simple configuration (no BGP required)
- ✅ Works on any network infrastructure
- ✅ No special router configuration needed

### Limitations

- ❌ Single-node bottleneck (all traffic goes through one node)
- ❌ Failover takes 10-30 seconds (ARP cache timeout)
- ❌ Not true load balancing (traffic not distributed across nodes)

### Network Requirements

- All nodes must be on the same Layer 2 network (same subnet)
- IP address range must be unused by DHCP/other systems
- No firewall blocking ARP traffic

## IP Address Pool Configuration

### Single IP Range

```yaml
metallb_ip_range: "192.168.1.100-192.168.1.150"
```

### Multiple Ranges (Advanced)

For multiple pools, manually create IPAddressPool resources:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
   - <PIHOLE-IP>-<METALLB-POOL-END>
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: staging-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.10.11.100-10.10.11.120
```

Use pool in Service:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: prod-app
  annotations:
    metallb.universe.tf/address-pool: production-pool
spec:
  type: LoadBalancer
  # ...
```

### CIDR Notation

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: cidr-pool
spec:
  addresses:
  - 192.168.1.0/28  # 192.168.1.1 - 192.168.1.14
```

## Troubleshooting

### Issue: Pods stuck in Pending/CrashLoopBackOff

**Symptom**: `kubectl get pods -n metallb-system` shows non-Running pods

**Solution**:
```bash
# Check pod events
kubectl describe pod -n metallb-system <pod-name>

# Check logs
kubectl logs -n metallb-system <pod-name>

# Common issues:
# 1. Insufficient resources
kubectl describe nodes | grep -A5 "Allocated resources"

# 2. CNI not ready
kubectl get pods -n kube-system | grep -E 'calico|cilium|flannel'

# 3. RBAC issues
kubectl get clusterrolebinding | grep metallb
```

### Issue: LoadBalancer Service stuck in Pending

**Symptom**: `EXTERNAL-IP` shows `<pending>` for LoadBalancer Service

**Solution**:
```bash
# Check if MetalLB controller is running
kubectl get pods -n metallb-system -l component=controller

# Check controller logs for errors
kubectl logs -n metallb-system deployment/controller

# Verify IPAddressPool exists
kubectl get ipaddresspool -n metallb-system

# Check if IP range is exhausted
kubectl get svc --all-namespaces -o wide | grep LoadBalancer

# Describe service for events
kubectl describe svc <service-name>
```

### Issue: External IP assigned but not accessible

**Symptom**: Service has EXTERNAL-IP but cannot be reached

**Solution**:
```bash
# Check speaker pods on all nodes
kubectl get pods -n metallb-system -l component=speaker -o wide

# Check speaker logs
kubectl logs -n metallb-system daemonset/speaker

# Test from cluster node
curl http://<EXTERNAL-IP>:<PORT>

# Check ARP table on router/other hosts
arp -a | grep <EXTERNAL-IP>

# Verify firewall rules
iptables -L -n | grep <PORT>

# Check if pods are running
kubectl get pods -l app=<your-app> -o wide
```

### Issue: IP address conflicts

**Symptom**: Network disruptions, duplicate IP warnings

**Solution**:
```bash
# Verify IP range doesn't conflict with DHCP
# Check router DHCP pool settings

# Scan network for IP usage
nmap -sn <YOUR-LAN-CIDR>

# Change MetalLB IP range
kubectl delete ipaddresspool default-pool -n metallb-system
# Re-run ansible role with new metallb_ip_range
```

### Issue: Slow failover during node failure

**Symptom**: 10-30 second downtime when node fails

**Solution**: This is expected in L2 mode (ARP cache timeout). For faster failover:
- Use BGP mode instead of L2 mode
- Implement application-level health checks
- Use multiple replicas with proper anti-affinity

### Issue: Uneven traffic distribution

**Symptom**: All traffic goes to one node

**Solution**: This is expected in L2 mode. For better distribution:
- Use BGP mode with ECMP routing
- Or use Ingress Controller (NGINX/Traefik) in front of MetalLB
- Or accept this limitation as trade-off for simplicity

## BGP Mode (Advanced)

For production environments, consider BGP mode for better load distribution.

### BGP Configuration Example

```yaml
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: router-peer
  namespace: metallb-system
spec:
  myASN: 64512
  peerASN: 64512
  peerAddress: <LAN-GATEWAY-IP>  # Router IP
---
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

Advantages over L2:
- True load balancing across nodes
- Sub-second failover
- Scales to large clusters

Requirements:
- BGP-capable router
- Network engineering knowledge
- More complex configuration

## Monitoring

### Prometheus Metrics

MetalLB exposes metrics on port 7472:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: metallb-metrics
  namespace: metallb-system
spec:
  selector:
    component: controller
  ports:
  - port: 7472
    targetPort: 7472
```

Key metrics:
- `metallb_allocator_addresses_in_use_total` - IPs currently allocated
- `metallb_allocator_addresses_total` - Total IPs in pool
- `metallb_speaker_announced` - Services announced by speaker

### Grafana Dashboard

Import MetalLB dashboard:
- Dashboard ID: 14127
- URL: https://grafana.com/grafana/dashboards/14127

## Performance Considerations

### IP Pool Sizing

Calculate required IPs:
```
Required IPs = (Number of LoadBalancer Services) × 1.5 (growth buffer)
```

Example:
- 10 services → 15 IPs → use /28 (16 IPs)
- 50 services → 75 IPs → use /25 (128 IPs)

### Node Resources

MetalLB is lightweight:
- Controller: ~50 MB RAM, minimal CPU
- Speaker: ~30 MB RAM per node, minimal CPU

### Network Bandwidth

In L2 mode:
- All traffic for one LoadBalancer IP goes through one node
- Size node network interface accordingly
- For high-bandwidth services, consider multiple LoadBalancers or BGP mode

## Security Considerations

### Network Isolation

MetalLB operates at network layer - apply additional security:

```yaml
# Restrict LoadBalancer access with NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-lb-access
spec:
  podSelector:
    matchLabels:
      app: sensitive-service
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 10.0.0.0/8  # Internal network only
```

### Service Annotations

```yaml
# Restrict LoadBalancer to internal network only
metadata:
  annotations:
    metallb.universe.tf/allow-shared-ip: "internal-only"
    # Combine with firewall rules
```

### RBAC

MetalLB requires ClusterRole permissions. Review and restrict if needed:

```bash
kubectl get clusterrole metallb-system:controller
kubectl get clusterrole metallb-system:speaker
```

## Upgrade Path

### Upgrade MetalLB Version

```yaml
# Update version
metallb_version: "v0.14.9"

# Re-run role
ansible-playbook playbooks/install_metallb.yml
```

### Migration from ConfigMap to CRDs

MetalLB v0.13+ uses CRDs instead of ConfigMap. This role uses CRDs by default.

If migrating from old ConfigMap-based setup:
1. Export existing config
2. Convert to IPAddressPool/L2Advertisement CRDs
3. Delete old ConfigMap
4. Apply new CRDs

## Integration with Ingress

MetalLB works great with Ingress Controllers:

```yaml
# Ingress Controller with MetalLB LoadBalancer
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer  # MetalLB assigns IP
  selector:
    app.kubernetes.io/name: ingress-nginx
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: https
    port: 443
    targetPort: https
```

Result: Single LoadBalancer IP serves all Ingress rules.

## Related Roles

- **k8s_cluster_manager**: Cluster initialization (required)
- **ingress_nginx_install**: NGINX Ingress Controller (commonly used with MetalLB)
- **traefik_install**: Traefik Ingress Controller (alternative)
- **cert_manager_install**: TLS certificate management

## Related Playbooks

- `config/playbooks/install_metallb.yml`: Main MetalLB deployment
- `config/playbooks/install_ingress_nginx.yml`: Ingress + LoadBalancer setup

## References

- [MetalLB Documentation](https://metallb.universe.tf/)
- [MetalLB GitHub](https://github.com/metallb/metallb)
- [Layer 2 Configuration](https://metallb.universe.tf/configuration/layer2/)
- [BGP Configuration](https://metallb.universe.tf/configuration/bgp/)
- [Kubernetes LoadBalancer Services](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)

## Changelog

- **2025-11**: Initial role creation for platform-iac
- **2025-11**: CRD-based configuration (IPAddressPool + L2Advertisement)
- **2025-11**: Declarative addon_state support

## Author

Platform Infrastructure Team

## License

Internal use only.
