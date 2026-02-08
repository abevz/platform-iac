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

# --- НОВЫЕ КОНСТАНТЫ ДЛЯ ИНВЕНТАРЯ (Интеграция) ---
readonly TOFU_CACHE_DIR="${REPO_ROOT}/.cache"
readonly INVENTORY_SCRIPT="${REPO_ROOT}/tools/tofu_inventory.py"
# ---------------------------------------------------

export TF_PLUGIN_CACHE_DIR="$HOME/.cpc/plugin-cache"
#export TF_LOG=TRACE

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

  local COMPONENT="$1"

  # --- НАЧАЛО: ИСПРАВЛЕНИЕ "КУРИЦЫ И ЯЙЦА" (API, SSH Addr, SSH Port) ---
  # Values loaded from config/platform.conf (with fallback defaults)
  local _PROXMOX_DIRECT_IP="${PROXMOX_DIRECT_IP:-192.0.2.101}"
  local _PROXMOX_DIRECT_API_URL="${PROXMOX_DIRECT_API_URL:-https://${_PROXMOX_DIRECT_IP}:8006}"
  local _PROXMOX_DIRECT_SSH_PORT="${PROXMOX_DIRECT_SSH_PORT:-22}"

  local PROXMOX_PROXY_API_URL
  PROXMOX_PROXY_API_URL=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.PROXMOX_VE_ENDPOINT')
  local _PROXMOX_PROXY_SSH_ADDR="${PROXMOX_PROXY_SSH_ADDR:-homelab.example.com}"
  local _PROXMOX_PROXY_SSH_PORT="${PROXMOX_PROXY_SSH_PORT:-22006}"

  local proxmox_api_url
  local proxmox_ssh_address
  local proxmox_ssh_port

  local PUBLIC_KEY_CONTENT=""

  # 1. Главный ключ (от Ansible)
  if [ -f "${SSH_KEY}.pub" ]; then
    PUBLIC_KEY_CONTENT+=$(cat "${SSH_KEY}.pub")
    PUBLIC_KEY_CONTENT+=$'\n' # Добавляем перевод строки
  else
    log "WARN: Публичный ключ ${SSH_KEY}.pub не найден!"
  fi

  # 2. Дополнительные ключи (например, ваш личный id_rsa.pub)
  # Можно указать конкретные файлы:
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

  # Если ключей нет совсем — ставим заглушку
  if [ -z "$PUBLIC_KEY_CONTENT" ]; then
    PUBLIC_KEY_CONTENT="ssh-rsa AAAA-PLACEHOLDER"
  fi

  # Убираем последний лишний перевод строки (опционально, но аккуратно)
  PUBLIC_KEY_CONTENT="${PUBLIC_KEY_CONTENT%$'\n'}"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "ВНИМАНИЕ: Bootstrap-компонент. Используем ПРЯМОЙ IP ($_PROXMOX_DIRECT_IP) и ПРЯМОЙ порт ($_PROXMOX_DIRECT_SSH_PORT)."
    proxmox_api_url="$_PROXMOX_DIRECT_API_URL"
    proxmox_ssh_address="$_PROXMOX_DIRECT_IP"
    proxmox_ssh_port=$_PROXMOX_DIRECT_SSH_PORT
  else
    log "INFO: Service-компонент. Используем ПРОКСИ FQDN ($_PROXMOX_PROXY_SSH_ADDR) и ПРОКСИ порт ($_PROXMOX_PROXY_SSH_PORT)."
    proxmox_api_url="$_PROXMOX_PROXY_API_URL"
    proxmox_ssh_address="$_PROXMOX_PROXY_SSH_ADDR"
    proxmox_ssh_port=$_PROXMOX_PROXY_SSH_PORT
  fi
  # --- КОНЕЦ: ИСПРАВЛЕНИЯ "КУРИЦЫ И ЯЙЦА" ---

  local PROXMOX_JSON
  # 3. Передаем ВСЕ 7 переменных в jq
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

  log "Отключение SSL-проверки (Принудительно)..."
  export PROXMOX_VE_INSECURE_SKIP_TLS_VERIFY=true

  log "Загрузка секретов бэкенда (MinIO)..."
  export AWS_ACCESS_KEY_ID=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_USER')
  export AWS_SECRET_ACCESS_KEY=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_PASSWORD')
  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    log "Ошибка: Не удалось расшифровать секреты MinIO."
    exit 1
  fi

  #local
  TEMP_TFVARS_FILE=$(mktemp /tmp/iac_tfvars_XXXXXX.json)
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
  echo "Действия: deploy, apply, configure, run-playbook, run-static, plan, destroy, start, stop, get-inventory, print-envs"
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
deploy)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'deploy' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Запуск Tofu Deploy (Только Инфраструктура) для '$COMPONENT'..."
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

  # Блоки DNS и Ansible УДАЛЕНЫ для этой команды

  log "✅ Инфраструктура (deploy) успешно создана. DNS и Ansible НЕ запускались."
  ;;

apply)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'apply' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"
  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"

  log "Запуск Tofu Apply для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "ВНИМАНИЕ: Обнаружен bootstrap-компонент. Принудительная очистка .terraform/ для локального стейта..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "ВНИМАНИЕ: Запуск 'tofu init' с ЛОКАЛЬНЫМ стейтом (bootstrap)."
    tofu init
  else
    log "Запуск 'tofu init' с S3-бэкендом..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"
  fi

  #tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  tofu apply -auto-approve "$TOFU_VARS_ARG"

  # --- ИНТЕГРАЦИЯ: Обновление и Кэширование ---
  log "Выполнение 'tofu refresh' для обновления IP-адресов (DHCP)..."
  tofu refresh "$TOFU_VARS_ARG"

  if ! tofu_cache_outputs "$TERRAFORM_DIR"; then
    log "🚨 Невозможно продолжить: Не удалось создать кэш инвентаря."
    exit 1
  fi
  # ------------------------------------

  # --- НАЧАЛО НОВОГО БЛОКА: РЕГИСТРАЦИЯ DNS ---
  log "Запуск регистрации DNS в Pi-hole..."
  # Предполагаем, что add_pihole_dns.py находится в $REPO_ROOT/tools/
  PYTHON_DNS_SCRIPT="${REPO_ROOT}/tools/add_pihole_dns.py"

  if [ ! -f "$PYTHON_DNS_SCRIPT" ]; then
    log "🚨 Ошибка: Скрипт add_pihole_dns.py не найден в $PYTHON_DNS_SCRIPT"
    exit 1
  fi

  # Вызываем Python-скрипт, передавая ему путь к Tofu и файлу секретов Ansible
  # (поскольку он содержит pihole.web_password)
  if ! python3 "$PYTHON_DNS_SCRIPT" --action "add" --tf-dir "$TERRAFORM_DIR" --secrets-file "$ANSIBLE_SECRETS_FILE"; then
    log "🚨 Ошибка: Не удалось зарегистрировать DNS-записи в Pi-hole."
    exit 1
  fi
  log "✅ DNS-записи успешно зарегистрированы в Pi-hole."
  # --- КОНЕЦ НОВОГО БЛОКА ---

  cd "$REPO_ROOT"

  log "Запуск Ansible (Основной плейбук) для '$COMPONENT'..."

  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Предупреждение: Основной плейбук не найден: ${ANSIBLE_PLAYBOOK}. Пропускаем конфигурацию."
  else
    # --- Проверка доступности SSH ---
    log "Установка прав на скрипт инвентаря..."
    chmod +x "${INVENTORY_SCRIPT}"

    log "Получение первого IP из динамического инвентаря..."
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
    # -------------------------------------------------------------

    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
    load_ansible_secrets_to_temp_file

    # ОКОНЧАТЕЛЬНОЕ ИСПРАВЛЕНИЕ: Использование eval для безопасной передачи опциональных флагов.
    # Это обходит все проблемы с порядком и экранированием.

    # Собираем все аргументы в одну строку
    ANSIBLE_CMD="ansible-playbook -i $INVENTORY_SCRIPT --private-key $SSH_KEY"

    # Добавляем переменные, только если они существуют
    if [ -n "$ANSIBLE_VARS_ARG" ]; then
      ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
    fi

    # Добавляем плейбук в конце (также можно в начале, но в Bash безопаснее в конце)
    ANSIBLE_CMD+=" $ANSIBLE_PLAYBOOK"

    log "Выполнение команды: $ANSIBLE_CMD"

    # Исполняем команду
    eval $ANSIBLE_CMD

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

  load_tofu_secrets_to_temp_file "$COMPONENT"

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

  # ОКОНЧАТЕЛЬНОЕ ИСПРАВЛЕНИЕ: Использование eval для безопасной передачи опциональных флагов.
  ANSIBLE_CMD="ansible-playbook -i $INVENTORY_SCRIPT --private-key $SSH_KEY --limit $LIMIT_TARGET $ANSIBLE_PLAYBOOK"

  if [ -n "$ANSIBLE_VARS_ARG" ]; then
    ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
  fi

  log "Выполнение команды: $ANSIBLE_CMD"
  eval $ANSIBLE_CMD

  ;;

run-playbook)
  if [ "$#" -lt 4 ]; then
    log "Ошибка: 'run-playbook' требует <env> <component> <playbook.yml> <limit_target>"
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
    log "🚨 Невозможно продолжить: Не удалось создать кэш инвентаря."
    exit 1
  fi

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/${PLAYBOOK_NAME}"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Запуск Ansible (Ad-Hoc) '$PLAYBOOK_NAME' для '$COMPONENT' с лимитом '$LIMIT_TARGET'..."

  log "Установка прав на скрипт инвентаря..."
  chmod +x "${INVENTORY_SCRIPT}"

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file # Это устанавливает $ANSIBLE_VARS_ARG

  # --- НАЧАЛО ИСПРАВЛЕНИЯ (Двойное экранирование для 'eval') ---

  # Мы должны экранировать кавычки (\\"), чтобы 'eval' получил
  # строку "ansible-playbook -i \"/path1,/path2\" ...",
  # а не "ansible-playbook -i /path1,/path2 ..."

  ANSIBLE_CMD="ansible-playbook -i $INVENTORY_SCRIPT -i $STATIC_INVENTORY --private-key $SSH_KEY --limit $LIMIT_TARGET $ANSIBLE_PLAYBOOK"

  if [ -n "$ANSIBLE_VARS_ARG" ]; then
    ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
  fi

  if [ -n "$EXTRA_ANSIBLE_ARGS" ]; then
    ANSIBLE_CMD+=" $EXTRA_ANSIBLE_ARGS"
  fi
  # --- КОНЕЦ ИСПРАВЛЕНИЯ ---

  log "Выполнение команды: $ANSIBLE_CMD"
  eval $ANSIBLE_CMD
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

  # 1. Собираем базовую команду
  ANSIBLE_CMD="ansible-playbook -i $STATIC_INVENTORY --private-key $SSH_KEY --limit $LIMIT_TARGET"

  # 2. Добавляем переменные, если они есть (без кавычек, чтобы eval их правильно разобрал)
  if [ -n "$ANSIBLE_VARS_ARG" ]; then
    ANSIBLE_CMD+=" $ANSIBLE_VARS_ARG"
  fi

  # 3. Добавляем плейбук
  ANSIBLE_CMD+=" $ANSIBLE_PLAYBOOK"

  log "Выполнение команды: $ANSIBLE_CMD"

  # 4. Выполняем через eval
  eval $ANSIBLE_CMD

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

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Запуск Tofu '$ACTION' для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "ВНИМАНИЕ: Обнаружен bootstrap-компонент. Принудительная очистка .terraform/ для локального стейта..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "ВНИМАНИЕ: Запуск 'tofu init' с ЛОКАЛЬНЫМ стейтом (bootstrap)."
    tofu init
  else
    log "Запуск 'tofu init' с S3-бэкендом..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"
  fi

  #tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  if [ "$ACTION" == "plan" ]; then
    tofu plan "$TOFU_VARS_ARG"
  else
    # --- DESTROY ---

    # 1. СНАЧАЛА УДАЛЯЕМ DNS, ПОКА STATE ЕЩЕ СУЩЕСТВУЕТ
    log "Запуск удаления DNS-записей из Pi-hole (перед destroy)..."
    PYTHON_DNS_SCRIPT="${REPO_ROOT}/tools/add_pihole_dns.py"

    if [ ! -f "$PYTHON_DNS_SCRIPT" ]; then
      log "🚨 Ошибка: Скрипт add_pihole_dns.py не найден в $PYTHON_DNS_SCRIPT"
      exit 1
    fi
    if [ ! -f "$ANSIBLE_SECRETS_FILE" ]; then
      log "🚨 Ошибка: Файл секретов Ansible ($ANSIBLE_SECRETS_FILE) не найден. Не могу получить пароль Pi-hole."
      exit 1
    fi

    # Вызываем Python-скрипт с действием 'unregister-dns'
    # Он прочитает Tofu state (через tofu output), чтобы найти хосты для удаления
    if ! python3 "$PYTHON_DNS_SCRIPT" --action "unregister-dns" --tf-dir "$TERRAFORM_DIR" --secrets-file "$ANSIBLE_SECRETS_FILE"; then
      log "⚠️  Предупреждение: Не удалось удалить DNS-записи из Pi-hole. (Продолжаем destroy...)"
      # Мы НЕ выходим (exit 1), чтобы destroy все равно выполнился
    else
      log "✅ DNS-записи успешно удалены из Pi-hole."
    fi

    # 2. ТЕПЕРЬ УНИЧТОЖАЕМ VM
    log "Уничтожение инфраструктуры (tofu destroy)..."
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

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Запуск Tofu Apply (var.vm_started=true) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "ВНИМАНИЕ: Обнаружен bootstrap-компонент. Принудительная очистка .terraform/ для локального стейта..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "ВНИМАНИЕ: Запуск 'tofu init' с ЛОКАЛЬНЫМ стейтом (bootstrap)."
    tofu init
  else
    log "Запуск 'tofu init' с S3-бэкендом..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"
  fi

  #tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

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

  load_tofu_secrets_to_temp_file "$COMPONENT"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  log "Запуск Tofu Apply (var.vm_started=false) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"

  if [ "$COMPONENT" == "nginx-proxy" ] || [ "$COMPONENT" == "minio" ]; then
    log "ВНИМАНИЕ: Обнаружен bootstrap-компонент. Принудительная очистка .terraform/ для локального стейта..."
    rm -rf .terraform/ .terraform.lock.hcl
    log "ВНИМАНИЕ: Запуск 'tofu init' с ЛОКАЛЬНЫМ стейтом (bootstrap)."
    tofu init
  else
    log "Запуск 'tofu init' с S3-бэкендом..."
    tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"
  fi

  #tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

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

  load_tofu_secrets_to_temp_file "$COMPONENT"

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

print-envs)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'print-envs' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate"

  # Загрузка всех секретов и аргументов
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

  # Запуск кэширования для гарантии, что инвентарь свежий
  tofu_cache_outputs "$TERRAFORM_DIR"
  ;;

*)
  log "Ошибка: Неизвестное действие '$ACTION'"
  print_usage
  exit 1
  ;;
esac

log "Выполнение '$ACTION' завершено."
