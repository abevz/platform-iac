#!/bin/bash
#
# iac-wrapper.sh: Единый скрипт-оркестратор для IaC.
# Связывает SOPS (секреты), Terraform (provisioning) и Ansible (configuration).
#
# ЗАВИСИМОСТИ: terraform, ansible-playbook, sops, yq, jq, nc (netcat)
#

# --- 1. Конфигурация и строгий режим ---
set -euo pipefail

# Глобальные пути и константы
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/..
SSH_KEY="~/.ssh/id_rsa"
STATIC_INVENTORY="${REPO_ROOT}/config/inventory/static.ini"
ANSIBLE_CONFIG_FILE="${REPO_ROOT}/config/ansible.cfg"

# Конфигурация S3 Backend (Бакет должен существовать)
readonly TF_STATE_BUCKET="terraform-state-bevz-net"

# Конфигурация SOPS (Файл должен существовать)
readonly PROXMOX_SECRETS_FILE="${REPO_ROOT}/config/secrets/proxmox/provider.sops.yml"

# --- 2. Вспомогательные функции ---

# Функция логирования
log() {
  # ${COMPONENT:-Global} использует "Global" если $COMPONENT еще не установлен
  echo "--- [$(date +'%T')] [${COMPONENT:-Global}] :: $*" >&2
}

# Очистка временных файлов
trap 'rm -f /tmp/iac_inventory_*.ini' EXIT

# Функция проверки зависимостей
check_deps() {
  local missing=0
  for cmd in terraform ansible-playbook sops yq jq nc; do
    if ! command -v "$cmd" &>/dev/null; then
      log "Ошибка: Необходимая зависимость '$cmd' не найдена в PATH."
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi

  # --- ИСПРАВЛЕНИЕ ЗДЕСЬ ---
  # Явно возвращаем 0 (успех), чтобы 'set -e' не остановил скрипт.
  return 0
}

# Загрузка секретов Proxmox в переменные окружения
# (НОВАЯ ВЕРСИЯ ФУНКЦИИ)
load_provider_secrets() {
  log "Настройка глобальной конфигурации SOPS..."

  # --- ВАШЕ ИЗМЕНЕНИЕ ЗДЕСЬ ---
  # Укажите точный путь к Вашему файлу .sops.yaml.
  # (Стандартный путь: $HOME/.config/sops/config.yaml, но Вы указали $HOME/.sops.yaml)

  local SOPS_CONFIG_FILE="$HOME/.sops.yaml"

  # -----------------------------

  if [ ! -f "$SOPS_CONFIG_FILE" ]; then
    log "Критическая ошибка: Файл конфигурации SOPS не найден по пути: ${SOPS_CONFIG_FILE}"
    log "Пожалуйста, исправьте путь в функции 'load_provider_secrets' в 'iac-wrapper.sh'"
    return 1
  fi

  # Экспортируем путь. Эта переменная будет "подхвачена" sops,
  # плагином 'community.sops' в Ansible и провайдером 'carlpett/sops' в Terraform.
  export SOPS_CONFIG_PATH="$SOPS_CONFIG_FILE"

  log "Загрузка секретов провайдера из SOPS (используя ${SOPS_CONFIG_FILE})..."
  if [ ! -f "$PROXMOX_SECRETS_FILE" ]; then
    log "Ошибка: Файл секретов Proxmox не найден: ${PROXMOX_SECRETS_FILE}"
    return 1
  fi

  # 'sops' теперь будет использовать --config $SOPS_CONFIG_PATH
  export PM_API_TOKEN_ID=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.proxmox_api_id')
  export PM_API_TOKEN_SECRET=$(sops -d "$PROXMOX_SECRETS_FILE" | yq -r '.proxmox_api_secret')

  if [ -z "$PM_API_TOKEN_ID" ] || [ -z "$PM_API_TOKEN_SECRET" ]; then
    log "Ошибка: Не удалось расшифровать секреты Proxmox (PM_API_TOKEN_ID/SECRET)."
    log "Убедитесь, что GPG-ключ, указанный в ${SOPS_CONFIG_FILE}, доступен в gpg-agent."
    return 1
  fi
}

# (v3) Универсальная функция генерации инвентаря
get_inventory_from_tf_state() {
  local ENV="$1"
  local COMPONENT="$2"
  local TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  # Создаем безопасный временный файл
  local TMP_INVENTORY
  TMP_INVENTORY=$(mktemp "/tmp/iac_inventory_${ENV}_${COMPONENT}.XXXXXX.ini")
  local TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate"

  log "Переход в каталог Terraform: ${TERRAFORM_DIR}"
  if [ ! -d "$TERRAFORM_DIR" ]; then
    log "Ошибка: Каталог Terraform не найден: ${TERRAFORM_DIR}"
    rm -f "$TMP_INVENTORY"
    exit 1
  fi
  cd "$TERRAFORM_DIR"

  log "Запуск 'terraform init' для подключения к S3 бэкенду..."
  terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" >/dev/null

  log "Получение 'ansible_inventory' (JSON) из Terraform state..."
  local TF_JSON_INVENTORY
  TF_JSON_INVENTORY=$(terraform output -raw ansible_inventory 2>/dev/null)

  if [ -z "$TF_JSON_INVENTORY" ]; then
    # --- ОТКАТ (Fallback) для простых VM (Harbor, revproxy) ---
    log "WARN: 'ansible_inventory' не найден. Попытка отката на 'vm_ip_address'..."
    local VM_IP
    VM_IP=$(terraform output -raw vm_ip_address 2>/dev/null)

    if [ -z "$VM_IP" ]; then
      log "Ошибка: Не найден ни 'ansible_inventory', ни 'vm_ip_address'."
      log "Пожалуйста, определите один из них в ${TERRAFORM_DIR}/outputs.tf"
      rm -f "$TMP_INVENTORY"
      exit 1
    fi

    log "Откат успешен. Генерация инвентаря для одного хоста."
    echo "[${COMPONENT}]" >"$TMP_INVENTORY"
    echo "${VM_IP} ansible_user=root" >>"$TMP_INVENTORY"
    echo "$TMP_INVENTORY" # Возвращаем путь к файлу
    return 0
    # --- КОНЕЦ ОТКАТА ---
  fi

  log "Генерация инвентаря из JSON..."
  # 'fromjson' парсит JSON-строку
  # 'to_entries[]' -> [ {key: "k", value: "v"}, ... ]
  # 'select(.value != null)' -> пропускает пустые группы (null)
  # 'select(length > 0)' -> пропускает пустые строки в массивах
  echo "$TF_JSON_INVENTORY" |
    jq -r 'fromjson | to_entries[] | select(.value != null) | "[\(.key)]\n\(.value | .[] | select(length > 0))\n"' >"$TMP_INVENTORY"

  if [ ! -s "$TMP_INVENTORY" ]; then
    log "Ошибка: Сгенерированный инвентарь пуст (JSON был, но данные некорректны)."
    rm -f "$TMP_INVENTORY"
    exit 1
  fi

  log "Универсальный инвентарь сгенерирован в ${TMP_INVENTORY}"
  echo "$TMP_INVENTORY" # Возвращаем путь к файлу
}

# (НОВАЯ) Функция вывода JSON-инвентаря
get_inventory_json() {
  local ENV="$1"
  local COMPONENT="$2"
  local TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  local TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate"

  log "Подключение к Terraform state..." >&2
  cd "$TERRAFORM_DIR"
  terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}" >/dev/null

  local TF_JSON_INVENTORY
  TF_JSON_INVENTORY=$(terraform output -raw ansible_inventory 2>/dev/null)

  if [ -z "$TF_JSON_INVENTORY" ]; then
    local VM_IP
    VM_IP=$(terraform output -raw vm_ip_address 2>/dev/null)
    if [ -z "$VM_IP" ]; then
      log "Ошибка: Не найден ни 'ansible_inventory', ни 'vm_ip_address'." >&2
      exit 1
    fi
    # Откат: генерируем JSON вручную
    jq -n --arg comp "$COMPONENT" --arg ip "$VM_IP" \
      '{($comp): [$ip]}'
  else
    # Основной путь: выводим JSON как есть
    echo "$TF_JSON_INVENTORY" | jq -r 'fromjson'
  fi
}

# --- 3. Точка входа и Разбор Действий ---

# Справка
print_usage() {
  echo "Использование: $0 <action> [options]"
  echo ""
  echo "Действия:"
  echo "  apply <env> <component>"
  echo "    (TF Apply + Ansible) Создать или обновить компонент и применить *основной* плейбук."
  echo ""
  echo "  configure <env> <component> [limit_target]"
  echo "    (Ansible) Применить *основной* плейбук (setup_*.yml) к компоненту."
  echo "    [limit_target] (опционально) - ограничить выполнение (напр. 'k8s_control_plane' или '10.10.10.12')."
  echo ""
  echo "  run-playbook <env> <component> <playbook.yml> <limit_target>"
  echo "    (Ansible Ad-Hoc) Выполнить *произвольный* плейбук (напр. 'set_timezone.yml')"
  echo "    на *конкретную цель* (напр. 'k8s_control_plane' или '10.10.10.12')."
  echo ""
  echo "  run-static <playbook.yml> <limit_target>"
  echo "    (Ansible Static) Выполнить *произвольный* плейбук на хосты из 'static.ini'."
  echo ""
  echo "  plan <env> <component>"
  echo "    (TF Plan) Показать план изменений Terraform."
  echo ""
  echo "  destroy <env> <component>"
  echo "    (TF Destroy) Уничтожить компонент."
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

case "$ACTION" in
apply)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'apply' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  check_deps
  load_provider_secrets

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate"
  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"

  log "Запуск Terraform Apply для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"
  terraform apply -auto-approve

  log "Запуск Ansible (Основной плейбук) для '$COMPONENT'..."
  local TMP_INVENTORY
  TMP_INVENTORY=$(get_inventory_from_tf_state "$ENV" "$COMPONENT")

  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Предупреждение: Основной плейбук не найден: ${ANSIBLE_PLAYBOOK}. Пропускаем конфигурацию."
  else
    log "Ожидание доступности SSH (проверка по первому хосту в инвентаре)..."
    # Получаем первый IP из инвентаря (пропускаем строки с '[')
    FIRST_HOST=$(grep -vE '^\s*[' "$TMP_INVENTORY" | head -n 1 | awk '{print $1}')
    while ! nc -z -w5 "$FIRST_HOST" 22; do
      log "Ожидание 5 секунд..."
      sleep 5
    done

    export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"

    ansible-playbook -i "$TMP_INVENTORY" \
      --private-key "$SSH_KEY" \
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
  LIMIT_TARGET="${3:-all}" # Если 3-й арг не задан, --limit=all (безвредно)

  check_deps
  load_provider_secrets

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/setup_${COMPONENT}.yml"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Основной плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Запуск Ansible (Основной плейбук) для '$COMPONENT' с лимитом '$LIMIT_TARGET'..."
  local TMP_INVENTORY
  TMP_INVENTORY=$(get_inventory_from_tf_state "$ENV" "$COMPONENT")

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"

  ansible-playbook -i "$TMP_INVENTORY" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
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

  check_deps
  load_provider_secrets

  ANSIBLE_PLAYBOOK="${REPO_ROOT}/config/playbooks/${PLAYBOOK_NAME}"
  if [ ! -f "$ANSIBLE_PLAYBOOK" ]; then
    log "Ошибка: Плейбук не найден: ${ANSIBLE_PLAYBOOK}"
    exit 1
  fi

  log "Запуск Ansible (Ad-Hoc) '$PLAYBOOK_NAME' для '$COMPONENT' с лимитом '$LIMIT_TARGET'..."
  local TMP_INVENTORY
  TMP_INVENTORY=$(get_inventory_from_tf_state "$ENV" "$COMPONENT")

  export ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE"

  ansible-playbook -i "$TMP_INVENTORY" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
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

  check_deps

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

  ansible-playbook -i "$STATIC_INVENTORY" \
    --private-key "$SSH_KEY" \
    --limit "$LIMIT_TARGET" \
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

  check_deps
  load_provider_secrets

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate"

  log "Запуск Terraform '$ACTION' для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  if [ "$ACTION" == "plan" ]; then
    terraform plan
  else
    terraform destroy -auto-approve
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

  check_deps
  load_provider_secrets

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate"

  log "Запуск Terraform Apply (var.vm_started=true) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  # Применяем состояние "запущено"
  terraform apply -var="vm_started=true" -auto-approve
  ;;

#
# --- НОВЫЙ БЛОК 'stop' ---
#
stop)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'stop' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  check_deps
  load_provider_secrets

  TERRAFORM_DIR="${REPO_ROOT}/infra/${ENV}/${COMPONENT}"
  TF_STATE_KEY="${ENV}/${COMPONENT}/terraform.tfstate"

  log "Запуск Terraform Apply (var.vm_started=false) для '$COMPONENT'..."
  cd "$TERRAFORM_DIR"
  terraform init -backend-config="bucket=${TF_STATE_BUCKET}" -backend-config="key=${TF_STATE_KEY}"

  # Применяем состояние "остановлено"
  terraform apply -var="vm_started=false" -auto-approve
  ;;

get-inventory)
  if [ "$#" -ne 2 ]; then
    log "Ошибка: 'get-inventory' требует <env> <component>"
    print_usage
    exit 1
  fi
  ENV="$1"
  COMPONENT="$2"

  check_deps
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
