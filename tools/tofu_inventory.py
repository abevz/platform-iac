#!/usr/bin/env python3
# tools/tofu_inventory.py

import json
import sys
import os

# Путь к файлу кэша, созданному iac-wrapper.sh
CACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.cache', 'tofu-outputs.json')
OUTPUT_KEY = 'ansible_inventory_data'

def get_inventory():
    """
    Читает кэшированный JSON OpenTofu, извлекает инвентарь и выводит его в stdout.
    """

    # --- НАЧАЛО ИСПРАВЛЕНИЯ ---
    # По умолчанию считаем, что нужен --list, если не указан --host
    # Это для совместимости с ansible-playbook, который может вызывать скрипт без аргументов
    # для проверки.

    is_host_request = '--host' in sys.argv
    is_list_request = '--list' in sys.argv

    # Если не --host, считаем, что --list
    if not is_host_request:
        is_list_request = True
    # --- КОНЕЦ ИСПРАВЛЕНИЯ ---

    try:
        # 1. Загрузка всего вывода OpenTofu
        with open(CACHE_PATH, 'r') as f:
            raw_outputs = json.load(f)

        # 2. Получение значения ключа "ansible_inventory_data"
        if OUTPUT_KEY not in raw_outputs:
            print(f"Ошибка: Ключ '{OUTPUT_KEY}' не найден в файле {CACHE_PATH}", file=sys.stderr)
            sys.exit(1)

        inventory_string = raw_outputs[OUTPUT_KEY]['value']

        # 3. Десериализация вложенной JSON-строки
        final_inventory = json.loads(inventory_string)

        # 4. Вывод финального инвентаря
        if is_list_request: # <--- ИСПРАВЛЕНО
            json.dump(final_inventory, sys.stdout, indent=2)
        elif is_host_request: # <--- ИСПРАВЛЕНО
            # Ответ на запрос '--host <hostname>'
            hostname = sys.argv[sys.argv.index('--host') + 1]
            hostvars = final_inventory.get('_meta', {}).get('hostvars', {})
            json.dump(hostvars.get(hostname, {}), sys.stdout, indent=2)

    except FileNotFoundError:
        print(f"Ошибка: Файл кэша не найден по пути: {CACHE_PATH}. Выполните 'tofu apply'.", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Ошибка парсинга JSON в {CACHE_PATH}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Непредвиденная ошибка: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    get_inventory()
