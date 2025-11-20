#!/bin/bash

# Имя файла, куда будут сохраняться результаты
OUTPUT_FILE="link_check_results.log"

# Очищаем/создаем файл для результатов перед началом работы
# > "$OUTPUT_FILE" создаст пустой файл или очистит существующий
echo "Starting link check. Results will be saved to $OUTPUT_FILE"
>"$OUTPUT_FILE"

# Функция для проверки одной ссылки
# Принимает один аргумент - URL для проверки
check_url() {
  local url=$1 # Присваиваем аргумент локальной переменной для ясности

  # Используем curl для получения HTTP статус-кода
  # -o /dev/null      : Не выводить тело ответа (отправляем его в "никуда")
  # -s                : "Тихий" режим, без индикаторов прогресса
  # -w "%{http_code}" : Формат вывода - только HTTP-код ответа
  # --max-time 10     : Таймаут на выполнение запроса в 10 секунд
  http_code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "$url")

  # Записываем результат в файл вывода в формате "КОД - ССЫЛКА"
  echo "$http_code - $url" >>"$OUTPUT_FILE"

  # Также выводим в консоль для наглядности процесса
  echo "Checked: $url -> Status: $http_code"
}

# --- Основная логика скрипта ---

# Проверяем, был ли передан аргумент (имя файла) скрипту
if [ -n "$1" ]; then
  # Если аргумент есть, проверяем, что это существующий файл
  if [ -f "$1" ]; then
    echo "Reading URLs from file: $1"
    # Читаем файл построчно с помощью цикла while
    while IFS= read -r line; do
      # Пропускаем пустые строки или строки с комментариями
      if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
        check_url "$line"
      fi
    done <"$1" # Перенаправляем содержимое файла на ввод цикла
  else
    echo "Error: File '$1' not found."
    exit 1 # Выходим из скрипта с кодом ошибки
  fi
else
  # Если аргумент не передан, запрашиваем ввод у пользователя
  echo "No input file provided. Please enter URLs one by one. Press Ctrl+D when finished."
  while IFS= read -r line; do
    # Пропускаем пустые строки
    if [ -n "$line" ]; then
      check_url "$line"
    fi
  done
fi

echo "-------------------------------------"
echo "All links checked. See results in $OUTPUT_FILE"
