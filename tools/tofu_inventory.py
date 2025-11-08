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
    if '--list' not in sys.argv and '--host' not in sys.argv:
        # Абсолютный Режим: ожидаем аргументы Ansible для вывода инвентаря.
        # Если аргументов нет, ничего не делаем или выводим пустой объект (для совместимости).
        # В данном случае, просто прекращаем работу.
        print(json.dumps({}))
        sys.exit(0)

    try:
        # 1. Загрузка всего вывода OpenTofu
        with open(CACHE_PATH, 'r') as f:
            raw_outputs = json.load(f)

        # 2. Получение значения ключа "ansible_inventory_data"
        # OpenTofu/Terraform оборачивает значение в объект {'value': ...}
        if OUTPUT_KEY not in raw_outputs:
            print(f"Ошибка: Ключ '{OUTPUT_KEY}' не найден в файле {CACHE_PATH}")
            sys.exit(1)

        inventory_string = raw_outputs[OUTPUT_KEY]['value']

        # 3. Десериализация вложенной JSON-строки
        # Это ключевой шаг, решающий проблему, которую вызывал jq без fromjson.
        final_inventory = json.loads(inventory_string)

        # 4. Вывод финального инвентаря
        if '--list' in sys.argv:
            json.dump(final_inventory, sys.stdout, indent=2)
        elif '--host' in sys.argv:
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
