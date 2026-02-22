# AGENTS.md - AI Coding Agent Guidelines

> **Project:** platform-iac - Infrastructure as Code for Proxmox VE
> **Last Updated:** 2026-02-12

## Project Overview

Hybrid IaC solution using **OpenTofu** (Terraform) for VM provisioning and **Ansible** for configuration management on Proxmox VE. Supports Kubernetes clusters, databases, CI/CD, and various VM workloads.

## Build / Lint / Test Commands

### Pre-commit (Required Before All Commits)
```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hooks
pre-commit run terraform_fmt
pre-commit run terraform_tflint
pre-commit run terraform_tfsec
pre-commit run ansible-lint
```

### OpenTofu / Terraform
```bash
# Format code
tofu fmt -recursive

# Validate
tofu validate

# Lint (with project config)
tflint --config=.tflint.hcl

# Security scan
tfsec .
```

### Ansible
```bash
# Lint playbooks/roles
ansible-lint config/playbooks/ config/roles/

# Syntax check
ansible-playbook --syntax-check -i /dev/null config/playbooks/setup_k8s-lab-01.yml

# Run playbook (via wrapper)
./tools/iac-wrapper.sh configure dev k8s-lab-01
```

### Python
```bash
# No specific linter configured; follow PEP 8
python3 -m py_compile tools/*.py
```

### Bash
```bash
# Lint scripts
shellcheck tools/*.sh
```

## Code Style Guidelines

### Terraform / OpenTofu
- **Naming:** snake_case for variables, resources, outputs
- **Formatting:** 2-space indentation, run `tofu fmt` before commit
- **Variables:** Always mark sensitive values with `sensitive = true`
- **Comments:** Use `#` for single-line, describe "why" not "what"
- **Structure:** `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `backend.tf`
- **Strings:** Use double quotes consistently

### Ansible
- **Naming:** snake_case for variables, roles, playbooks
- **Indentation:** 2 spaces (YAML standard)
- **Module names:** Use FQCN (e.g., `ansible.builtin.shell`)
- **Variables:** Define defaults in `roles/<name>/defaults/main.yml`
- **Tags:** Use descriptive tags (e.g., `bootstrap_prereqs`, `containerd`)
- **Handlers:** Name with verbs (e.g., `restart_containerd`)
- **When clauses:** Place at end of task, use explicit conditions

### Bash Scripts
- **Shebang:** `#!/bin/bash`
- **Strict mode:** `set -euo pipefail` at start
- **Variables:** UPPER_CASE for constants, snake_case for others
- **Functions:** snake_case with `()` and `{}`
- **Quotes:** Always quote variables (e.g., `"$var"`)
- **Comments:** Section headers with `---`

### Python
- **Style:** PEP 8
- **Docstrings:** Use `"""` for functions
- **Imports:** Group stdlib first, then third-party, then local
- **Error handling:** Use try/except with specific exceptions
- **Comments:** Russian acceptable for internal notes, English for public API

## Secrets Management

- All secrets stored in `config/secrets/` as SOPS-encrypted YAML
- Never commit decrypted secrets (`.sops.yml` files are git-ignored)
- Use `.sops.yml.example` as templates
- Wrapper script auto-decrypts via `iac-wrapper.sh`

## Git Workflow

- **Conventional Commits:** `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- **Messages:** English, 1-2 lines, focus on "why"
- **Branches:** Feature branches from `main`, merge via PR
- **Pre-commit:** Must pass before any commit
- **No force push** to shared branches

## Common File Patterns

```
infra/<env>/<component>/    # Terraform projects
config/roles/<name>/        # Ansible roles
  ├── defaults/main.yml     # Default variables
  ├── tasks/main.yml        # Main tasks
  ├── handlers/main.yml     # Event handlers
tools/                      # Python/Bash utilities
docs/                       # Documentation
```

## Security Guidelines

- Never hardcode credentials in code
- Mark all sensitive TF variables with `sensitive = true`
- Use SOPS for secret encryption
- Run `tfsec` before committing TF changes
- Run `ansible-lint` before playbook changes
- Use `changed_when: false` for read-only shell commands

## Dependencies

Required tools: `tofu`, `ansible-playbook`, `sops`, `yq`, `jq`, `nc`, `python3`, `pre-commit`

## References

- `.pre-commit-config.yaml` - Hook configuration
- `.tflint.hcl` - TFLint rules
- `.ansible-lint` - Ansible lint exclusions
- `config/ansible.cfg` - Ansible settings
- `tools/iac-wrapper.sh` - Main orchestration script
- `docs/` - Full documentation
