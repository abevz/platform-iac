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
- **Main worktree:** Treat `<repo>/main` as read/update/status only
- **Branches:** Feature branches from `main`, merge via PR
- **Worktrees:** Make every code or documentation change in a sibling worktree on a non-`main` branch
- **Task shape:** One task means one branch, one sibling worktree, one PR, and cleanup after merge
- **Cleanup:** Remove completed worktrees with `git worktree remove`, not raw directory deletion
- **Merge policy:** Use a normal merge commit by default; do not use squash or rebase merge unless explicitly requested for that PR
- **Pre-commit:** Must pass before any commit
- **No force push** to shared branches

## Attribution Rules (MANDATORY — NO EXCEPTIONS)

- **NEVER** add `Co-authored-by` or `Co-Authored-By` lines for AI tools in any commit
- **NEVER** add AI attribution trailers, bot identities, or agent names to commits, PR bodies, generated files, docs, examples, logs, or release notes
- **NEVER** mention Claude, Codex, ChatGPT, opencode, or other AI agents as authors or participants in repository-visible artifacts unless explicitly requested by the repo owner
- Keep commits and PRs as normal human project history using the existing Conventional Commits style

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

## Homelab Monitoring Conventions

- Deploy monitoring as a dedicated VM component (`infra/dev/monitoring`) managed via `tools/iac-wrapper.sh`
- Keep VM ID and IP last octet aligned when possible (e.g., `108` <-> `192.0.2.108`)
- Default stack is Docker Compose in role `config/roles/monitoring_stack`
- Public endpoint policy: expose only `grafana.<domain>` via `nginx_proxy_setup`; keep Prometheus/Alertmanager internal
- Alerting channel default is Telegram; tokens and chat IDs must come from SOPS-encrypted vars
- Proxmox API access for exporters must use token auth with least privilege (read-only/auditor scope)
- Treat known noisy AUX sensors as excluded from alert thresholds to avoid false positives
- Certbot renew must be automated via systemd timer and reload reverse proxy on successful renewal

## Dependencies

Required tools: `tofu`, `ansible-playbook`, `sops`, `yq`, `jq`, `nc`, `python3`, `pre-commit`

## References

- `.pre-commit-config.yaml` - Hook configuration
- `.tflint.hcl` - TFLint rules
- `.ansible-lint` - Ansible lint exclusions
- `config/ansible.cfg` - Ansible settings
- `tools/iac-wrapper.sh` - Main orchestration script
- `docs/` - Full documentation

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
