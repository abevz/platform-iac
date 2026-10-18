# platform-iac

OpenTofu module examples for Proxmox, reusable Ansible roles and local validation fixtures.

## Public example scope

This repository is an allowlisted public snapshot. `PUBLIC-ALLOWLIST.txt` enumerates every published path. Runtime inventories, encrypted secrets, credentials, private keys, certificates, state, saved plans, internal operations reports and personal contact data are excluded.

Domains under example.com/example.internal and addresses in 192.0.2.0/24 and 198.51.100.0/24 are documentation values. Host and cluster names are generic. CIDR prefixes broader than /24 are reduced to documentation ranges; this is an illustrative configuration, not a ready-to-apply environment. Supply your own reviewed inventory, credentials, keys, backend and networking before deployment. Secret references name required runtime inputs; they do not contain secret values.

Dependency versions retain the reviewed source baseline and selected patch/minor updates. Major migrations are excluded. No deployment or cloud mutation was performed when validating this snapshot.

## Local validation

Use an isolated Python environment with `tools/ci/requirements.txt`. Install the collections from `config/requirements.yml` and the existing implicit `ansible.posix` requirement into an isolated collection directory. Initialize each OpenTofu module with `tofu init -backend=false -input=false`, then run `tofu validate`. Run `pre-commit run --all-files`, `python tests/test_argocd_upgrade.py` and the local exporter contract fixture. The backend and encryption configuration are deliberately not published.
