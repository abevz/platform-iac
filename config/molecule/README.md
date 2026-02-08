# Molecule Testing Framework

Shared Molecule configuration for testing Ansible roles on Proxmox VMs.

## Architecture

```
molecule/
├── shared/                    # Shared components
│   ├── create.yml             # VM provisioning via OpenTofu
│   ├── destroy.yml            # VM cleanup
│   └── testinfra/
│       └── conftest.py        # Shared pytest fixtures
├── mailserver/                # Mailserver scenario
│   ├── molecule.yml           # Scenario config
│   ├── converge.yml           # Role application
│   └── tests/
│       └── test_mailserver.py # Testinfra tests
└── requirements.txt           # Python dependencies
```

## Quick Start

### Install dependencies

```bash
pip install -r molecule/requirements.txt
```

### Run full test cycle

```bash
cd config/molecule/mailserver
molecule test
```

### Run individual phases

```bash
# Create VM only
molecule create -s mailserver

# Apply role
molecule converge -s mailserver

# Run tests without destroying
molecule verify -s mailserver

# SSH into test VM
molecule login -s mailserver

# Destroy VM
molecule destroy -s mailserver
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MOLECULE_SSH_USER` | SSH user for VM | `ubuntu` |
| `MOLECULE_SSH_KEY` | Path to SSH private key | `~/.ssh/id_ed25519` |
| `MOLECULE_TEST_HOST` | Use existing VM IP (skip tofu) | - |
| `MOLECULE_KEEP_VM` | Don't destroy VM after test | `false` |

## Scenarios

### mailserver

Tests the `mailserver_setup` role:

- Creates VM via `infra/dev/mailserver/` OpenTofu config
- Applies `mailserver_setup` role
- Verifies:
  - Directory structure (`/opt/mailserver/*`)
  - File permissions (`mailserver.env` mode 0600)
  - Docker-compose configuration
  - Docker service status

### Adding New Scenarios

1. Create scenario directory:
   ```bash
   mkdir -p molecule/newscenario/tests
   ```

2. Create `molecule.yml`:
   ```yaml
   driver:
     name: delegated
   provisioner:
     playbooks:
       create: ../shared/create.yml
       destroy: ../shared/destroy.yml
   ```

3. Create `converge.yml` with your role

4. Add Testinfra tests in `tests/test_*.py`

## Integration with OpenTofu

The delegated driver uses OpenTofu to provision real VMs:

1. Looks for tofu config at `infra/dev/{scenario_name}/`
2. Runs `tofu init && tofu apply`
3. Extracts VM IP from `tofu output -json`
4. Configures SSH connection

To skip tofu and use existing VM:
```bash
export MOLECULE_TEST_HOST=192.168.1.100
molecule test -s mailserver
```

## CI/CD Integration

```yaml
# .github/workflows/molecule.yml
jobs:
  test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: pip install -r config/molecule/requirements.txt
      - name: Run Molecule
        run: |
          cd config/molecule/mailserver
          molecule test
        env:
          MOLECULE_SSH_KEY: ${{ secrets.SSH_KEY_PATH }}
```

## Testinfra Examples

```python
# Test file exists with correct permissions
def test_config_file(host):
    f = host.file("/opt/app/config.yml")
    assert f.exists
    assert f.mode == 0o644
    assert f.user == "root"

# Test service is running
def test_service(host):
    svc = host.service("nginx")
    assert svc.is_running
    assert svc.is_enabled

# Test port is listening
def test_port(host):
    assert host.socket("tcp://0.0.0.0:443").is_listening
```

## Troubleshooting

### SSH connection issues

```bash
# Check VM is accessible
ssh -i ~/.ssh/id_ed25519 ubuntu@$(tofu -chdir=infra/dev/mailserver output -raw vm_ip)

# Verbose molecule output
molecule --debug test -s mailserver
```

### Keep VM for debugging

```bash
export MOLECULE_KEEP_VM=true
molecule test -s mailserver

# Login and inspect
molecule login -s mailserver
```
