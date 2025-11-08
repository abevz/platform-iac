#!/bin/bash
#
# iac-wrapper.sh: Единый скрипт-оркестратор v3.0 для 'platform-iac'.
# Связывает SOPS (секреты), Tofu (provisioning) и Ansible (configuration).
#
# ЗАВИСИМОСТИ: tofu, ansible-playbook, sops, yq, jq, nc (netcat)
#

# --- 1. Конфигурация и строгий режим ---
set -euo pipefail

# Глобальные пути и константы
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/..
STATIC_INVENTORY="${REPO_ROOT}/config/inventory/static.ini"
ANSIBLE_CONFIG_FILE="${REPO_ROOT}/config/ansible.cfg"

# --- ИЗМЕНЕНО: Ключ для Ansible ---
SSH_KEY="/home/abevz/Projects/platform-iac/cpc_deployment_key"

# Конфигурация S3 Backend (Бакет должен существовать)
readonly TF_STATE_BUCKET="terraform-state-bevz-net"

# --- ИЗМЕНЕНО: Все 3 файла секретов ---
readonly PROXMOX_SECRETS_FILE="${REPO_ROOT}/config/secrets/proxmox/provider.sops.yml"
readonly MINIO_SECRETS_FILE="${REPO_ROOT}/config/secrets/minio/backend.sops.yml"
readonly ANSIBLE_SECRETS_FILE="${REPO_ROOT}/config/secrets/ansible/extra_vars.sops.yml"

# --- Глобальные переменные ---
ANSIBLE_VARS_ARG="" # Хранит --extra-vars

# --- 2. Вспомогательные функции ---

# Функция логирования
log() {
  # ${COMPONENT:-Global} использует "Global" если $COMPONENT еще не установлен
  echo "--- [$(date +'%T')] [${COMPONENT:-Global}] :: $*" >&2
}

# --- ИЗМЕНЕНО: Очистка ---
# Гарантированно удаляет ВСЕ временные файлы
trap 'rm -f /tmp/iac_inventory_*.json /tmp/iac_vars_*.json /tmp/iac_inventory_*.ini' EXIT

# --- ИЗМЕНЕНО: check_deps (использует 'tofu') ---
check_deps() {
  log "Проверка зависимостей..."
  local missing=0
  for cmd in tofu ansible-playbook sops yq jq nc; do
    if ! command -v "$cmd" &>/dev/null; then
      log "Ошибка: Необходимая зависимость '$cmd' не найдена в PATH."
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi
  return 0
}

# --- НОВАЯ ФУНКЦИЯ: Загрузка секретов Ansible ---
load_ansible_secrets_to_temp_file() {
  if [ ! -f "$ANSIBLE_SECRETS_FILE" ]; then
    log "Файл секретов Ansible ($ANSIBLE_SECRETS_FILE) не найден. Пропускаем."
    ANSIBLE_VARS_ARG=""
    return
  fi

  log "Расшифровка секретов Ansible ($ANSIBLE_SECRETS_FILE)..."
  local TEMP_VARS_FILE=$(mktemp /tmp/iac_vars_XXXXXX.json)

  if ! sops -d "$ANSIBLE_SECRETS_FILE" | yq -o json >"$TEMP_VARS_FILE"; then
    log "Ошибка: Не удалось расшифровать или конвертировать $ANSIBLE_SECRETS_FILE"
    exit 1
  fi

  ANSIBLE_VARS_ARG="--extra-vars @${TEMP_VARS_FILE}"
}

# --- ИЗМЕНЕНО: Загрузка ВСЕХ секретов провайдера/бэкенда ---
load_provider_secrets() {
  log "Загрузка секретов бэкенда (MinIO)..."
  export AWS_ACCESS_KEY_ID=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_USER')
  export AWS_SECRET_ACCESS_KEY=$(sops -d "$MINIO_SECRETS_FILE" | yq -r '.MINIO_ROOT_PASSWORD')
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    log "Ошибка: Не удалось расшифровать секреты MinIO."
    exit 1
  fi

  log "Загрузка секретов провайдера (Proxmox)..."
  if [ ! -f "$PROXMOX_SECRETS_FILE" ]; then
    log "Ошибка: Файл секретов Proxmox не найден: ${PROXMOX_SECRETS_FILE}"
    return 1
  fi

  export PROXMOX_VE_ENDPOINT=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.PROXMOX_VE_ENDPOINT')
  export PROXMOX_VE_API_TOKEN_ID=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.PROXMOX_VE_API_TOKEN_ID')
  export PROXMOX_VE_API_TOKEN_SECRET=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.PROXMOX_VE_API_TOKEN_SECRET')
  export PROXMOX_VE_SSH_USERNAME=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.PROXMOX_VE_SSH_USERNAME')
  export PROXMOX_VE_SSH_PRIVATE_KEY=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.PROXMOX_VE_SSH_PRIVATE_KEY')

  if [ -z "$PROXMOX_VE_API_TOKEN_ID" ] || [ -z "$PROXMOX_VE_API_TOKEN_SECRET" ]; then
    log "Ошибка: Не удалось расшифровать секреты Proxmox (API_TOKEN_ID/SECRET)."
    return 1
  fi
}

# (v3) Универсальная функция генерации инвентаря
# --- ИЗМЕНЕНО: 'tofu' и убран 'ansible_user=root' ---
get_inventory_from_tf_state() {
  local ENV="$1"
  local COMPONENT="$2"
  local TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  local TMP_INVENTORY
  TMP_INVENTORY=$(mktemp "/tmp/iac_inventory_${ENV}_${COMPONENT}.XXXXXX.ini")
  local TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate" # (Убедитесь, что здесь .tfstate)

  log "Переход в каталог Tofu: ${TERRAFORM_DIR}"
  if [ ! -d "$TERRAFORM_DIR" ]; then
    log "Ошибка: Каталог Tofu не найден: ${TERRAFORM_DIR}"
    rm -f "$TMP_INVENTORY"
    exit 1
  fi
  cd "$TERRAFORM_DIR"

  log "Запуск 'tofu init' для подключения к S3 бэкенду..."
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" >/dev/null

  log "Получение 'ansible_inventory' (JSON) из Tofu state..."
  local TF_JSON_INVENTORY
  # Мы используем -json, а не -raw, чтобы Tofu сам вернул JSON
  TF_JSON_INVENTORY=$(tofu output -json ansible_inventory 2>/dev/null)

  if [ -z "$TF_JSON_INVENTORY" ]; then
    # --- ОТКАТ (Fallback) ---
    log "WARN: 'ansible_inventory' не найден. Попытка отката на 'vm_ip_address'..."
    local VM_IP
    VM_IP=$(tofu output -raw vm_ip_address 2>/dev/null)

    if [ -z "$VM_IP" ]; then
      log "Ошибка: Не найден ни 'ansible_inventory', ни 'vm_ip_address'."
      rm -f "$TMP_INVENTORY"
      exit 1
    fi

    log "Откат успешен. Генерация инвентаря для одного хоста."
    echo "[${COMPONENT}]" >"$TMP_INVENTORY"
    # Полагаемся на ansible.cfg (remote_user = abevz)
    echo "${VM_IP}" >>"$TMP_INVENTORY"
    echo "$TMP_INVENTORY" # Возвращаем путь к файлу
    return 0
    # --- КОНЕЦ ОТКАТА ---
  fi

  log "Генерация инвентаря из JSON..."
  # 'to_entries[]' -> [ {key: "k", value: "v"}, ... ]
  echo "$TF_JSON_INVENTORY" |
    jq -r 'to_entries[] | select(.value != null) | "[\(.key)]\n\(.value.hosts | .[]? | select(length > 0))\n"' >"$TMP_INVENTORY"

  if [ ! -s "$TMP_INVENTORY" ]; then
    log "Ошибка: Сгенерированный инвентарь пуст."
    rm -f "$TMP_INVENTORY"
    exit 1
  fi

  log "Универсальный инвентарь сгенерирован в ${TMP_INVENTORY}"
  echo "$TMP_INVENTORY" # Возвращаем путь к файлу
}

# (НОВАЯ) Функция вывода JSON-инвентаря
# --- ИЗМЕНЕНО: 'tofu' ---
get_inventory_json() {
  local ENV="$1"
  local COMPONENT="$2"
  local TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  local TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate"

  log "Подключение к Tofu state..." >&2
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" >/dev/null

  local TF_JSON_INVENTORY
  TF_JSON_INVENTORY=$(tofu output -json ansible_inventory 2>/dev/null)

  if [ -z "$TF_JSON_INVENTORY" ]; then
    local VM_IP
    VM_IP=$(tofu output -raw vm_ip_address 2>/dev/null)
    if [ -z "$VM_IP" ]; then
      log "Ошибка: Не найден ни 'ansible_inventory', ни 'vm_ip_address'." >&2
      exit 1
    fi
    # Откат: генерируем JSON вручную (для _meta)
    jq -n --arg comp "$COMPONENT" --arg ip "$VM_IP" \
      '{($comp): {"hosts": [$ip]}, "_meta": {"hostvars": {($ip): {"ansible_host": $ip}}}}'
  else
    # Основной путь: выводим JSON как есть
    echo "$TF_JSON_INVENTORY"
  fi
}

# --- 3. Точка входа и Разбор Действий ---

# Справка (сохраняем все Ваши команды)
print_usage() {
  echo "Использование: $0 <action> [options]"
  echo ""
  echo "Действия:"
  echo "  apply <env> <component>"
  echo "    (Tofu Apply + Ansible) Создать или обновить компонент и применить *основной* плейбук."
  echo ""
  echo "  configure <env> <component> [limit_target]"
  echo "    (Ansible) Применить *основной* плейбук (setup_*.yml) к компоненту."
  echo ""
  echo "  run-playbook <env> <component> <playbook.yml> <limit_target>"
  echo "    (Ansible Ad-Hoc) Выполнить *произвольный* плейбук (напр. 'set_timezone.yml')"
  echo "    на *конкретную цель* (напр. 'k8s_control_plane')."
  echo ""
  echo "  run-static <playbook.yml> <limit_target>"
  echo "    (Ansible Static) Выполнить *произвольный* плейбук на хосты из 'static.ini'."
  echo ""
  echo "  plan <env> <component>"
  echo "    (Tofu Plan) Показать план изменений Tofu."
  echo ""
  echo "  destroy <env> <component>"
  echo "    (Tofu Destroy) Уничтожить компонент."
  echo ""
  echo "  start <env> <component>"
  echo "    (Tofu Apply) Запускает VM (устанавливает var.vm_started=true)."
  echo ""
  echo "  stop <env> <component>"
  echo "    (Tofu Apply) Останавливает VM (устанавливает var.vm_started=false)."
  echo ""
  echo "  get-inventory <env> <component>"
  echo "    (JSON Output) Вывести инвентарь компонента в формате JSON."
  echo ""
}

# ---
# ГЛАВНЫЙ БЛОК CASE
# ---

if [ "$#" -lt 1 ]; then
  print_usage
  exit 1
fi

ACTION="$1"
shift # $1 теперь это <env> или <playbook.yml>

# Запускаем проверку зависимостей для всех действий
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

  load_provider_secrets # Загружаем Tofu/MinIO/Proxmox секреты

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate" # ИЗМЕНЕН КЛЮЧ
  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"

  log "Запуск Tofu Apply для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"
  tofu apply -auto-approve

  cd "$REPO_ROOT" # Возвращаемся в корень

  log "Запуск Ansible (Основной плейбук) для '$COMPONENT'..."
  local TMP_INVENTORY
  # Передаем 'tofu -chdir' вместо 'cd'
  TMP_INVENTORY=$(get_inventory_from_tf_state "$ENV" "$COMPONENT")

  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Предупреждение: Основной плейбук не найден: ${ANSIBLE_PLAYBOOK}. Пропускаем конфигурацию."
  else
    log "Ожидание доступности SSH (проверка по первому хосту в инвентаре)..."
    FIRST_HOST=$(grep -vE '^\s*[' "$TMP_INVENTORY" | head -n 1 | awk '{print $1}')
    while ! nc -z -w5 "$FIRST_HOST" 22; do
      log "Ожидание 5 секунд..."
      sleep 5
    done

    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
    load_ansible_secrets_to_temp_file # Загружаем Ansible секреты

    ansible-playbook -i "$TMP_INVENTORY" \
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

  load_provider_secrets # (Нужно для Tofu state)

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Основной плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Запуск Ansible (Основной плейбук) для '$COMPONENT' с лимитом '$LIMIT_TARGET'..."
  local TMP_INVENTORY
  TMP_INVENTORY=$(get_inventory_from_tf_state "$ENV" "$COMPONENT")

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file # Загружаем Ansible секреты

  ansible-playbook -i "$TMP_INVENTORY" \
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

  load_provider_secrets # (Нужно для Tofu state)

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/${PLAYBOOK_NAME}"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Запуск Ansible (Ad-Hoc) '$PLAYBOOK_NAME' для '$COMPONENT' с лимитом '$LIMIT_TARGET'..."
  local TMP_INVENTORY
  TMP_INVENTORY=$(get_inventory_from_tf_state "$ENV" "$COMPONENT")

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"
  load_ansible_secrets_to_temp_file # Загружаем Ansible секреты

  ansible-playbook -i "$TMP_INVENTORY" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
    "$ANSIBLE_VARS_ARG" \
    "$ANSIBLE_PLAYBOOK"
  ;;

run-static)
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
  load_ansible_secrets_to_temp_file # Загружаем Ansible секреты

  ansible-playbook -i "$STATIC_INVENTORY" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
    "$ANSIBLE_VARS_ARG" \
    "$ANSIBLE_PLAYBOOK"
  ;;

plan | destroy)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: '$ACTION' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_provider_secrets

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate" # ИЗМЕНЕН КЛЮЧ

  log "Запуск Tofu '$ACTION' для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  if [ "$ACTION" == "plan" ]; then
    tofu plan
  else
    tofu destroy -auto-approve
  fi
  ;;

start)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'start' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_provider_secrets

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate" # ИЗМЕНЕН КЛЮЧ

  log "Запуск Tofu Apply (var.vm_started=true) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  # Применяем состояние "запущено"
  tofu apply -var="vm_started=true" -auto-approve
  ;;

stop)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'stop' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_provider_secrets

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="infra/${ENV}/${COMPONENT}.tfstate" # ИЗМЕНЕН КЛЮЧ

  log "Запуск Tofu Apply (var.vm_started=false) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  tofu init -reconfigure -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  # Применяем состояние "остановлено"
  tofu apply -var="vm_started=false" -auto-approve
  ;;

get-inventory)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'get-inventory' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  load_provider_secrets

  # Эта функция выводит JSON в STDOUT. Логи (log) идут в STDERR.
  get_inventory_json "$ENV" "$COMPONENT"
  ;;

*)
  log "Ошибка: Неизвестное действие '$ACTION'"
  print_usage
  exit 1
  ;;
esac

log "Выполнение '$ACTION' завершено."
