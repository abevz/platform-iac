# Sanitization Workflow

## Branch Model

| Branch | Purpose | Push to GitHub |
|--------|---------|----------------|
| `main` | Working branch (real IPs, domains, configs) | **BLOCKED** by pre-push hook |
| `github-public` | Sanitized mirror for public portfolio | Allowed |
| `feat/*`, `fix/*`, `chore/*` | Feature branches off main | Not pushed (local only) |

## Pre-push Hook

`.bare/hooks/pre-push` blocks any push of `main` to `github.com`. Only `github-public` is allowed through.

## Sanitization Rules

| Private value | Public placeholder |
|---------------|-------------------|
| `bevz.net` | `example.com` |
| `bevz.dev` | `example.com` |
| `gitlab.bevz.net` | `gitlab.example.com` |
| `s3.minio.bevz.net` | `s3.minio.example.com` |
| `minio.bevz.net` | `minio.example.com` |
| `10.10.10.x` | `192.0.2.x` (RFC 5737) |

## Publishing Workflow

```bash
# 1. Switch to github-public branch
git checkout github-public

# 2. Cherry-pick commits from main (without committing)
git cherry-pick --no-commit <commit-hash>

# 3. Sanitize
tools/sanitize-for-github.sh --all

# 4. Verify no private values remain
tools/sanitize-for-github.sh --check

# 5. Commit and push
git commit -m "docs: add monitoring vault agent integration"
git push origin github-public

# 6. Switch back
git checkout main
```

## Script Usage

```bash
tools/sanitize-for-github.sh              # sanitize staged files only
tools/sanitize-for-github.sh --all        # sanitize all tracked files
tools/sanitize-for-github.sh --dry-run    # preview changes
tools/sanitize-for-github.sh --check      # verify no private values (CI-friendly)
tools/sanitize-for-github.sh --strip-git  # rewrite branch to remove Co-Authored-By trailers
```

## Git History Sanitization

Commits cherry-picked from `main` may contain `Co-Authored-By` trailers. Before pushing `github-public`:

```bash
git checkout github-public
tools/sanitize-for-github.sh --strip-git
git push origin github-public --force
```

## What's Already Protected by .gitignore

These never reach any branch:
- `*.tfstate`, `*.tfstate.backup`
- `*.tfvars` (only `*.tfvars.example` tracked)
- `*.sops.yml` (only `*.sops.yml.example` tracked)
- `*.key`, `*.pem`, `*.p12`, `*.pfx`
- `config/platform.conf`
- `config/inventory/static.ini`
- `keys/`, `.venv/`, `.terraform/`
