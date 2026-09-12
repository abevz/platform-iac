#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf '%s\n' "test_vault_cert_sync_receiver: $*" >&2
  exit 1
}

assert_unchanged() {
  local before="$1"
  local after
  after="$(sha256sum "$tls_cert" "$tls_key")"
  [[ "$before" == "$after" ]] || fail "rejected input changed Vault TLS files"
}

payload() {
  local cert="$1"
  local key="$2"
  printf '%s\n' "vault-cert-sync-v1"
  base64 -w 0 "$cert"
  printf '\n'
  base64 -w 0 "$key"
  printf '\n'
}

expect_reject() {
  local name="$1"
  local before
  before="$(sha256sum "$tls_cert" "$tls_key")"
  if "$receiver" vault-cert-sync-v1 >/dev/null 2>&1; then
    fail "${name}: malformed input unexpectedly succeeded"
  fi
  assert_unchanged "$before"
}

run_receiver() {
  /usr/bin/sudo -n env \
    PATH="$PATH" \
    TEST_SYSTEMCTL_LOG="$TEST_SYSTEMCTL_LOG" \
    TEST_TLS_CERT="$TEST_TLS_CERT" \
    TEST_ACTIVE_CERT="$TEST_ACTIVE_CERT" \
    TEST_HUP_FAILED_ONCE="$TEST_HUP_FAILED_ONCE" \
    TEST_FAIL_FIRST_HUP="${TEST_FAIL_FIRST_HUP:-0}" \
    "$receiver" "$@"
}

make_certificate() {
  local name="$1"
  local hostname="$2"
  local days="$3"

  openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$test_root/${name}.key" \
    -out "$test_root/${name}.csr" \
    -subj "/CN=${hostname}" >/dev/null 2>&1
  printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$hostname" > "$test_root/${name}.ext"
  openssl x509 -req -sha256 -days "$days" \
    -in "$test_root/${name}.csr" \
    -CA "$test_root/ca.crt" \
    -CAkey "$test_root/ca.key" \
    -CAcreateserial \
    -out "$test_root/${name}.crt" \
    -extfile "$test_root/${name}.ext" >/dev/null 2>&1
  cat "$test_root/${name}.crt" "$test_root/ca.crt" > "$test_root/${name}.fullchain.pem"
}

tls_dir="$test_root/tls"
tls_cert="$tls_dir/fullchain.pem"
tls_key="$tls_dir/privkey.pem"
mkdir -p "$tls_dir" "$test_root/bin"

openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout "$test_root/ca.key" \
  -out "$test_root/ca.crt" \
  -subj '/CN=test-vault-cert-sync-ca' >/dev/null 2>&1
make_certificate old vault.test 7
make_certificate new vault.test 7
make_certificate wrong-host other.test 7
make_certificate wrong-key vault.test 7
make_certificate expired vault.test 0
cp "$test_root/old.fullchain.pem" "$tls_cert"
cp "$test_root/old.key" "$tls_key"
cp "$tls_cert" "$test_root/active-cert.pem"

cat > "$test_root/bin/systemctl" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
if [[ "$1" == "kill" ]]; then
  if [[ "${TEST_FAIL_FIRST_HUP:-0}" == "1" && ! -e "$TEST_HUP_FAILED_ONCE" ]]; then
    touch "$TEST_HUP_FAILED_ONCE"
  else
    cp "$TEST_TLS_CERT" "$TEST_ACTIVE_CERT"
  fi
fi
exit 0
EOF
cat > "$test_root/bin/curl" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$test_root/bin/docker" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$test_root/bin/openssl" <<'EOF'
#!/bin/bash
if [[ "$1" == "s_client" ]]; then
  cat "$TEST_ACTIVE_CERT"
  exit 0
fi
exec /usr/bin/openssl "$@"
EOF
cat > "$test_root/bin/sudo" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_SUDO_LOG"
exit 0
EOF
chmod 0755 "$test_root/bin/systemctl" "$test_root/bin/curl" "$test_root/bin/openssl"
chmod 0755 "$test_root/bin/docker"
chmod 0755 "$test_root/bin/sudo"

receiver="$test_root/vault-cert-sync-receive"
sed \
  -e 's/{% raw %}//g' \
  -e 's/{% endraw %}//g' \
  -e "s#{{ vault_cert_sync_receiver_expected_hostname | quote }}#'vault.test'#g" \
  -e "s#{{ vault_cert_sync_receiver_tls_cert_file | dirname | quote }}#'${tls_dir}'#g" \
  -e "s#{{ vault_cert_sync_receiver_tls_cert_file | quote }}#'${tls_cert}'#g" \
  -e "s#{{ vault_cert_sync_receiver_tls_key_file | quote }}#'${tls_key}'#g" \
  -e "s#{{ vault_cert_sync_receiver_tls_owner | quote }}#'$(id -un)'#g" \
  -e "s#{{ vault_cert_sync_receiver_tls_group | quote }}#'$(id -gn)'#g" \
  -e "s#{{ vault_cert_sync_receiver_vault_service | quote }}#'vault'#g" \
  -e "s#{{ vault_cert_sync_receiver_vault_port | quote }}#'8200'#g" \
  -e "s#{{ vault_cert_sync_receiver_min_validity_seconds | quote }}#'300'#g" \
  -e "s#{{ vault_cert_sync_receiver_trust_bundle | quote }}#'${test_root}/ca.crt'#g" \
  -e "s#{{ vault_cert_sync_receiver_lock_file | quote }}#'${test_root}/vault-cert-sync.lock'#g" \
  "$repo_root/config/roles/vault_cert_sync_receiver/templates/vault-cert-sync-receive.sh.j2" > "$receiver"
chmod 0700 "$receiver"

# Render with Ansible itself as well as the controlled test paths above. This
# catches Jinja/Bash delimiter collisions before a receiver template reaches a
# Vault host.
ansible_rendered_receiver="$test_root/vault-cert-sync-receive-ansible"
ANSIBLE_CONFIG="$repo_root/config/ansible.cfg" ansible localhost -i localhost, -c local \
  -m ansible.builtin.template \
  -a "src=${repo_root}/config/roles/vault_cert_sync_receiver/templates/vault-cert-sync-receive.sh.j2 dest=${ansible_rendered_receiver} mode=0700" \
  -e "vault_cert_sync_receiver_expected_hostname=vault.test" \
  -e "vault_cert_sync_receiver_tls_cert_file=${tls_cert}" \
  -e "vault_cert_sync_receiver_tls_key_file=${tls_key}" \
  -e "vault_cert_sync_receiver_tls_owner=$(id -un)" \
  -e "vault_cert_sync_receiver_tls_group=$(id -gn)" \
  -e "vault_cert_sync_receiver_vault_service=vault" \
  -e "vault_cert_sync_receiver_vault_port=8200" \
  -e "vault_cert_sync_receiver_min_validity_seconds=300" \
  -e "vault_cert_sync_receiver_trust_bundle=${test_root}/ca.crt" \
  -e "vault_cert_sync_receiver_lock_file=${test_root}/vault-cert-sync.lock" \
  >/dev/null
bash -n "$ansible_rendered_receiver"

sender_vars_json="$(jq -cn \
  --arg lineage 'bevz-net-wildcard' \
  --arg hostname 'vault.test' \
  --arg target_host '10.10.10.109' \
  --arg target_key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest' \
  --arg identity "${test_root}/source-key" \
  --arg known_hosts "${test_root}/known-hosts" \
  --arg ssh_config "${test_root}/ssh-config" \
  --arg helper "${test_root}/sender-helper" \
  '{certbot_vault_cert_sync_enabled: true, certbot_vault_cert_sync_lineage: $lineage, certbot_vault_cert_sync_expected_hostname: $hostname, certbot_vault_cert_sync_target_host: $target_host, certbot_vault_cert_sync_target_port: 22, certbot_vault_cert_sync_target_user: "vault-cert-sync", certbot_vault_cert_sync_target_host_key: $target_key, certbot_vault_cert_sync_identity_path: $identity, certbot_vault_cert_sync_known_hosts_path: $known_hosts, certbot_vault_cert_sync_ssh_config_path: $ssh_config, certbot_vault_cert_sync_helper_path: $helper, certbot_vault_cert_sync_service: "certbot-vault-cert-sync.service", certbot_vault_cert_sync_timer: "certbot-vault-cert-sync.timer", certbot_vault_cert_sync_on_calendar: "hourly", certbot_vault_cert_sync_randomized_delay_sec: "10m", certbot_vault_cert_sync_min_validity_seconds: 300, certbot_vault_cert_sync_timeout_seconds: 30}')"
receiver_vars_json="$(jq -cn \
  --arg hostname 'vault.test' \
  --arg cert "${tls_cert}" \
  --arg key "${tls_key}" \
  --arg owner "$(id -un)" \
  --arg group "$(id -gn)" \
  --arg trust "${test_root}/ca.crt" \
  --arg lock "${test_root}/vault-cert-sync.lock" \
  --arg script "${test_root}/receiver-target" \
  --arg wrapper "${test_root}/receiver-wrapper" \
  --arg public_key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest' \
  '{vault_cert_sync_receiver_expected_hostname: $hostname, vault_cert_sync_receiver_tls_cert_file: $cert, vault_cert_sync_receiver_tls_key_file: $key, vault_cert_sync_receiver_tls_owner: $owner, vault_cert_sync_receiver_tls_group: $group, vault_cert_sync_receiver_vault_service: "vault", vault_cert_sync_receiver_vault_port: 8200, vault_cert_sync_receiver_min_validity_seconds: 300, vault_cert_sync_receiver_trust_bundle: $trust, vault_cert_sync_receiver_lock_file: $lock, vault_cert_sync_receiver_script_path: $script, vault_cert_sync_receiver_wrapper_path: $wrapper, vault_cert_sync_receiver_sudo_path: "/usr/bin/sudo", vault_cert_sync_receiver_source_address: "10.10.10.105", vault_cert_sync_receiver_authorized_key: $public_key, vault_cert_sync_receiver_user: "vault-cert-sync"}')"

render_template() {
  local source_template="$1"
  local destination="$2"
  local variables_json="$3"

  ANSIBLE_CONFIG="$repo_root/config/ansible.cfg" ansible localhost -i localhost, -c local \
    -m ansible.builtin.template \
    -a "src=${source_template} dest=${destination}" \
    -e "$variables_json" >/dev/null
}

# Every new template is rendered by Ansible before its local parser is run.
render_template "$repo_root/config/roles/certbot_setup/templates/certbot-vault-cert-sync.sh.j2" "$test_root/sender-helper-ansible" "$sender_vars_json"
render_template "$repo_root/config/roles/certbot_setup/templates/certbot-renew-hook.sh.j2" "$test_root/certbot-renew-hook-ansible" "$sender_vars_json"
render_template "$repo_root/config/roles/certbot_setup/templates/vault-cert-sync-known-hosts.j2" "$test_root/known-hosts-ansible" "$sender_vars_json"
render_template "$repo_root/config/roles/certbot_setup/templates/vault-cert-sync-ssh-config.j2" "$test_root/ssh-config-ansible" "$sender_vars_json"
render_template "$repo_root/config/roles/certbot_setup/templates/certbot-vault-cert-sync.service.j2" "$test_root/certbot-vault-cert-sync.service" "$sender_vars_json"
render_template "$repo_root/config/roles/certbot_setup/templates/certbot-vault-cert-sync.timer.j2" "$test_root/certbot-vault-cert-sync.timer" "$sender_vars_json"
render_template "$repo_root/config/roles/vault_cert_sync_receiver/templates/vault-cert-sync-ssh-wrapper.sh.j2" "$test_root/receiver-wrapper-ansible" "$receiver_vars_json"
render_template "$repo_root/config/roles/vault_cert_sync_receiver/templates/authorized_keys.j2" "$test_root/authorized_keys-ansible" "$receiver_vars_json"
render_template "$repo_root/config/roles/vault_cert_sync_receiver/templates/sudoers.j2" "$test_root/sudoers-ansible" "$receiver_vars_json"
bash -n "$test_root/sender-helper-ansible" "$test_root/certbot-renew-hook-ansible" "$test_root/receiver-wrapper-ansible"
cp "$test_root/sender-helper-ansible" "$test_root/sender-helper"
chmod 0700 "$test_root/sender-helper"
ssh -F "$test_root/ssh-config-ansible" -G vault-cert-sync-target >/dev/null
/usr/sbin/visudo -cf "$test_root/sudoers-ansible" >/dev/null
systemd-analyze verify "$test_root/certbot-vault-cert-sync.service" "$test_root/certbot-vault-cert-sync.timer" >/dev/null
grep -Fqx 'vault-cert-sync-target ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest' "$test_root/known-hosts-ansible" || fail "Ansible did not render the pinned known_hosts line"
grep -Fq 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty,no-user-rc' "$test_root/authorized_keys-ansible" || fail "Ansible did not render SSH key restrictions"

export PATH="$test_root/bin:$PATH"
export TEST_SYSTEMCTL_LOG="$test_root/systemctl.log"
export TEST_TLS_CERT="$tls_cert"
export TEST_ACTIVE_CERT="$test_root/active-cert.pem"
export TEST_HUP_FAILED_ONCE="$test_root/hup-failed-once"
: > "$TEST_SYSTEMCTL_LOG"
export TEST_SUDO_LOG="$test_root/sudo.log"
: > "$TEST_SUDO_LOG"

# Render the sender with representative fixed values and require valid Bash.
sender="$test_root/certbot-vault-cert-sync"
sed \
  -e "s#{{ certbot_vault_cert_sync_lineage | quote }}#'bevz-net-wildcard'#g" \
  -e "s#{{ certbot_vault_cert_sync_expected_hostname | quote }}#'vault.test'#g" \
  -e "s#{{ certbot_vault_cert_sync_identity_path | quote }}#'${test_root}/source-key'#g" \
  -e "s#{{ certbot_vault_cert_sync_ssh_config_path | quote }}#'${test_root}/ssh-config'#g" \
  -e "s#{{ certbot_vault_cert_sync_min_validity_seconds | quote }}#'300'#g" \
  -e "s#{{ certbot_vault_cert_sync_timeout_seconds | quote }}#'30'#g" \
  "$repo_root/config/roles/certbot_setup/templates/certbot-vault-cert-sync.sh.j2" > "$sender"
bash -n "$sender"

# ssh-keygen -y may retain the source key comment. The Ansible expression used
# by the playbook must normalize it to the two-field authorized_keys value.
normalized_public_key="$(ansible localhost -i localhost, -c local \
  -m ansible.builtin.debug \
  -a 'msg={{ source_key.split()[:2] | join(" ") }}' \
  -e '{"source_key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest certbot-vault-cert-sync"}' \
  -o 2>&1)"
[[ "$normalized_public_key" == *'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest'* ]] || fail "Ansible did not normalize an SSH public-key comment"
[[ "$normalized_public_key" != *'certbot-vault-cert-sync'* ]] || fail "Ansible retained an SSH public-key comment"
public_key_match="$(ansible localhost -i localhost, -c local \
  -m ansible.builtin.debug \
  -a 'msg={{ source_key is match("^ssh-ed25519 [A-Za-z0-9+/=]+( \\S+)?$") }}' \
  -e '{"source_key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest certbot-vault-cert-sync"}' \
  -o 2>&1)"
[[ "$public_key_match" == *'"msg": true'* ]] || fail "Ansible did not accept a commented ed25519 public key"
tls_path_match="$(ansible localhost -i localhost, -c local \
  -m ansible.builtin.debug \
  -a 'msg={{ tls_cert is match("^/\\S+$") and tls_key is match("^/\\S+$") }}' \
  -e '{"tls_cert":"/etc/vault.d/tls/fullchain.pem","tls_key":"/etc/vault.d/tls/privkey.pem"}' \
  -o 2>&1)"
[[ "$tls_path_match" == *'"msg": true'* ]] || fail "Ansible did not accept fixed Vault TLS paths"

# The root receiver is reachable only through the forced-command wrapper. It
# must reject every original command except the protocol literal and pass no
# caller-controlled argument into sudo.
wrapper="$test_root/vault-cert-sync-ssh-wrapper"
sed \
  -e "s#{{ vault_cert_sync_receiver_sudo_path | quote }}#'${test_root}/bin/sudo'#g" \
  -e "s#{{ vault_cert_sync_receiver_script_path | quote }}#'${test_root}/receiver-target'#g" \
  "$repo_root/config/roles/vault_cert_sync_receiver/templates/vault-cert-sync-ssh-wrapper.sh.j2" > "$wrapper"
chmod 0700 "$wrapper"
if SSH_ORIGINAL_COMMAND='uname -a' "$wrapper" >/dev/null 2>&1; then
  fail "forced-command wrapper accepted an arbitrary SSH command"
fi
[[ ! -s "$TEST_SUDO_LOG" ]] || fail "rejected SSH command reached sudo"
SSH_ORIGINAL_COMMAND='vault-cert-sync-v1' "$wrapper"
grep -Fx -- "-n ${test_root}/receiver-target vault-cert-sync-v1" "$TEST_SUDO_LOG" >/dev/null || fail "forced-command wrapper did not pass the fixed sudo invocation"

# The deploy hook has a literal lineage gate. An unrelated renewal, including
# a pathname-looking value, cannot invoke the sender helper.
hook="$test_root/certbot-renew-hook"
hook_helper_log="$test_root/hook-helper.log"
cat > "$test_root/hook-helper" <<'EOF'
#!/bin/bash
printf '%s\n' invoked >> "$TEST_HOOK_HELPER_LOG"
EOF
chmod 0700 "$test_root/hook-helper"
sed \
  -e '/{% if certbot_vault_cert_sync_enabled/d' \
  -e '/{% endif %}/d' \
  -e "s#{{ certbot_vault_cert_sync_lineage }}#bevz-net-wildcard#g" \
  -e "s#{{ certbot_vault_cert_sync_helper_path }}#${test_root}/hook-helper#g" \
  "$repo_root/config/roles/certbot_setup/templates/certbot-renew-hook.sh.j2" > "$hook"
chmod 0700 "$hook"
export TEST_HOOK_HELPER_LOG="$hook_helper_log"
RENEWED_LINEAGE='/etc/letsencrypt/live/bevz-net-wildcard/../../other' "$hook"
[[ ! -e "$hook_helper_log" ]] || fail "noncanonical renewal lineage invoked sender"
RENEWED_LINEAGE='/etc/letsencrypt/live/bevz-net-wildcard' "$hook"
grep -qx invoked "$hook_helper_log" || fail "canonical renewal lineage did not invoke sender"

# The receiver accepts only its fixed command and never accepts source paths.
before="$(sha256sum "$tls_cert" "$tls_key")"
if run_receiver '../../etc/passwd' </dev/null >/dev/null 2>&1; then
  fail "arbitrary receiver command unexpectedly succeeded"
fi
assert_unchanged "$before"

# Reject malformed, extra, wrong-host, expired, and mismatched-key input with
# no file mutation. The fixed protocol has no pathname field to traverse.
before="$(sha256sum "$tls_cert" "$tls_key")"
if printf 'vault-cert-sync-v1\n%%%%%%\n%%%%%%\n' | run_receiver vault-cert-sync-v1 >/dev/null 2>&1; then
  fail "malformed base64 unexpectedly succeeded"
fi
assert_unchanged "$before"

before="$(sha256sum "$tls_cert" "$tls_key")"
if { payload "$test_root/new.fullchain.pem" "$test_root/new.key"; printf 'extra\n'; } | run_receiver vault-cert-sync-v1 >/dev/null 2>&1; then
  fail "extra protocol line unexpectedly succeeded"
fi
assert_unchanged "$before"

before="$(sha256sum "$tls_cert" "$tls_key")"
if payload "$test_root/wrong-host.fullchain.pem" "$test_root/wrong-host.key" | run_receiver vault-cert-sync-v1 >/dev/null 2>&1; then
  fail "wrong hostname unexpectedly succeeded"
fi
assert_unchanged "$before"

before="$(sha256sum "$tls_cert" "$tls_key")"
if payload "$test_root/expired.fullchain.pem" "$test_root/expired.key" | run_receiver vault-cert-sync-v1 >/dev/null 2>&1; then
  fail "expired certificate unexpectedly succeeded"
fi
assert_unchanged "$before"

before="$(sha256sum "$tls_cert" "$tls_key")"
if payload "$test_root/new.fullchain.pem" "$test_root/wrong-key.key" | run_receiver vault-cert-sync-v1 >/dev/null 2>&1; then
  fail "mismatched certificate/key unexpectedly succeeded"
fi
assert_unchanged "$before"

# A valid pair is installed only after the main Vault PID receives HUP; no
# restart command is used. The fake listener follows the current file on HUP.
payload "$test_root/new.fullchain.pem" "$test_root/new.key" | run_receiver vault-cert-sync-v1
cmp -s "$test_root/new.fullchain.pem" "$tls_cert" || fail "valid certificate was not installed"
cmp -s "$test_root/new.key" "$tls_key" || fail "valid private key was not installed"
grep -qx 'kill --kill-who=main --signal=HUP vault' "$TEST_SYSTEMCTL_LOG" || fail "receiver did not HUP Vault main PID"
if grep -Eq '(restart|reload)' "$TEST_SYSTEMCTL_LOG"; then
  fail "receiver restarted or reloaded Vault through systemctl"
fi

# A failed post-HUP fingerprint check restores the prior pair and HUPs it.
cp "$test_root/old.fullchain.pem" "$tls_cert"
cp "$test_root/old.key" "$tls_key"
cp "$tls_cert" "$TEST_ACTIVE_CERT"
: > "$TEST_SYSTEMCTL_LOG"
rm -f "$TEST_HUP_FAILED_ONCE"
export TEST_FAIL_FIRST_HUP=1
before="$(sha256sum "$tls_cert" "$tls_key")"
if payload "$test_root/new.fullchain.pem" "$test_root/new.key" | run_receiver vault-cert-sync-v1 >/dev/null 2>&1; then
  fail "failed reload verification unexpectedly succeeded"
fi
assert_unchanged "$before"
[[ "$(grep -c '^kill --kill-who=main --signal=HUP vault$' "$TEST_SYSTEMCTL_LOG")" -eq 2 ]] || fail "rollback did not HUP the restored Vault pair"

printf '%s\n' "vault certificate sync receiver tests passed"
