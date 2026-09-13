#!/usr/bin/env bash
# Safely apply config/playbooks/harden_proxmox_ssh.yml to one Proxmox node.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <ssh-target> <ansible-inventory>" >&2
  exit 64
fi

readonly target="$1"
readonly inventory="$2"
readonly rollback_seconds=180
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
readonly timestamp
readonly backup_dir="/root/piac-8-proxmox-ssh-hardening-${timestamp}"
readonly rollback_unit="piac-8-sshd-rollback-${timestamp}"
readonly ssh_options=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o ControlMaster=no
  -o ControlPath=none
)

if [ ! -f "$inventory" ]; then
  echo "Inventory does not exist: $inventory" >&2
  exit 66
fi

ssh "${ssh_options[@]}" "$target" 'sudo -n true'

# shellcheck disable=SC2029 # Arguments deliberately expand locally before SSH.
ssh "${ssh_options[@]}" "$target" \
  "sudo sh -s -- '$backup_dir' '$rollback_unit' '$rollback_seconds'" <<'REMOTE_SETUP'
set -eu

backup_dir="$1"
rollback_unit="$2"
rollback_seconds="$3"
config_dir='/etc/ssh/sshd_config.d'
primary_config='/etc/ssh/sshd_config'
managed_drop_in='/etc/ssh/sshd_config.d/99-platform-iac.conf'

umask 077
mkdir -p "$backup_dir"

backup_path() {
  source_path="$1"
  backup_name="$2"

  if [ -e "$source_path" ]; then
    cp -a -- "$source_path" "$backup_dir/$backup_name"
    printf 'present\n' >"$backup_dir/$backup_name.state"
  else
    printf 'absent\n' >"$backup_dir/$backup_name.state"
  fi
}

backup_path "$primary_config" 'sshd_config'
backup_path "$config_dir" 'sshd_config.d'
backup_path "$managed_drop_in" '99-platform-iac.conf'

cat >"$backup_dir/rollback.sh" <<ROLLBACK
#!/bin/sh
set -eu
backup_dir='$backup_dir'
restore_path() {
  target_path="\$1"
  backup_name="\$2"

  if [ "\$(cat "\$backup_dir/\$backup_name.state")" = present ]; then
    rm -rf -- "\$target_path"
    cp -a -- "\$backup_dir/\$backup_name" "\$target_path"
  else
    rm -rf -- "\$target_path"
  fi
}

restore_path '/etc/ssh/sshd_config' 'sshd_config'
restore_path '/etc/ssh/sshd_config.d' 'sshd_config.d'
/usr/sbin/sshd -t
systemctl reload ssh
ROLLBACK
chmod 700 "$backup_dir/rollback.sh"

systemd-run --unit="$rollback_unit" --on-active="${rollback_seconds}s" \
  "$backup_dir/rollback.sh"
REMOTE_SETUP

echo "Rollback armed for ${rollback_seconds}s: ${rollback_unit}.timer"

if ! ANSIBLE_CONFIG=config/ansible.cfg ANSIBLE_ROLES_PATH=config/roles \
  ansible-playbook -i "$inventory" config/playbooks/harden_proxmox_ssh.yml; then
  echo "Apply failed; automatic rollback remains armed." >&2
  exit 1
fi

if ! ssh "${ssh_options[@]}" "$target" \
  "sudo /usr/sbin/sshd -t && sudo /usr/sbin/sshd -T | grep -Fx 'passwordauthentication no' >/dev/null && sudo /usr/sbin/sshd -T | grep -Fx 'allowgroups sudo' >/dev/null && sudo /usr/sbin/sshd -T | grep -Fx 'allowgroups terraform' >/dev/null"; then
  echo "Fresh key-only SSH verification failed; automatic rollback remains armed." >&2
  exit 1
fi

# shellcheck disable=SC2029 # Unit name deliberately expands locally before SSH.
ssh "${ssh_options[@]}" "$target" \
  "sudo systemctl stop '${rollback_unit}.timer'"

echo "SSH hardening applied. Root-only backup retained at ${backup_dir}."
