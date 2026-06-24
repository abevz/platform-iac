# Documentation Index

Complete documentation index for the Platform Infrastructure as Code project.

## 📚 Main Documentation

| Document | Description | Audience |
|----------|-------------|----------|
| [Main README](../README.md) | Project overview and setup instructions | Everyone |
| [Complete Documentation](./README.md) | Full platform documentation with workflows | Operators, Developers |
| [Architecture Guide](./architecture.md) | Visual architecture and component diagrams | Architects, DevOps |
| **[IAC Wrapper Guide](./iac-wrapper.md)** ⭐ | Complete iac-wrapper.sh command reference | DevOps, Operators |
| [Monitoring Runbook](./runbook-monitoring.md) | Monitoring operations and alert handling | Operators, On-call |
| [RustFS Migration Runbook](./runbook-rustfs-minio-replacement.md) | Completed MinIO-to-RustFS migration, validation, and rollback | Operators |
| [Secrets Architecture](./secrets-architecture.md) | Vault/ESO runtime secrets, manual unseal, backup, and restore | Operators, DevSecOps |
| [Architecture Decisions](./decisions/) | ADRs for secrets and observability decisions | Architects, Operators |
| [Cheat Sheet](./cheatsheet.md) | Quick command reference | Daily users |

## 🎭 Role Documentation

### Overview
| Document | Description |
|----------|-------------|
| [All Roles Overview](../config/roles/README.md) | Complete role catalog with usage patterns |
| [Quick Reference](../config/roles/QUICK_REFERENCE.md) | Fast lookup for role commands and tags |

### Infrastructure Roles

| Role | Description | Documentation |
|------|-------------|---------------|
| k8s_bootstrap_node | Bootstrap Kubernetes nodes with containerd | [README](../config/roles/k8s_bootstrap_node/README.md) |
| k8s_cluster_manager | Initialize control plane and join workers | - |
| set_timezone | Configure system timezone | - |
| nginx_proxy_setup | Nginx reverse proxy with Docker Compose | - |
| certbot_setup | Let's Encrypt SSL certificate automation | - |

### Networking Roles

| Role | Description | Documentation |
|------|-------------|---------------|
| calico_install_manifest | Install Calico CNI via manifests | - |
| calico_install_helm | Install Calico CNI via Helm | - |
| cilium_install_helm | Install Cilium CNI with eBPF | - |
| metallb_install | LoadBalancer for bare-metal | - |
| ingress_nginx_install | NGINX Ingress Controller | - |
| traefik_install | Traefik Ingress Controller | - |
| istio_install | Istio Service Mesh | - |

### Security Roles

| Role | Description | Documentation |
|------|-------------|---------------|
| falco_install_helm | Runtime security with Falco | [README](../config/roles/falco_install_helm/README.md) |
| falco_install_package | Falco system package installation | - |
| trivy_operator_deploy | Vulnerability scanning operator | - |
| trivy_package_install | Trivy CLI tool | - |
| kube_bench_run | CIS Kubernetes Benchmark | [README](../config/roles/kube_bench_run/README.md) |
| apparmor_configure | AppArmor security profiles | - |
| cert_manager_install | TLS certificate management | - |
| vault_server | Vault server with manual unseal and Raft snapshots | [README](../config/roles/vault_server/README.md) |

### Application Delivery

| Role | Description | Documentation |
|------|-------------|---------------|
| argocd_install | GitOps continuous delivery | [README](../config/roles/argocd_install/README.md) |
| bom_install | Bill of Materials tooling | - |

## 🛠️ Tools Documentation

| Tool | Description | Location |
|------|-------------|----------|
| iac-wrapper.sh | Main orchestration script | [tools/iac-wrapper.sh](../tools/iac-wrapper.sh) |
| tofu_inventory.py | Dynamic Ansible inventory | [tools/tofu_inventory.py](../tools/tofu_inventory.py) |
| add_pihole_dns.py | Pi-hole DNS automation | [tools/add_pihole_dns.py](../tools/add_pihole_dns.py) |

## 📖 Usage Guides

### Getting Started

1. **[Prerequisites](./README.md#prerequisites)** - Required tools and access
2. **[Initial Setup](./README.md#initial-setup)** - First-time configuration
3. **[Deploy Infrastructure](./README.md#deploy-infrastructure)** - VM provisioning
4. **[Bootstrap Kubernetes](./README.md#bootstrap-kubernetes)** - Cluster setup
5. **[Install Add-ons](./README.md#install-add-ons)** - Additional components

### Common Tasks

- **[Deploy New Cluster](./README.md#deploy-new-cluster)** - Step-by-step guide
- **[Add Worker Node](./README.md#add-worker-node)** - Cluster scaling
- **[Upgrade Kubernetes](./README.md#upgrade-kubernetes-version)** - Version updates
- **[Run Security Audit](./README.md#run-security-audit)** - CIS compliance check
- **[Backup and Restore](./README.md#backup-and-restore)** - Disaster recovery

### Quick References

- **[Ansible Tags](./cheatsheet.md#ansible-tags)** - All available tags
- **[kubectl Commands](./cheatsheet.md#kubernetes)** - Common kubectl usage
- **[Debugging](./cheatsheet.md#debugging)** - Troubleshooting guide
- **[Security Operations](./cheatsheet.md#security-operations)** - Security commands

## 🏗️ Architecture Documentation

### System Architecture

- **[High-Level Architecture](./architecture.md#high-level-architecture)** - Component overview
- **[Deployment Workflow](./architecture.md#deployment-workflow)** - Step-by-step flow
- **[Security Layers](./architecture.md#security-layers)** - Defense in depth
- **[Network Architecture](./architecture.md#network-architecture)** - Network topology

### Component Details

- **[Component Dependencies](./architecture.md#component-dependencies)** - Dependency graph
- **[Role Execution Flow](./architecture.md#role-execution-flow)** - Ansible execution order
- **[CKS Exam Coverage](./architecture.md#cks-exam-coverage)** - Security certification mapping

## 🔐 Security Documentation

### Hardening Guides

| Topic | Documentation |
|-------|---------------|
| Cluster Security | [README](./README.md#security-best-practices) |
| RBAC Configuration | [cheatsheet](./cheatsheet.md#rbac) |
| Network Policies | [cheatsheet](./cheatsheet.md#network-policies) |
| Pod Security Standards | [README](./README.md#pod-security-standards) |

### Security Tools

| Tool | Purpose | Documentation |
|------|---------|---------------|
| Falco | Runtime threat detection | [Role README](../config/roles/falco_install_helm/README.md) |
| Trivy | Vulnerability scanning | - |
| kube-bench | CIS benchmark compliance | [Role README](../config/roles/kube_bench_run/README.md) |
| AppArmor | Mandatory access control | - |

### Compliance

- **[CIS Benchmark](./architecture.md#cks-exam-coverage)** - Compliance status
- **[CKS Preparation](../kubernetes/cks-prep/README.md)** - Exam resources
- **[Security Policies](../kubernetes/policies/README.md)** - Policy examples

## 📊 Operational Documentation

### Monitoring & Observability

- **[Logs](./cheatsheet.md#system-logs)** - Log locations and commands
- **[Metrics](./cheatsheet.md#monitoring)** - Resource monitoring
- **[Debugging](./cheatsheet.md#debugging)** - Troubleshooting procedures

### Maintenance

- **[Certificate Management](./cheatsheet.md#certificate-management)** - Cert rotation
- **[Backup & Restore](./cheatsheet.md#backup--restore)** - Disaster recovery
- **[Upgrade Procedures](./cheatsheet.md#upgrade)** - Version upgrades

### Troubleshooting

- **[Common Issues](./README.md#troubleshooting)** - FAQ and solutions
- **[Emergency Procedures](./cheatsheet.md#emergency-procedures)** - Critical issues
- **[Debug Commands](./cheatsheet.md#debugging)** - Diagnostic tools

## 🎓 Training & Reference

### CKS Exam Preparation

- **[CKS Coverage Map](./architecture.md#cks-exam-coverage)** - Exam domain mapping
- **[Practice Resources](../kubernetes/cks-prep/README.md)** - Hands-on examples
- **[Security Scenarios](../config/roles/falco_install_helm/README.md#test-falco-detection)** - Real-world tests

### Best Practices

- **[Ansible Best Practices](../config/roles/README.md#usage-patterns)** - Role development
- **[Kubernetes Best Practices](./README.md#security-best-practices)** - Production tips
- **[Security Best Practices](./README.md#security-best-practices)** - Hardening guide

### References

| Resource | Link |
|----------|------|
| Kubernetes Documentation | https://kubernetes.io/docs/ |
| Ansible Documentation | https://docs.ansible.com/ |
| Falco Documentation | https://falco.org/docs/ |
| CIS Benchmark | https://www.cisecurity.org/benchmark/kubernetes |
| CNCF CKS Curriculum | https://github.com/cncf/curriculum |

## 🔄 Update History

| Date | Changes | Author |
|------|---------|--------|
| 2025-11 | Initial comprehensive documentation | Platform Team |
| 2025-11 | Added role-specific READMEs | Platform Team |
| 2025-11 | Created architecture diagrams | Platform Team |
| 2025-11 | Added cheat sheet and quick reference | Platform Team |

## 📝 Documentation Standards

### Creating New Documentation

When adding new documentation:

1. **Follow the template structure** from existing docs
2. **Include practical examples** with code snippets
3. **Add troubleshooting sections** for common issues
4. **Link to related documentation** for context
5. **Update this index** to include new documents

### Documentation Template

```markdown
# Component Name

## Description
Brief overview of the component

## Requirements
Prerequisites and dependencies

## Variables
Configuration options

## Usage
How to use the component

## Examples
Practical examples

## Troubleshooting
Common issues and solutions

## Related Documentation
Links to other relevant docs
```

## 🆘 Getting Help

### Documentation Issues

If you find documentation issues:

1. Check existing docs for updates
2. Review the [Quick Reference](./cheatsheet.md)
3. Consult the [Troubleshooting Guide](./README.md#troubleshooting)
4. Contact the Platform Team

### Contributing

To contribute to documentation:

1. Follow the documentation standards above
2. Test all examples and commands
3. Use clear, concise language
4. Include visual aids where helpful
5. Update the index when adding new docs

## 📞 Support Resources

| Resource | Purpose | Location |
|----------|---------|----------|
| Main README | Project overview | [README.md](../README.md) |
| Architecture Guide | System design | [architecture.md](./architecture.md) |
| Cheat Sheet | Quick commands | [cheatsheet.md](./cheatsheet.md) |
| Role Documentation | Ansible roles | [config/roles/](../config/roles/) |

## 🔗 Quick Links

### Most Used Documentation

1. [Quick Start Guide](./README.md#quick-start)
2. [Ansible Cheat Sheet](./cheatsheet.md)
3. [Role Overview](../config/roles/README.md)
4. [Architecture Diagrams](./architecture.md)
5. [Troubleshooting Guide](./README.md#troubleshooting)

### Security Documentation

1. [Falco Setup](../config/roles/falco_install_helm/README.md)
2. [CIS Benchmark](../config/roles/kube_bench_run/README.md)
3. [Security Best Practices](./README.md#security-best-practices)

### Operations

1. [Deployment Workflow](./architecture.md#deployment-workflow)
2. [Maintenance Procedures](./cheatsheet.md#maintenance)
3. [Emergency Procedures](./cheatsheet.md#emergency-procedures)

---

**Navigation:**
- [← Back to Project Root](../README.md)
- [Complete Documentation →](./README.md)
- [Quick Reference →](./cheatsheet.md)
- [Architecture →](./architecture.md)

**Last Updated**: November 2025
**Documentation Version**: 1.0
**Project**: platform-iac
