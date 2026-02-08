# Role: certbot_setup

## Description

Automates SSL/TLS certificate management using **Let's Encrypt** and **Certbot** with DNS-01 challenge validation via **certbot-dns-multi** plugin. Supports wildcard certificates and automated renewal for multiple domains with Cloudflare DNS provider integration.

## Requirements

- Debian 11/12 or Ubuntu 20.04/22.04
- Root or sudo access
- Cloudflare account with API token (for DNS-01 validation)
- SOPS-encrypted secrets file with Cloudflare credentials
- Internet connectivity for Let's Encrypt ACME server

## Role Variables

### defaults/main.yml

```yaml
# Python virtual environment path for Certbot
certbot_venv_path: "/opt/certbot"

# Path to DNS credentials file
certbot_credentials_path: "/etc/letsencrypt/dns-multi.ini"

# Email for Let's Encrypt notifications
certbot_email: "aleksey.bevz@gmail.com"

# List of domains to request certificates for
certbot_domains_to_create:
  - name: "bevz-net-wildcard"        # Certificate name
    domains:
      - "*.<your-domain>.com"                 # Wildcard domain
      - "<your-domain>.com"                   # Root domain

  - name: "bevz-dev-wildcard"
    domains:
      - "*.<your-dev-domain>.dev"
      - "<your-dev-domain>.dev"

  - name: "s3-minio-bevz-net"
    domains:
      - "s3.minio.<your-domain>.com"          # Single domain
```

### Override Variables

```yaml
# Custom certbot installation path
certbot_venv_path: "/usr/local/certbot"

# Custom credentials file location
certbot_credentials_path: "/root/.secrets/dns-multi.ini"

# Custom email
certbot_email: "admin@example.com"

# Custom domain list
certbot_domains_to_create:
  - name: "example-wildcard"
    domains:
      - "*.example.com"
      - "example.com"
```

### Required Secrets (via SOPS)

In `config/secrets/ansible/extra_vars.sops.yml`:

```yaml
cloudflare:
  api_token: "YOUR_CLOUDFLARE_API_TOKEN"
```

## Tags

| Tag | Purpose |
|-----|---------|
| `certbot` | All certbot tasks |

## Dependencies

- **SOPS**: For decrypting Cloudflare API token
- **Cloudflare DNS**: Domain must be managed by Cloudflare

## Example Playbook

### Basic Installation

```yaml
---
- name: Setup Let's Encrypt Certificates
  hosts: certbot_hosts
  become: yes
  vars_files:
    - ../secrets/ansible/extra_vars.sops.yml
  roles:
    - certbot_setup
```

### With Custom Domains

```yaml
---
- name: Setup Certificates for Multiple Domains
  hosts: web_servers
  become: yes
  vars_files:
    - ../secrets/ansible/extra_vars.sops.yml
  vars:
    certbot_email: "ssl-admin@example.com"
    certbot_domains_to_create:
      - name: "production-wildcard"
        domains:
          - "*.prod.example.com"
          - "prod.example.com"
      - name: "staging-wildcard"
        domains:
          - "*.staging.example.com"
          - "staging.example.com"
  roles:
    - certbot_setup
```

### Declarative Install/Uninstall

```yaml
# Install certbot and certificates
- hosts: certbot_hosts
  become: yes
  roles:
    - role: certbot_setup
      vars:
        addon_state: present

# Uninstall certbot and remove certificates
- hosts: certbot_hosts
  become: yes
  roles:
    - role: certbot_setup
      vars:
        addon_state: absent
```

## Task Workflow

```
┌─────────────────────────────────┐
│ Install Python3-venv            │
│ (for isolated Certbot env)      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create Python Virtual Env       │
│ /opt/certbot/                   │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Install Certbot + Plugins       │
│ - certbot                       │
│ - certbot-dns-multi             │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create Symlink                  │
│ /usr/bin/certbot → venv/certbot │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Create /etc/letsencrypt/        │
│ (certificate storage)           │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Verify Cloudflare Token         │
│ (from SOPS encrypted file)      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Deploy dns-multi.ini            │
│ (Cloudflare credentials)        │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Request Let's Encrypt Certs     │
│ (DNS-01 challenge per domain)   │
└─────────────────────────────────┘
```

## DNS-01 Challenge

This role uses **DNS-01** challenge validation, which:

- Allows wildcard certificates (e.g., `*.<your-domain>.com`)
- Works without exposing port 80/443
- Requires DNS provider API access (Cloudflare)
- More secure than HTTP-01 for internal infrastructure

### How DNS-01 Works

1. Certbot requests certificate from Let's Encrypt
2. Let's Encrypt provides a challenge token
3. Certbot adds TXT record to `_acme-challenge.your-domain.com`
4. Let's Encrypt verifies TXT record via DNS query
5. Certificate is issued if validation succeeds

## Cloudflare Configuration

### Generate API Token

1. Log in to Cloudflare dashboard
2. Go to **My Profile → API Tokens**
3. Click **Create Token**
4. Use **Edit zone DNS** template
5. Configure:
   - **Permissions**: Zone → DNS → Edit
   - **Zone Resources**: Include → Specific zone → `<your-domain>.com`
6. Copy the generated token

### Store Token Securely

```bash
# Edit SOPS encrypted file
cd config/secrets/ansible
sops extra_vars.sops.yml

# Add token
cloudflare:
  api_token: "your_cloudflare_token_here"
```

### Template: dns-multi.ini.j2

```ini
# /etc/letsencrypt/dns-multi.ini
dns_multi_credential_path_1 = /etc/letsencrypt/cloudflare.ini
```

Cloudflare credentials are automatically configured via `certbot-dns-multi` plugin.

## Certificate Locations

Certificates are stored in `/etc/letsencrypt/live/<cert-name>/`:

```
/etc/letsencrypt/live/
├── bevz-net-wildcard/
│   ├── fullchain.pem    # Certificate + CA bundle
│   ├── privkey.pem      # Private key
│   ├── cert.pem         # Certificate only
│   └── chain.pem        # CA bundle only
├── bevz-dev-wildcard/
│   └── ...
└── s3-minio-bevz-net/
    └── ...
```

## Post-Installation Verification

### Check Certbot Installation

```bash
certbot --version
# certbot 2.7.4

which certbot
# /usr/bin/certbot → /opt/certbot/bin/certbot
```

### List Certificates

```bash
certbot certificates
```

**Expected output:**
```
Certificate Name: bevz-net-wildcard
  Domains: *.<your-domain>.com <your-domain>.com
  Expiry Date: 2025-02-15 12:34:56+00:00 (VALID: 89 days)
  Certificate Path: /etc/letsencrypt/live/<your-domain>-wildcard/fullchain.pem
  Private Key Path: /etc/letsencrypt/live/<your-domain>-wildcard/privkey.pem
```

### Verify Certificate

```bash
openssl x509 -in /etc/letsencrypt/live/<your-domain>-wildcard/fullchain.pem -text -noout
```

### Test Certificate with Nginx

```bash
# Test SSL configuration
nginx -t

# Reload Nginx with new certificates
systemctl reload nginx
```

## Automatic Renewal

Let's Encrypt certificates expire after **90 days**. Certbot automatically creates a systemd timer for renewal.

### Check Renewal Timer

```bash
systemctl list-timers certbot.timer
systemctl status certbot.timer
```

### Manual Renewal Test

```bash
# Dry-run (no actual renewal)
certbot renew --dry-run

# Force renewal (if < 30 days until expiry)
certbot renew --force-renewal
```

### Renewal Process

Certbot automatically:
1. Checks certificates daily via systemd timer
2. Renews certificates < 30 days until expiry
3. Uses same DNS-01 challenge as initial issue
4. Reloads Nginx/Apache if configured

## Troubleshooting

### Issue: Cloudflare API token not found

**Symptom**: Role fails with "Variable 'cloudflare.api_token' not found"

**Solution**:
```bash
# Verify SOPS file exists
ls -la config/secrets/ansible/extra_vars.sops.yml

# Edit SOPS file
cd config/secrets/ansible
sops extra_vars.sops.yml

# Add token
cloudflare:
  api_token: "YOUR_TOKEN"

# Test decryption
sops -d extra_vars.sops.yml | grep cloudflare
```

### Issue: DNS validation timeout

**Symptom**: `Timeout during connect (likely firewall problem)`

**Solution**:
```bash
# Test Cloudflare API access
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Verify DNS propagation
dig +short TXT _acme-challenge.<your-domain>.com

# Check DNS plugin
certbot plugins
# Should list: dns-multi

# Retry with verbose output
certbot certonly --dns-multi --dns-multi-credentials /etc/letsencrypt/dns-multi.ini \
  -d "*.<your-domain>.com" -d "<your-domain>.com" --dry-run -v
```

### Issue: Rate limit exceeded

**Symptom**: `too many certificates already issued for: <your-domain>.com`

**Solution**: Let's Encrypt has rate limits:
- **50 certificates** per registered domain per week
- **5 duplicate certificates** per week

Wait for rate limit to reset or use `--dry-run` for testing.

### Issue: Certificate already exists

**Symptom**: `Certificate already exists, skipping`

**Solution**: This is expected behavior (idempotent). To force renewal:

```bash
certbot certonly --dns-multi \
  --dns-multi-credentials /etc/letsencrypt/dns-multi.ini \
  -d "*.<your-domain>.com" -d "<your-domain>.com" \
  --force-renewal
```

### Issue: Symlink conflict

**Symptom**: `/usr/bin/certbot` already exists

**Solution**:
```bash
# Remove old certbot
apt-get remove certbot

# Verify symlink
ls -la /usr/bin/certbot
# Should point to /opt/certbot/bin/certbot

# Re-run role if needed
ansible-playbook playbooks/install_certbot.yml
```

### Issue: Permission denied on /etc/letsencrypt

**Symptom**: `Permission denied: '/etc/letsencrypt'`

**Solution**:
```bash
# Fix permissions
chmod 700 /etc/letsencrypt
chown root:root /etc/letsencrypt

# Verify
ls -ld /etc/letsencrypt
```

## DNS Providers

While this role is configured for **Cloudflare**, `certbot-dns-multi` supports:

- Cloudflare
- AWS Route53
- Google Cloud DNS
- Azure DNS
- DigitalOcean
- Linode
- And 30+ others

### Adding Another DNS Provider

1. Update `dns-multi.ini.j2` template:
```ini
dns_multi_credential_path_1 = /etc/letsencrypt/cloudflare.ini
dns_multi_credential_path_2 = /etc/letsencrypt/route53.ini
```

2. Add provider credentials to SOPS:
```yaml
cloudflare:
  api_token: "token1"
aws:
  access_key: "key"
  secret_key: "secret"
```

3. Update template to include both providers

## Security Considerations

### Credential Protection

- `dns-multi.ini` has **0600** permissions (owner-only read/write)
- Cloudflare token stored in **SOPS encrypted** file
- Never commit plaintext tokens to git

### Certificate Storage

- `/etc/letsencrypt` has **0700** permissions
- Private keys are **0600** (owner-only read/write)
- Root access required to read certificates

### API Token Permissions

Cloudflare token should have **minimal permissions**:
- ✅ Zone → DNS → Edit (required for TXT records)
- ❌ Zone → Zone → Edit (not needed)
- ❌ Account → Account Settings (not needed)

### Monitoring

Monitor certificate expiry:

```bash
# Check expiry dates
certbot certificates | grep "Expiry Date"

# Set up monitoring alert (e.g., Prometheus, Zabbix)
# Alert if certificate expires in < 14 days
```

## Integration with Nginx

### Use Certificates in Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name *.<your-domain>.com;

    ssl_certificate /etc/letsencrypt/live/<your-domain>-wildcard/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<your-domain>-wildcard/privkey.pem;

    # Include SSL hardening
    include /etc/nginx/ssl-params.conf;
}
```

### Automatic Reload on Renewal

Create post-renewal hook:

```bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
#!/bin/bash
systemctl reload nginx
docker compose -f /srv/nginx-proxy/docker-compose.yml restart
```

Make executable:
```bash
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

## Performance Considerations

### Certificate Caching

Certbot caches certificates locally. Renewal only happens if < 30 days until expiry.

### DNS Propagation Time

DNS-01 challenge requires **DNS propagation** (typically 30-60 seconds). Certbot automatically waits for propagation.

### Rate Limits

Let's Encrypt rate limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week
- Use `--dry-run` for testing

## Declarative State Management

This role supports `addon_state` variable:

```yaml
# Install
addon_state: present

# Uninstall (removes certbot, certificates, credentials)
addon_state: absent
```

### What Gets Removed on Uninstall

- Python venv (`/opt/certbot/`)
- Certbot symlink (`/usr/bin/certbot`)
- Credentials file (`/etc/letsencrypt/dns-multi.ini`)
- **Note**: Certificates in `/etc/letsencrypt/live/` are preserved for safety

## Related Roles

- **nginx_proxy_setup**: Nginx reverse proxy (consumes certificates)
- **set_timezone**: System timezone configuration

## Related Playbooks

- `config/playbooks/install_certbot.yml`: Main deployment playbook
- `config/playbooks/setup_nginx-proxy.yml`: Full nginx + certbot stack

## References

- [Certbot Documentation](https://certbot.eff.org/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [certbot-dns-multi Plugin](https://github.com/alexzorin/certbot-dns-multi)
- [Cloudflare API Tokens](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)

## Changelog

- **2025-11**: Initial role creation for platform-iac
- **2025-11**: Added wildcard certificate support via DNS-01
- **2025-11**: Integrated certbot-dns-multi for multi-provider support

## Author

Platform Infrastructure Team

## License

Internal use only.
