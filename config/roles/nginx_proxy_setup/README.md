# Role: nginx_proxy_setup

## Description

Configures Nginx reverse proxy with Docker Compose for routing external traffic to internal services. This role sets up a centralized entry point for all HTTP/HTTPS and TCP/UDP traffic with SSL termination, load balancing, and advanced routing capabilities.

## Requirements

- Debian 11/12 or Ubuntu 20.04/22.04
- Root or sudo access
- Internet connectivity for Docker installation
- Valid SSL certificates (managed separately via certbot_setup role)

## Role Variables

### defaults/main.yml

```yaml
# Root directory for Nginx Proxy
nginx_proxy_root_dir: "/srv/nginx-proxy"

# Upstream services (IP:PORT mappings)
nginx_proxy_upstreams:
  # Stream (TCP/UDP) upstreams - no http:// prefix
  k8s_ingress: "10.10.10.200:443"
  gitlab_ssh: "10.10.10.104:22"
  proxmox_ssh: "10.10.10.101:22"

  # HTTP upstreams - with http:// prefix
  wiki_http: "http://10.10.10.5:3000"
  plantuml_http: "http://10.10.10.5:18080"
  minio_s3_api: "http://minioserver.bevz.net:9000"
  minio_console: "http://minioserver.bevz.net:9001"
  proxmox_https: "https://10.10.10.101:8006"

  # HTTP upstreams - without prefix (added in template)
  gitlab_http: "10.10.10.104:80"
  harbor_http: "10.10.10.103:80"
```

### Override Variables

```yaml
# Custom root directory
nginx_proxy_root_dir: "/opt/nginx-proxy"

# Custom upstream mappings
nginx_proxy_upstreams:
  app1: "http://192.168.1.100:8080"
  app2: "https://192.168.1.101:8443"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `nginx_proxy` | All Nginx proxy tasks |

## Dependencies

- Docker CE and Docker Compose (installed by this role)
- Optional: `certbot_setup` role for SSL certificates

## Example Playbook

### Basic Installation

```yaml
---
- name: Setup Nginx Reverse Proxy
  hosts: nginx_proxies
  become: yes
  roles:
    - nginx_proxy_setup
```

### With Custom Upstreams

```yaml
---
- name: Setup Nginx Proxy with Custom Services
  hosts: nginx_proxies
  become: yes
  vars:
    nginx_proxy_upstreams:
      gitlab_http: "10.10.10.104:80"
      harbor_http: "10.10.10.103:80"
      wiki_http: "http://10.10.10.5:3000"
  roles:
    - nginx_proxy_setup
```

### Complete Stack with SSL

```yaml
---
- name: Deploy Nginx Proxy with SSL
  hosts: nginx_proxies
  become: yes
  roles:
    - certbot_setup      # Setup Let's Encrypt certificates
    - nginx_proxy_setup  # Configure Nginx proxy
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Install Docker Dependencies     │
│ - ca-certificates, curl, gnupg  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Add Docker Repository           │
│ - Add GPG key                   │
│ - Configure APT source          │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install Docker CE               │
│ - docker-ce                     │
│ - docker-compose-plugin         │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create Directory Structure      │
│ - /srv/nginx-proxy/             │
│ - /srv/nginx-proxy/logs/        │
│ - /srv/nginx-proxy/html/        │
│ - /srv/nginx-proxy/nginx-conf/  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Deploy Nginx Configuration      │
│ - nginx.conf (main config)      │
│ - default.conf (vhosts)         │
│ - ssl-params.conf               │
│ - gzip.conf                     │
│ - proxy-params-websockets.conf  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Deploy Docker Compose Stack     │
│ - docker-compose.yml            │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Start Nginx Container           │
│ docker compose up -d            │
└─────────────────────────────────┘
```

## Configuration Files

### 1. nginx.conf - Main Configuration

Main Nginx configuration with worker processes, events, HTTP, and stream blocks.

**Features:**
- Worker auto-tuning
- HTTP/2 support
- Stream (TCP/UDP) proxying
- Gzip compression
- SSL optimization

### 2. default.conf - Virtual Hosts

Virtual host configurations for all proxied services.

**Example vhost:**
```nginx
# GitLab
server {
    listen 443 ssl http2;
    server_name gitlab.bevz.net;

    ssl_certificate /etc/letsencrypt/live/bevz.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/bevz.net/privkey.pem;

    location / {
        proxy_pass http://10.10.10.104:80;
        include /etc/nginx/proxy-params-websockets.conf;
    }
}
```

### 3. ssl-params.conf - SSL/TLS Hardening

Modern SSL/TLS configuration with strong ciphers and HSTS.

**Features:**
- TLS 1.2+ only
- Strong cipher suites
- OCSP stapling
- Security headers (HSTS, X-Frame-Options, etc.)

### 4. gzip.conf - Compression

Gzip compression for text-based content.

### 5. proxy-params-websockets.conf - Proxy Headers

Standard proxy headers including WebSocket support.

### 6. docker-compose.yml - Container Orchestration

Docker Compose configuration for Nginx container.

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "2222:2222"   # SSH to Proxmox
      - "2223:2223"   # SSH to GitLab
    volumes:
      - ./nginx-conf/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx-conf/default.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
```

## Post-Installation Verification

### Check Docker Service

```bash
systemctl status docker
docker ps
```

### Check Nginx Container

```bash
docker compose -f /srv/nginx-proxy/docker-compose.yml ps
docker logs nginx-proxy
```

### Test HTTP/HTTPS Access

```bash
# Test SSL certificate
curl -I https://gitlab.bevz.net

# Test specific vhost
curl -H "Host: harbor.bevz.net" https://your-proxy-ip/

# Check SSL grade
openssl s_client -connect gitlab.bevz.net:443 -servername gitlab.bevz.net
```

### Verify Port Bindings

```bash
ss -tlnp | grep -E ':(80|443|2222|2223)'
```

## Upstream Services

This role is designed to proxy the following services:

### HTTP/HTTPS Services

| Service | Domain | Upstream | Port |
|---------|--------|----------|------|
| GitLab | gitlab.bevz.net | 10.10.10.104:80 | 443 |
| Harbor | harbor.bevz.net | 10.10.10.103:80 | 443 |
| Wiki.js | wiki.bevz.net | 10.10.10.5:3000 | 443 |
| PlantUML | plantuml.bevz.net | 10.10.10.5:18080 | 443 |
| MinIO S3 | s3.bevz.net | minioserver:9000 | 443 |
| MinIO Console | minio.bevz.net | minioserver:9001 | 443 |
| Proxmox | pve.bevz.net | 10.10.10.101:8006 | 443 |
| Kubernetes | *.bevz.net | 10.10.10.200:443 | 443 |

### TCP/Stream Services

| Service | Port | Upstream |
|---------|------|----------|
| Proxmox SSH | 2222 | 10.10.10.101:22 |
| GitLab SSH | 2223 | 10.10.10.104:22 |
| Kubernetes Ingress | 443 | 10.10.10.200:443 |

## SSL Certificate Management

This role expects SSL certificates to be present in `/etc/letsencrypt/live/`. Use the `certbot_setup` role to manage certificates:

```yaml
- hosts: nginx_proxies
  become: yes
  roles:
    - role: certbot_setup
      vars:
        certbot_domains:
          - "bevz.net"
          - "*.bevz.net"
    - role: nginx_proxy_setup
```

## Troubleshooting

### Issue: Docker service not starting

**Symptom**: `systemctl status docker` shows failed state

**Solution**:
```bash
# Check Docker logs
journalctl -u docker -n 50

# Reinstall Docker
apt-get purge docker-ce docker-ce-cli containerd.io
apt-get autoremove
# Re-run ansible role
```

### Issue: Nginx container fails to start

**Symptom**: `docker logs nginx-proxy` shows errors

**Solution**:
```bash
# Check configuration syntax
docker run --rm -v /srv/nginx-proxy/nginx-conf:/etc/nginx:ro nginx:alpine nginx -t

# Check port conflicts
ss -tlnp | grep -E ':(80|443)'

# Review logs
docker logs nginx-proxy --tail 100
```

### Issue: SSL certificate not found

**Symptom**: Nginx fails with "no such file or directory" for SSL cert

**Solution**:
```bash
# Verify certificate exists
ls -la /etc/letsencrypt/live/bevz.net/

# Run certbot_setup role first
ansible-playbook -i inventory playbooks/install_certbot.yml

# Temporarily comment out SSL in default.conf
```

### Issue: Upstream service unreachable

**Symptom**: 502 Bad Gateway errors

**Solution**:
```bash
# Test upstream connectivity from proxy host
curl -v http://10.10.10.104:80
telnet 10.10.10.104 80

# Check firewall rules
iptables -L -n

# Verify upstream service is running
ssh user@10.10.10.104 'systemctl status gitlab'
```

### Issue: WebSocket connections failing

**Symptom**: WebSocket upgrade errors in logs

**Solution**: Verify proxy-params-websockets.conf is included:

```nginx
location / {
    proxy_pass http://upstream;
    include /etc/nginx/proxy-params-websockets.conf;  # ← Required
}
```

## Security Considerations

### Network Isolation

- Nginx proxy runs in Docker network
- Backend services should be firewalled from direct internet access
- Only proxy host should have public IP

### SSL/TLS Configuration

- TLS 1.2+ only (configured in ssl-params.conf)
- Strong cipher suites (ECDHE, AES-GCM)
- HSTS enabled (365 days)
- OCSP stapling enabled

### Rate Limiting

Consider adding rate limiting for public endpoints:

```nginx
# In nginx.conf http block
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;

# In default.conf location block
limit_req zone=general burst=20 nodelay;
```

### Monitoring

Monitor Nginx access and error logs:

```bash
# Access logs
docker logs nginx-proxy -f

# Error logs
tail -f /srv/nginx-proxy/logs/error.log

# Access stats
docker exec nginx-proxy tail -f /var/log/nginx/access.log | grep -v "health"
```

## Performance Tuning

### Worker Processes

Nginx automatically tunes workers based on CPU cores. Override if needed:

```nginx
# nginx.conf
worker_processes 4;  # Manual override
```

### Connection Limits

```nginx
# nginx.conf
events {
    worker_connections 2048;  # Increase for high traffic
}
```

### Keepalive

```nginx
# nginx.conf http block
keepalive_timeout 65;
keepalive_requests 1000;
```

### Buffer Sizes

```nginx
# default.conf
proxy_buffer_size 4k;
proxy_buffers 8 4k;
proxy_busy_buffers_size 8k;
```

## Related Roles

- **certbot_setup**: SSL certificate management (recommended)
- **set_timezone**: System timezone configuration

## Related Playbooks

- `config/playbooks/setup_nginx-proxy.yml`: Main deployment playbook
- `config/playbooks/install_certbot.yml`: SSL certificate setup

## References

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Nginx Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)

## Changelog

- **2025-11**: Initial role creation for platform-iac
- **2025-11**: Added WebSocket support and security hardening

## Author

Platform Infrastructure Team

## License

Internal use only.
