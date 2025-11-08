#!/bin/bash
#
# iac-wrapper.sh - Оркестратор v4.0 для 'platform-iac'
# ИСПРАВЛЕНО: УДАЛЕНА зависимость от сложного парсинга 'jq' для инвентаря.
# НОВОЕ: Внедрен механизм кэширования 'tofu output' и использование 'tofu_inventory.py'.
#
# ЗАВИСИМОСТИ: tofu, ansible-playbook, sops, yq, jq, nc (netcat), python3
#

# --- 1. Конфигурация и строгий режим ---
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/..
STATIC_INVENTORY="${REPO_ROOT}/config/inventory/static.ini"
ANSIBLE_CONFIG_FILE="${REPO_ROOT}/config/ansible.cfg"
SSH_KEY="/home/abevz/Projects/platform-iac/cpc_deployment_key"
readonly TF_STATE_BUCKET="terraform-state-bevz-net"

# --- НОВЫЕ КОНСТАНТЫ ДЛЯ ИНВЕНТАРЯ (Интеграция) ---
readonly TOFU_CACHE_DIR="${REPO_ROOT}/.cache"
readonly INVENTORY_SCRIPT="${REPO_ROOT}/tools/tofu_inventory.py"
# ---------------------------------------------------

export TF_PLUGIN_CACHE_DIR="$HOME/.cpc/plugin-cache"
# export TF_LOG=TRACE

# Пути к 3-м файлам SOPS
readonly PROXMOX_SECRETS_FILE="${REPO_ROOT}/config/secrets/proxmox/provider.sops.yml"
readonly MINIO_SECRETS_FILE="${REPO_ROOT}/config/secrets/minio/backend.sops.yml"
readonly ANSIBLE_SECRETS_FILE="${REPO_ROOT}/config/secrets/ansible/extra_vars.sops.yml"

# --- Глобальные переменные ---
ANSIBLE_VARS_ARG=""
TOFU_VARS_ARG=""

# --- Очистка ---
# Удаляем очистку старых временных INI файлов. Оставляем только очистку temp JSON/TFVARS.
trap 'rm -f /tmp/iac_vars_*.json /tmp/iac_tfvars_*.json' EXIT

# --- 2. Вспомогательные функции ---

log() {
  echo "--- [$(date +'%T')] [${COMPONENT:-Global}] :: $*" >&2
}

check_deps() {
  log "Проверка зависимостей..."
  local missing=0
  for cmd in tofu ansible-playbook sops yq jq nc python3; do # Добавляем python3
    if ! command -v "$cmd" &>/dev/null; then
      log "Ошибка: Необходимая зависимость '$cmd' не найдена в PATH."
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then exit 1; fi
  return 0
}

# Загрузка секретов Ansible (для Ansible)
load_ansible_secrets_to_temp_file() {
  if [ ! -f "$ANSIBLE_SECRETS_FILE" ]; then
    log "Файл секретов Ansible ($ANSIBLE_SECRETS_FILE) не найден. Пропускаем."
    ANSIBLE_VARS_ARG=""
    return
  fi
  log "Расшифровка секретов Ansible (для --extra-vars)..."
  local TEMP_VARS_FILE=$(mktemp /tmp/iac_vars_XXXXXX.json)
  if ! sops -d "$ANSIBLE_SECRETS_FILE" | yq -o json >"$TEMP_VARS_FILE"; then
    log "Ошибка: Не удалось расшифровать $ANSIBLE_SECRETS_FILE"
    exit 1
  fi
  ANSIBLE_VARS_ARG="--extra-vars @${TEMP_VARS_FILE}"
}

# (v3.6) Загрузка секретов Tofu
load_tofu_secrets_to_temp_file() {
  log "Расшифровка секретов Tofu (для -var-file)..."

  local PROXMOX_JSON
  PROXMOX_JSON=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -o json | jq -r '
      {
        "proxmox_api_url": .PROXMOX_VE_ENDPOINT,
        "proxmox_api_username": .PROXMOX_VE_API_TOKEN_ID,
        "proxmox_api_password": .PROXMOX_VE_API_TOKEN_SECRET,
        "proxmox_ssh_user": .PROXMOX_VE_SSH_USERNAME,
        "proxmox_ssh_private_key": .PROXMOX_VE_SSH_PRIVATE_KEY
      }
    ')

  log "Отключение SSL-проверки (Принудительно)..."
  export PROXMOX_VE_INSECURE_SKIP_TLS_VERIFY=true

  log "Загрузка секретов бэкенда (MinIO)..."
  export AWS_ACCESS_KEY_ID=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_USER')
  export AWS_SECRET_ACCESS_KEY=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_PASSWORD')
  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    log "Ошибка: Не удалось расшифровать секреты MinIO."
    exit 1
  fi

  local TEMP_TFVARS_FILE=$(mktemp /tmp/iac_tfvars_XXXXXX.json)
  echo "$PROXMOX_JSON" >"$TEMP_TFVARS_FILE"

  TOFU_VARS_ARG="-var-file=${TEMP_TFVARS_FILE}"
}

# --- НОВАЯ ФУНКЦИЯ (Кэширование) ---
tofu_cache_outputs() {
  local TERRAFORM_DIR="$1"
  log "⚙️ Кэширование OpenTofu outputs в ${TOFU_CACHE_DIR}/tofu-outputs.json..."

  cd "$TERRAFORM_DIR"

  if [ ! -f .terraform/terraform.tfstate ]; then
    log "WARN: Состояние не найдено локально. Выполняем 'tofu init'."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" >/dev/null
  fi

  mkdir -p "$TOFU_CACHE_DIR"

  # Вывод всех outputs в JSON-файл кэша. $TOFU_VARS_ARG необходим для доступа к состоянию.
  if ! tofu output -json $TOFU_VARS_ARG >"${TOFU_CACHE_DIR}/tofu-outputs.json"; then
    log "🚨 Ошибка кэширования output. Проверьте состояние 'tofu apply' и output 'ansible_inventory_data'."
    return 1
  fi
  log "✅ Кэш инвентаря успешно создан."
  return 0
}
# ------------------------------------

# --- УДАЛЕНЫ СТАРЫЕ ФУНКЦИИ: get_inventory_from_tf_state И get_inventory_json ---
# Они заменены вызовом INVENTORY_SCRIPT.

# --- 3. Точка входа и Разбор Действий ---

print_usage() {
  echo "Использование: $0 <action> [options]"
  echo "Действия: apply, configure, run-playbook, run-static, plan, destroy, start, stop, get-inventory"
}

# ---
# ГЛАВНЫЙ БЛОК CASE
# ---

if [ "$#" -lt 1 ]; then
  print_usage
  exit 1
fi

ACTION="$1"
shift

check_deps

case "$ACTION" in
apply)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'apply' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"
  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"

  log "Запуск Tofu Apply для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  tofu apply -auto-approve "$TOFU_VARS_ARG"

  # --- ИНТЕГРАЦИЯ: Обновление и Кэширование ---
  log "Выполнение 'tofu refresh' для обновления IP-адресов (DHCP)..."
  tofu refresh "$TOFU_VARS_ARG"

  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Невозможно продолжить: Не удалось создать кэш инвентаря."
    exit 1
  fi
  # ------------------------------------

  cd "$REPO_ROOT"

  log "Запуск Ansible (Основной плейбук) для '$COMPONENT'..."

  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Предупреждение: Основной плейбук не найден: ${ANSIBLE_PLAYBOOK}. Пропускаем конфигурацию."
  else
    # --- Проверка доступности SSH (используем новый инвентарь) ---
    log "Установка прав на скрипт инвентаря..."
    chmod +x "${INVENTORY_SCRIPT}"

    log "Получение первого IP из динамического инвентаря..."
    # ИСПРАВЛЕНО: Надежное извлечение первого IP из JSON, который выводит tofu_inventory.py.
    # Используем to_entries[0].value для получения первой пары хост:данные.
    INVENTORY_JSON=$("${INVENTORY_SCRIPT}" --list)

    FIRST_IP=$(echo "$INVENTORY_JSON" | jq -r '
        ._meta.hostvars | to_entries[0].value.ansible_host // empty
    ')

    if [ -z "$FIRST_IP" ] || [ "$FIRST_IP" == "unknown" ]; then
      log "Ошибка: Не удалось получить IP первого хоста ($FIRST_IP) через динамический инвентарь. Не могу проверить SSH."
      exit 1
    fi

    log "Ожидание доступности SSH (${FIRST_IP}:22)..."
    while ! nc -z -w5 "$FIRST_IP" 22; do
      log "Ожидание 5 секунд ($FIRST_IP:22)..."
      sleep 5
    done

    if [ -z "$FIRST_IP" ]; then
      log "Ошибка: Не удалось получить IP первого хоста через динамический инвентарь. Не могу проверить SSH."
      exit 1
    fi

    log "Ожидание доступности SSH (${FIRST_IP}:22)..."
    while ! nc -z -w5 "$FIRST_IP" 22; do
      log "Ожидание 5 секунд ($FIRST_IP:22)..."
      sleep 5
    done
    # -------------------------------------------------------------

    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
    load_ansible_secrets_to_temp_file

    ansible-playbook -i "$INVENTORY_SCRIPT" \
      --private-key "$SSH_KEY" \
      "$ANSIBLE_VARS_ARG" \
      "$ANSIBLE_PLAYBOOK"
  fi
  ;;

configure)
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    log "Ошибка: 'configure' требует <env> <component> [limit_target]"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"
  LIMIT_TARGET="${3:-all}"

  load_tofu_secrets_to_temp_file

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate" # Используется в tofu_cache_outputs

  # --- НОВОЕ: Создание кэша перед запуском Ansible ---
  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Невозможно продолжить: Не удалось создать кэш инвентаря."
    exit 1
  fi
  # --------------------------------------------------

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Основной плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Запуск Ansible (Основной плейбук) для '$COMPONENT' с лимитом '$LIMIT_TARGET'..."

  log "Установка прав на скрипт инвентаря..."
  chmod +x "${INVENTORY_SCRIPT}"

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file

  ansible-playbook -i "$INVENTORY_SCRIPT" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
    "$ANSIBLE_VARS_ARG" \
    "$ANSIBLE_PLAYBOOK"
  ;;

run-playbook)
  if [ "$#" -ne 4 ]; then
    log "Ошибка: 'run-playbook' требует <env> <component> <playbook.yml> <limit_target>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"
  PLAYBOOK_NAME="$3"
  LIMIT_TARGET="$4"

  load_tofu_secrets_to_temp_file

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  # --- НОВОЕ: Создание кэша перед запуском Ansible ---
  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Невозможно продолжить: Не удалось создать кэш инвентаря."
    exit 1
  fi
  # --------------------------------------------------

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/${PLAYBOOK_NAME}"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Запуск Ansible (Ad-Hoc) '$PLAYBOOK_NAME' для '$COMPONENT' с лимитом '$LIMIT_TARGET'..."

  log "Установка прав на скрипт инвентаря..."
  chmod +x "${INVENTORY_SCRIPT}"

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file

  ansible-playbook -i "$INVENTORY_SCRIPT" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
    "$ANSIBLE_VARS_ARG" \
    "$ANSIBLE_PLAYBOOK"
  ;;

run-static)
  # Не требует изменений, так как использует статический INI
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'run-static' требует <playbook.yml> <limit_target>"
    print_usage
    exit 1
  fi
  PLAYBOOK_NAME="$1"
  LIMIT_TARGET="$2"

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/${PLAYBOOK_NAME}"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi
  if [ ! -f "$STATIC_INVENTORY" ]; then
    log "Ошибка: Статический инвентарь не найден: ${STATIC_INVENTORY}"
    exit 1
  fi

  log "Запуск Ansible (Static) '$PLAYBOOK_NAME' с лимитом '$LIMIT_TARGET'..."

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file

  ansible-playbook -i "$STATIC_INVENTORY" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
    "$ANSIBLE_VARS_ARG" \
    "$ANSIBLE_PLAYBOOK"
  ;;

plan | destroy)
  # Не требуют изменений, так как не вызывают Ansible
  if [ "$#" -ne 2 ]; then
    log "Ошибка: '$ACTION' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Запуск Tofu '$ACTION' для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  if [ "$ACTION" == "plan" ]; then
    tofu plan "$TOFU_VARS_ARG"
  else
    tofu destroy -auto-approve "$TOFU_VARS_ARG"
  fi
  ;;

start)
  # Не требует изменений
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'start' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Запуск Tofu Apply (var.vm_started=true) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  tofu apply -var="vm_started=true" -auto-approve "$TOFU_VARS_ARG"
  ;;

stop)
  # Не требует изменений
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'stop' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Запуск Tofu Apply (var.vm_started=false) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  tofu apply -var="vm_started=false" -auto-approve "$TOFU_VARS_ARG"
  ;;

get-inventory)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'get-inventory' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  # --- НОВОЕ: Обновление кэша и вывод JSON через скрипт ---
  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Не удалось обновить кэш. Вывожу пустой JSON."
    echo "{}"
    exit 1
  fi

  log "Установка прав на скрипт инвентаря..."
  chmod +x "${INVENTORY_SCRIPT}"

  # Вывод JSON инвентаря на stdout
  "${INVENTORY_SCRIPT}" --list
  # --------------------------------------------------------
  ;;

*)
  log "Ошибка: Неизвестное действие '$ACTION'"
  print_usage
  exit 1
  ;;
esac

log "Выполнение '$ACTION' завершено."
