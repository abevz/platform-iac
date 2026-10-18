#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf '%s\n' "test_vault_snapshot_backup: $*" >&2
  exit 1
}

rendered_script="$test_root/vault-snapshot-backup"
role_id_file="$test_root/snapshot-role-id"
secret_id_file="$test_root/snapshot-secret-id"
snapshot_dir="$test_root/snapshots"
vault_log="$test_root/vault.log"

vars_json="$(jq -cn \
  --arg role_id_file "$role_id_file" \
  --arg secret_id_file "$secret_id_file" \
  --arg snapshot_dir "$snapshot_dir" \
  '{vault_snapshot_vault_addr: "https://127.0.0.1:8200", vault_snapshot_tls_server_name: "vault.test", vault_snapshot_role_id_file: $role_id_file, vault_snapshot_secret_id_file: $secret_id_file, vault_backup_dir: $snapshot_dir, vault_snapshot_local_retention_days: 14, vault_backup_s3_enabled: false, vault_backup_rclone_enabled: false, vault_backup_rclone_target: "", vault_backup_rclone_config_file: "/unused/rclone.conf", vault_config_dir: "/unused"}')"

ANSIBLE_CONFIG="$repo_root/config/ansible.cfg" ansible localhost -i localhost, -c local \
  -m ansible.builtin.template \
  -a "src=${repo_root}/config/roles/vault_server/templates/vault-snapshot-backup.sh.j2 dest=${rendered_script} mode=0700" \
  -e "$vars_json" >/dev/null
bash -n "$rendered_script"

mkdir -p "$test_root/bin"
cat > "$test_root/bin/vault" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "$1" == "status" ]]; then
  printf '%s|%s\n' "$VAULT_ADDR" "$VAULT_TLS_SERVER_NAME" >> "$TEST_VAULT_LOG"
  case "$TEST_VAULT_STATE" in
    unavailable) exit 1 ;;
    uninitialized) printf '%s\n' '{"initialized":false,"sealed":true}' ;;
    sealed) printf '%s\n' '{"initialized":true,"sealed":true}'; exit 2 ;;
    healthy) printf '%s\n' '{"initialized":true,"sealed":false}' ;;
    *) exit 99 ;;
  esac
elif [[ "$1" == "write" ]]; then
  printf '%s\n' 'test-token'
elif [[ "$1 $2 $3 $4" == "operator raft snapshot save" ]]; then
  : > "$5"
else
  exit 98
fi
EOF

cat > "$test_root/bin/install" <<'EOF'
#!/bin/bash
mkdir -p "${@: -1}"
EOF

for command_name in chown chmod find; do
  cat > "$test_root/bin/$command_name" <<'EOF'
#!/bin/bash
exit 0
EOF
done
/usr/bin/chmod 0755 "$test_root/bin/"*

export PATH="$test_root/bin:$PATH"
export TEST_VAULT_LOG="$vault_log"

expect_failure() {
  local state="$1"
  local expected="$2"
  local output="$test_root/${state}.out"
  if TEST_VAULT_STATE="$state" "$rendered_script" >"$output" 2>&1; then
    fail "$state unexpectedly succeeded"
  fi
  grep -Fq "$expected" "$output" || fail "$state did not report: $expected"
}

expect_failure unavailable "Vault status is unavailable"
expect_failure uninitialized "Vault is not initialized"
expect_failure sealed "Vault is sealed"
expect_failure healthy "AppRole credentials missing"

printf '%s\n' 'test-role-id' > "$role_id_file"
printf '%s\n' 'test-secret-id' > "$secret_id_file"
TEST_VAULT_STATE=healthy "$rendered_script" > "$test_root/healthy.out"

grep -Fqx 'https://127.0.0.1:8200|vault.test' "$vault_log" || \
  fail "rendered script did not use the verified local TLS endpoint"
compgen -G "$snapshot_dir/vault-raft-*.snap" >/dev/null || \
  fail "healthy Vault did not produce a snapshot"
grep -Fq "Created local snapshot" "$test_root/healthy.out" || \
  fail "successful snapshot was not logged"
