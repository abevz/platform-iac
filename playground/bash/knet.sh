#!/bin/bash

# Функция для входа в сетевой неймспейс контейнера (CRI-O/Containerd)
# Использование: source knet.sh; knet <имя_пода>

function knet() {
    if [ -z "$1" ]; then
        echo "Использование: knet <частичное_имя_пода>"
        return 1
    fi

    # Находим ID (2>/dev/null убирает мусор от crictl)
    local container_id=$(sudo crictl ps --name "$1" --state Running -q 2>/dev/null | head -n 1)

    if [ -z "$container_id" ]; then
        echo "❌ Контейнер с именем '$1' не найден."
        return 1
    fi

    local pid=$(sudo crictl inspect --output go-template --template '{{.info.pid}}' "$container_id" 2>/dev/null)

    if [ -z "$pid" ]; then
        echo "❌ Не удалось получить PID."
        return 1
    fi

    echo "✅ Входим в сеть контейнера: $1 (PID: $pid)"
    echo "⚠️  Файловая система осталась от ХОСТА. Доступны утилиты хоста."

    # МАГИЯ ЗДЕСЬ:
    # Мы передаем команду bash-у: "Настрой красный промпт и останься в оболочке"
    # --norc нужен, чтобы ваш .bashrc не перезаписал наш красивый промпт обратно
    sudo nsenter -t "$pid" -n /bin/bash --norc -c "export PS1='\[\e[1;31m\](CONTAINER-NET)\[\e[0m\] \u@\h:\w\$ '; exec /bin/bash --norc"
}
