#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Аудит ссылок на директорию 'config/' ===${NC}"
echo "Поиск файлов, которые сломаются при переименовании 'config' -> 'ansible'..."
echo ""

# 1. Поиск прямых вхождений 'config/' в коде и скриптах
# Исключаем: .git, .bare (worktrees), сам скрипт и README (текст не ломает сборку)
grep -rnI "config/" . \
  --exclude-dir={.git,.bare,.idea,.vscode} \
  --exclude="audit_config_refs.sh" \
  --exclude="README.md" \
  --exclude="*.log" |
  grep --color=always "config/"

echo ""
echo -e "${BLUE}=== Проверка ansible.cfg ===${NC}"

# 2. Проверка путей внутри ansible.cfg (roles_path)
# Если roles_path относительный, он может сломаться при перемещении самого конфига
if [ -f config/ansible.cfg ]; then
  echo "Найден config/ansible.cfg. Проверяем roles_path:"
  grep -H "roles_path" config/ansible.cfg
else
  echo -e "${RED}Файл config/ansible.cfg не найден!${NC}"
fi

echo ""
echo -e "${BLUE}=== Итог ===${NC}"
echo "1. CI/CD: Проверьте .github/workflows или .gitlab-ci.yml (если есть)"
echo "2. Wrappers: Обратите внимание на скрипты в tools/"
echo "3. Hooks: Проверьте .pre-commit-config.yaml"
