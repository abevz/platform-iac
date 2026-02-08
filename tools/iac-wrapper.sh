#!/bin/bash
#
# iac-wrapper.sh - Orchestrator v4.0 for 'platform-iac'
# FIXED: REMOVED dependency on complex 'jq' parsing for inventory.
# NEW: Implemented 'tofu output' caching mechanism and usage of 'tofu_inventory.py'.
#
# DEPENDENCIES: tofu, ansible-playbook, sops, yq, jq, nc (netcat), python3
#

# --- 1. Configuration and strict mode ---
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/..

# --- Load platform configuration ---
PLATFORM_CONF="${REPO_ROOT}/config/platform.conf"
if [ -f "$PLATFORM_CONF" ]; then
  # shellcheck source=/dev/null
  source "$PLATFORM_CONF"
else
  echo "WARN: ${PLATFORM_CONF} not found. Using defaults or environment variables." >&2
  echo "      Copy config/platform.conf.example to config/platform.conf and customize." >&2
fi

# --- Configuration with defaults (can be overridden by platform.conf or env) ---
STATIC_INVENTORY="${REPO_ROOT}/config/inventory/static.ini"
ANSIBLE_CONFIG_FILE="${REPO_ROOT}/config/ansible.cfg"
SSH_KEY="${SSH_KEY:-${REPO_ROOT}/keys/deployment_key}"
readonly TF_STATE_BUCKET="${TF_STATE_BUCKET:-terraform-state}"

# --- NEW CONSTANTS FOR INVENTORY (Integration) ---
readonly TOFU_CACHE_DIR="${REPO_ROOT}/.cache"
readonly INVENTORY_SCRIPT="${REPO_ROOT}/tools/tofu_inventory.py"
# ---------------------------------------------------

export TF_PLUGIN_CACHE_DIR="$HOME/.cpc/plugin-cache"
#export TF_LOG=TRACE

# Paths to 3 SOPS files
readonly PROXMOX_SECRETS_FILE="${REPO_ROOT}/config/secrets/proxmox/provider.sops.yml"
readonly MINIO_SECRETS_FILE="${REPO_ROOT}/config/secrets/minio/backend.sops.yml"
readonly ANSIBLE_SECRETS_FILE="${REPO_ROOT}/config/secrets/ansible/extra_vars.sops.yml"

# --- Global variables ---
ANSIBLE_VARS_ARG=""
TOFU_VARS_ARG=""

# --- Cleanup ---
# Remove old temporary JSON/TFVARS files on exit.
trap 'rm -f /tmp/iac_vars_*.json /tmp/iac_tfvars_*.json' EXIT

# --- 2. Helper functions ---

log() {
  echo "--- [$(date +'%T')] [${COMPONENT:-Global}] :: $*" >&2
}

check_deps() {
  log "Checking dependencies..."
  local missing=0
  for cmd in tofu ansible-playbook sops yq jq nc python3; do
    if ! command -v "$cmd" &>/dev/null; then
      log "Error: Required dependency '$cmd' not found in PATH."
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then exit 1; fi
  return 0
}

# Load Ansible secrets (for Ansible)
load_ansible_secrets_to_temp_file() {
  if [ ! -f "$ANSIBLE_SECRETS_FILE" ]; then
    log "Ansible secrets file ($ANSIBLE_SECRETS_FILE) not found. Skipping."
    ANSIBLE_VARS_ARG=""
    return
  fi
  log "Decrypting Ansible secrets (for --extra-vars)..."
  local TEMP_VARS_FILE=$(mktemp /tmp/iac_vars_XXXXXX.json)
  if ! sops -d "$ANSIBLE_SECRETS_FILE" | yq -o json >"$TEMP_VARS_FILE"; then
    log "Error: Failed to decrypt $ANSIBLE_SECRETS_FILE"
    exit 1
  fi
  ANSIBLE_VARS_ARG="--extra-vars @${TEMP_VARS_FILE}"
}

# (v3.6) Load Tofu secrets
load_tofu_secrets_to_temp_file() {
  log "Decrypting Tofu secrets (for -var-file)..."

  local COMPONENT="$1"

  # --- START: CHICKEN AND EGG FIX (API, SSH Addr, SSH Port) ---
  # Values loaded from config/platform.conf (with fallback defaults)
  local _PROXMOX_DIRECT_IP="${PROXMOX_DIRECT_IP:-<PROXMOX-HOST-IP>}"
  local _PROXMOX_DIRECT_API_URL="${PROXMOX_DIRECT_API_URL:-https://${_PROXMOX_DIRECT_IP}:8006}"
  local _PROXMOX_DIRECT_SSH_PORT="${PROXMOX_DIRECT_SSH_PORT:-22}"

  local PROXMOX_PROXY_API_URL
  PROXMOX_PROXY_API_URL=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.PROXMOX_VE_ENDPOINT')
  local _PROXMOX_PROXY_API_URL="${PROXMOX_PROXY_API_URL}"
  local _PROXMOX_PROXY_SSH_ADDR="${PROXMOX_PROXY_SSH_ADDR:-homelab.example.com}"
  local _PROXMOX_PROXY_SSH_PORT="${PROXMOX_PROXY_SSH_PORT:-22006}"

  local proxmox_api_url
  local proxmox_ssh_address
  local proxmox_ssh_port

  local PUBLIC_KEY_CONTENT=""

  # 1. Main key (from Ansible)
  if [ -f "${SSH_KEY}.pub" ]; then
    PUBLIC_KEY_CONTENT+=$(cat "${SSH_KEY}.pub")
    PUBLIC_KEY_CONTENT+=$'\n' # Add newline
  else
    log "WARN: Public key ${SSH_KEY}.pub not found!"
  fi

  # 2. Extra keys (e.g., your personal id_rsa.pub)
  # You can specify specific files:
  local EXTRA_KEYS=(
    "$HOME/.ssh/id_rsa.pub"
    "$HOME/.ssh/another_key.pub"
  )

  for key_file in "${EXTRA_KEYS[@]}"; do
    if [ -f "$key_file" ]; then
      PUBLIC_KEY_CONTENT+=$(cat "$key_file")
      PUBLIC_KEY_CONTENT+=$'\n'
    fi
  done

  # If no keys at all - set placeholder
  if [ -z "$PUBLIC_KEY_CONTENT" ]; then
    PUBLIC_KEY_CONTENT="ssh-rsa AAAA-PLACEHOLDER"
  fi

  # Remove last extra newline (optional but clean)
  PUBLIC_KEY_CONTENT="${PUBLIC_KEY_CONTENT%$'\n'}"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "WARNING: Bootstrap component detected. Using DIRECT IP ($_PROXMOX_DIRECT_IP) and DIRECT port ($_PROXMOX_DIRECT_SSH_PORT)."
    proxmox_api_url="$_PROXMOX_DIRECT_API_URL"
    proxmox_ssh_address="$_PROXMOX_DIRECT_IP"
    proxmox_ssh_port=$_PROXMOX_DIRECT_SSH_PORT
  else
    log "INFO: Service component. Using PROXY FQDN ($_PROXMOX_PROXY_SSH_ADDR) and PROXY port ($_PROXMOX_PROXY_SSH_PORT)."
    proxmox_api_url="$_PROXMOX_PROXY_API_URL"
    proxmox_ssh_address="$_PROXMOX_PROXY_SSH_ADDR"
    proxmox_ssh_port=$_PROXMOX_PROXY_SSH_PORT
  fi
  # --- END: CHICKEN AND EGG FIX ---

  local PROXMOX_JSON
  # 3. Pass ALL variables to jq
  PROXMOX_JSON=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -o json | jq -r \
    --arg api_url "$proxmox_api_url" \
    --arg ssh_addr "$proxmox_ssh_address" \
    --arg ssh_port "$proxmox_ssh_port" \
    --arg pub_key "$PUBLIC_KEY_CONTENT" '
      {
        "proxmox_api_url": $api_url,
        "proxmox_api_username": .PROXMOX_VE_API_TOKEN_ID,
        "proxmox_api_password": .PROXMOX_VE_API_TOKEN_SECRET,
        "proxmox_ssh_user": .PROXMOX_VE_SSH_USERNAME,
        "proxmox_ssh_private_key": .PROXMOX_VE_SSH_PRIVATE_KEY,
        "proxmox_ssh_address": $ssh_addr,
        "proxmox_ssh_port": ($ssh_port | tonumber),
        "ssh_public_key": $pub_key
      }
    ')

  log "Disabling SSL verification (Forced)..."
  export PROXMOX_VE_INSECURE_SKIP_TLS_VERIFY=true

  log "Loading backend secrets (MinIO)..."
  export AWS_ACCESS_KEY_ID=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_USER')
  export AWS_SECRET_ACCESS_KEY=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_PASSWORD')
  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    log "Error: Failed to decrypt MinIO secrets."
    exit 1
  fi

  # Load MinIO endpoint for backend configuration (use env var if set, otherwise read from sops)
  if [ -z "$MINIO_ENDPOINT" ]; then
    export MINIO_ENDPOINT=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ENDPOINT // "https://s3.minio.example.com"')
  fi
  if [ -z "$MINIO_ENDPOINT" ] || [ "$MINIO_ENDPOINT" = "null" ]; then
    log "WARN: MINIO_ENDPOINT not found in secrets. Using default."
    export MINIO_ENDPOINT="https://s3.minio.example.com"
  fi
  log "Using MinIO endpoint: $MINIO_ENDPOINT"

  TEMP_TFVARS_FILE=$(mktemp /tmp/iac_tfvars_XXXXXX.json)
  echo "$PROXMOX_JSON" >"$TEMP_TFVARS_FILE"

  TOFU_VARS_ARG="-var-file=${TEMP_TFVARS_FILE}"
}

# --- NEW FUNCTION (Caching) ---
tofu_cache_outputs() {
  local TERRAFORM_DIR="$1"
  log "⚙️ Caching OpenTofu outputs to ${TOFU_CACHE_DIR}/tofu-outputs.json..."

  cd "$TERRAFORM_DIR"

  if [ ! -f .terraform/terraform.tfstate ]; then
    log "WARN: State not found locally. Executing 'tofu init'."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="endpoint=${MINIO_ENDPOINT}" >/dev/null
  fi

  mkdir -p "$TOFU_CACHE_DIR"

  # Output all outputs to JSON cache file. $TOFU_VARS_ARG is needed for state access.
  if ! tofu output -json $TOFU_VARS_ARG >"${TOFU_CACHE_DIR}/tofu-outputs.json"; then
    log "🚨 Caching error. Check 'tofu apply' state and 'ansible_inventory_data' output."
    return 1
  fi
  log "✅ Inventory cache successfully created."
  return 0
}
# ------------------------------------

# --- REMOVED OLD FUNCTIONS: get_inventory_from_tf_state AND get_inventory_json ---
# Replaced by INVENTORY_SCRIPT call.

# --- 3. Entry Point and Action Parsing ---

print_usage() {
  echo "Usage: $0 <action> [options]"
  echo "Actions: deploy, apply, configure, run-playbook, run-static, plan, destroy, start, stop, get-inventory, print-envs"
}

# ---
# MAIN CASE BLOCK
# ---

if [ "$#" -lt 1 ]; then
  print_usage
  exit 1
fi

ACTION="$1"
shift

check_deps

case "$ACTION" in
deploy)
  if [ "$#" -ne 2 ]; then
    log "Error: 'deploy' requires <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Starting Tofu Deploy (Infrastructure Only) for '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure \
    -backend-config="bucket=${TF_STATE_BUCKET}" \
    -backend-config="key=${TF_STATE_KEY}" \
    -backend-config="endpoint=${MINIO_ENDPOINT}"

  tofu apply -auto-approve "$TOFU_VARS_ARG"

  # --- INTEGRATION: Refresh and Cache ---
  log "Executing 'tofu refresh' to update IP addresses (DHCP)..."
  tofu refresh "$TOFU_VARS_ARG"

  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Cannot continue: Failed to create inventory cache."
    exit 1
  fi
  # ------------------------------------

  # DNS and Ansible blocks REMOVED for this command

  log "✅ Infrastructure (deploy) successfully created. DNS and Ansible were NOT run."
  ;;

apply)
  if [ "$#" -ne 2 ]; then
    log "Error: 'apply' requires <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"
  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"

  log "Starting Tofu Apply for '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "WARNING: Bootstrap component detected. Forcing cleanup of .terraform/ for local state..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "WARNING: Starting 'tofu init' with LOCAL state (bootstrap)."
    tofu init
  else
    log "Starting 'tofu init' with S3 backend..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="endpoint=${MINIO_ENDPOINT}"
  fi

  tofu apply -auto-approve "$TOFU_VARS_ARG"

  # --- INTEGRATION: Refresh and Cache ---
  log "Executing 'tofu refresh' to update IP addresses (DHCP)..."
  tofu refresh "$TOFU_VARS_ARG"

  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Cannot continue: Failed to create inventory cache."
    exit 1
  fi
  # ------------------------------------

  # --- NEW BLOCK: DNS REGISTRATION ---
  log "Starting DNS registration in Pi-hole..."
  PYTHON_DNS_SCRIPT="${REPO_ROOT}/tools/add_pihole_dns.py"

  if [ ! -f "$PYTHON_DNS_SCRIPT" ]; then
    log "🚨 Error: add_pihole_dns.py script not found at $PYTHON_DNS_SCRIPT"
    exit 1
  fi

  # Call Python script, passing Tofu dir and Ansible secrets file
  # (as it contains pihole.web_password)
  if ! python3 "$PYTHON_DNS_SCRIPT" --action "add" --tf-dir "$TERRAFORM_DIR" --secrets-file "$ANSIBLE_SECRETS_FILE"; then
    log "🚨 Error: Failed to register DNS records in Pi-hole."
    exit 1
  fi
  log "✅ DNS records successfully registered in Pi-hole."
  # --- END NEW BLOCK ---

  cd "$REPO_ROOT"

  log "Starting Ansible (Main Playbook) for '$COMPONENT'..."

  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Warning: Main playbook not found: ${ANSIBLE_PLAYBOOK}. Skipping configuration."
  else
    # --- Check SSH availability ---
    log "Setting execution rights on inventory script..."
    chmod +x "${INVENTORY_SCRIPT}"

    log "Getting first IP from dynamic inventory..."
    INVENTORY_JSON=$("${INVENTORY_SCRIPT}" --list)

    FIRST_IP=$(echo "$INVENTORY_JSON" | jq -r '
        ._meta.hostvars | to_entries[0].value.ansible_host // empty
    ')

    if [ -z "$FIRST_IP" ] || [ "$FIRST_IP" == "unknown" ]; then
      log "Error: Failed to get first host IP ($FIRST_IP) via dynamic inventory. Cannot check SSH."
      exit 1
    fi

    log "Waiting for SSH availability (${FIRST_IP}:22)..."
    while ! nc -z -w5 "$FIRST_IP" 22; do
      log "Waiting 5 seconds ($FIRST_IP:22)..."
      sleep 5
    done
    # -------------------------------------------------------------

    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
    load_ansible_secrets_to_temp_file

    # FINAL FIX: Using eval to safely pass optional flags.
    # This bypasses all order and escaping issues.

    # Build command arguments
    ANSIBLE_CMD="ansible-playbook -i $INVENTORY_SCRIPT --private-key $SSH_KEY"

    # Add variables only if they exist
    if [ -n "$ANSIBLE_VARS_ARG" ]; then
      ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
    fi

    # Add playbook at the end
    ANSIBLE_CMD+=" $ANSIBLE_PLAYBOOK"

    log "Executing command: $ANSIBLE_CMD"

    # Execute command
    eval $ANSIBLE_CMD

  fi
  ;;

configure)
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    log "Error: 'configure' requires <env> <component> [limit_target]"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"
  LIMIT_TARGET="${3:-all}"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate" # Used in tofu_cache_outputs

  # --- NEW: Create cache before running Ansible ---
  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Cannot continue: Failed to create inventory cache."
    exit 1
  fi
  # --------------------------------------------------

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Error: Main playbook not found: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Starting Ansible (Main Playbook) for '$COMPONENT' with limit '$LIMIT_TARGET'..."

  log "Setting execution rights on inventory script..."
  chmod +x "${INVENTORY_SCRIPT}"

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file

  # FINAL FIX: Using eval for safe optional flag passing
  ANSIBLE_CMD="ansible-playbook -i $INVENTORY_SCRIPT --private-key $SSH_KEY --limit $LIMIT_TARGET $ANSIBLE_PLAYBOOK"

  if [ -n "$ANSIBLE_VARS_ARG" ]; then
    ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
  fi

  log "Executing command: $ANSIBLE_CMD"
  eval $ANSIBLE_CMD

  ;;

run-playbook)
  if [ "$#" -lt 4 ]; then
    log "Error: 'run-playbook' requires <env> <component> <playbook.yml> <limit_target>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"
  PLAYBOOK_NAME="$3"
  LIMIT_TARGET="$4"

  shift 4
  EXTRA_ANSIBLE_ARGS="$@"
  ANSIBLE_VARS_ARG=""

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Cannot continue: Failed to create inventory cache."
    exit 1
  fi

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/${PLAYBOOK_NAME}"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Error: Playbook not found: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Starting Ansible (Ad-Hoc) '$PLAYBOOK_NAME' for '$COMPONENT' with limit '$LIMIT_TARGET'..."

  log "Setting execution rights on inventory script..."
  chmod +x "${INVENTORY_SCRIPT}"

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file

  # --- START FIX (Double escaping for 'eval') ---

  # We must escape quotes (\\") so 'eval' receives
  # "ansible-playbook -i \"/path1,/path2\" ...",
  # not "ansible-playbook -i /path1,/path2 ..."

  ANSIBLE_CMD="ansible-playbook -i $INVENTORY_SCRIPT -i $STATIC_INVENTORY --private-key $SSH_KEY --limit $LIMIT_TARGET $ANSIBLE_PLAYBOOK"

  if [ -n "$ANSIBLE_VARS_ARG" ]; then
    ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
  fi

  if [ -n "$EXTRA_ANSIBLE_ARGS" ]; then
    ANSIBLE_CMD+=" $EXTRA_ANSIBLE_ARGS"
  fi
  # --- END FIX ---

  log "Executing command: $ANSIBLE_CMD"
  eval $ANSIBLE_CMD
  ;;

run-static)
  # No changes needed as it uses static INI
  if [ "$#" -ne 2 ]; then
    log "Error: 'run-static' requires <playbook.yml> <limit_target>"
    print_usage
    exit 1
  fi
  PLAYBOOK_NAME="$1"
  LIMIT_TARGET="$2"

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/${PLAYBOOK_NAME}"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Error: Playbook not found: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi
  if [ ! -f "$STATIC_INVENTORY" ]; then
    log "Error: Static inventory not found: ${STATIC_INVENTORY}"
    exit 1
  fi

  log "Starting Ansible (Static) '$PLAYBOOK_NAME' with limit '$LIMIT_TARGET'..."

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file

  # 1. Build base command
  ANSIBLE_CMD="ansible-playbook -i $STATIC_INVENTORY --private-key $SSH_KEY --limit $LIMIT_TARGET"

  # 2. Add variables if they exist (without quotes so eval parses them correctly)
  if [ -n "$ANSIBLE_VARS_ARG" ]; then
    ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
  fi

  # 3. Add playbook
  ANSIBLE_CMD+=" $ANSIBLE_PLAYBOOK"

  log "Executing command: $ANSIBLE_CMD"

  # 4. Execute via eval
  eval $ANSIBLE_CMD

  ;;

plan | destroy)
  # No changes needed as Ansible is not called
  if [ "$#" -ne 2 ]; then
    log "Error: '$ACTION' requires <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Starting Tofu '$ACTION' for '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "WARNING: Bootstrap component detected. Forcing cleanup of .terraform/ for local state..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "WARNING: Starting 'tofu init' with LOCAL state (bootstrap)."
    tofu init
  else
    log "Starting 'tofu init' with S3 backend..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="endpoint=${MINIO_ENDPOINT}"
  fi

  if [ "$ACTION" == "plan" ]; then
    tofu plan "$TOFU_VARS_ARG"
  else
    # --- DESTROY ---

    # 1. FIRST DELETE DNS WHILE STATE STILL EXISTS
    log "Starting DNS record deletion from Pi-hole (before destroy)..."
    PYTHON_DNS_SCRIPT="${REPO_ROOT}/tools/add_pihole_dns.py"

    if [ ! -f "$PYTHON_DNS_SCRIPT" ]; then
      log "🚨 Error: add_pihole_dns.py script not found at $PYTHON_DNS_SCRIPT"
      exit 1
    fi
    if [ ! -f "$ANSIBLE_SECRETS_FILE" ]; then
      log "🚨 Error: Ansible secrets file ($ANSIBLE_SECRETS_FILE) not found. Cannot retrieve Pi-hole password."
      exit 1
    fi

    # Call Python script with 'unregister-dns' action
    # It reads Tofu state (via tofu output) to find hosts to delete
    if ! python3 "$PYTHON_DNS_SCRIPT" --action "unregister-dns" --tf-dir "$TERRAFORM_DIR" --secrets-file "$ANSIBLE_SECRETS_FILE"; then
      log "⚠️  Warning: Failed to remove DNS records from Pi-hole. (Continuing with destroy...)"
      # We do NOT exit (exit 1) so destroy runs anyway
    else
      log "✅ DNS records successfully removed from Pi-hole."
    fi

    # 2. NOW DESTROY VM
    log "Destroying infrastructure (tofu destroy)..."
    tofu destroy -auto-approve "$TOFU_VARS_ARG"
  fi
  ;;

start)
  if [ "$#" -ne 2 ]; then
    log "Error: 'start' requires <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Starting Tofu Apply (var.vm_started=true) for '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "WARNING: Bootstrap component detected. Forcing cleanup of .terraform/ for local state..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "WARNING: Starting 'tofu init' with LOCAL state (bootstrap)."
    tofu init
  else
    log "Starting 'tofu init' with S3 backend..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="endpoint=${MINIO_ENDPOINT}"
  fi

  tofu apply -var="vm_started=true" -auto-approve "$TOFU_VARS_ARG"
  ;;

stop)
  if [ "$#" -ne 2 ]; then
    log "Error: 'stop' requires <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Starting Tofu Apply (var.vm_started=false) for '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "WARNING: Bootstrap component detected. Forcing cleanup of .terraform/ for local state..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "WARNING: Starting 'tofu init' with LOCAL state (bootstrap)."
    tofu init
  else
    log "Starting 'tofu init' with S3 backend..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" -backend-config="endpoint=${MINIO_ENDPOINT}"
  fi

  tofu apply -var="vm_started=false" -auto-approve "$TOFU_VARS_ARG"
  ;;

get-inventory)
  if [ "$#" -ne 2 ]; then
    log "Error: 'get-inventory' requires <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  # --- NEW: Refresh cache and output JSON via script ---
  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Failed to update cache. Outputting empty JSON."
    echo "{}"
    exit 1
  fi

  log "Setting execution rights on inventory script..."
  chmod +x "${INVENTORY_SCRIPT}"

  # Output inventory JSON to stdout
  "${INVENTORY_SCRIPT}" --list
  # --------------------------------------------------------
  ;;

print-envs)
  if [ "$#" -ne 2 ]; then
    log "Error: 'print-envs' requires <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  # Load all secrets and arguments
  load_tofu_secrets_to_temp_file "$COMPONENT"
  load_ansible_secrets_to_temp_file

  log "--- Tofu Arguments and Environment ---"
  echo "PROXMOX_VE_INSECURE_SKIP_TLS_VERIFY=true"
  echo "AWS_ACCESS_KEY_ID=..."
  echo "AWS_SECRET_ACCESS_KEY=..."
  echo "TF_VAR_FILE=${TEMP_TFVARS_FILE}"
  echo "TOFU_VARS_ARG=\"$TOFU_VARS_ARG\""

  log "--- Ansible Arguments ---"
  echo "INVENTORY_SCRIPT=$INVENTORY_SCRIPT"
  echo "ANSIBLE_VARS_ARG=\"$ANSIBLE_VARS_ARG\""
  echo "SSH_KEY=$SSH_KEY"

  # Run caching to ensure inventory is fresh
  tofu_cache_outputs "$TERRAFORM_DIR"
  ;;

*)
  log "Error: Unknown action '$ACTION'"
  print_usage
  exit 1
  ;;
esac

log "Execution of '$ACTION' completed."
