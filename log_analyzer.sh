#!/bin/bash

# ==========================================
# НАСТРОЙКИ
# ==========================================
LOG_FILE="/var/log/nginx/access.log"   # Путь к логу веб-сервера
OFFSET_FILE="/tmp/log_analyzer.offset" # Файл для хранения номера последней строки
LOCK_FILE="/tmp/log_analyzer.lock"     # Файл блокировки
EMAIL="1092vst@gmail.com"              # Почта для отправки отчета
TEMP_LOG="/tmp/temp_log_chunk.txt"     # Временный файл для текущего сегмента
# ==========================================

# 1. Блокировка повторного запуска
if [ -e "$LOCK_FILE" ]; then
    echo "Скрипт уже запущен. Завершение работы."
    exit 1
fi

touch "$LOCK_FILE"

# Функция очистки при выходе (удаление лока и временных файлов)
cleanup() {
    rm -f "$LOCK_FILE"
    rm -f "$TEMP_LOG"
}
trap cleanup EXIT

# 2. Определение диапазона строк
# Если файл смещения не существует, начинаем с 0
if [ ! -f "$OFFSET_FILE" ]; then
    echo 0 > "$OFFSET_FILE"
fi

LAST_LINE=$(cat "$OFFSET_FILE")
CURRENT_LINES=$(wc -l < "$LOG_FILE")

# Проверка на ротацию логов (если текущий файл меньше сохраненного значения)
if [ "$CURRENT_LINES" -lt "$LAST_LINE" ]; then
    LAST_LINE=0
fi

# Если новых строк нет, выходим
if [ "$CURRENT_LINES" -eq "$LAST_LINE" ]; then
    exit 0
fi

# 3. Извлечение данных с момента последнего запуска
# tail -n +X выводит строки, начиная с X. Нам нужно с (LAST_LINE + 1)
# head -n Y оставляет только нужное количество новых строк
LINES_TO_READ=$((CURRENT_LINES - LAST_LINE))
tail -n +$((LAST_LINE + 1)) "$LOG_FILE" | head -n "$LINES_TO_READ" > "$TEMP_LOG"

# 4. Получение временного диапазона
START_TIME=$(head -n 1 "$TEMP_LOG" | awk '{print $4}' | sed 's/
\[//')
END_TIME=$(tail -n 1 "$TEMP_LOG" | awk '{print $4}' | sed 's/
\[//')

# 5. Генерация отчета
SUBJECT="Otchet veb-servera: $START_TIME - $END_TIME"
REPORT_BODY="Otchet o rabote veb-servera\n"
REPORT_BODY+="Vremennoy diapazon: $START_TIME - $END_TIME\n"
REPORT_BODY+="--------------------------------------\n\n"

# X IP-адресов с наибольшим числом запросов
REPORT_BODY+="Top-10 IP-adresov:\n"
REPORT_BODY+=$(awk '{print $1}' "$TEMP_LOG" | sort | uniq -c | sort -rn | head -10)
REPORT_BODY+="\n\n"

# Y запрашиваемых URL с наибольшим числом запросов
REPORT_BODY+="Top-10 URL:\n"
REPORT_BODY+=$(awk '{print $7}' "$TEMP_LOG" | sort | uniq -c | sort -rn | head -10)
REPORT_BODY+="\n\n"

# Ошибки веб-сервера (коды 4xx и 5xx)
REPORT_BODY+="Oshibki (4xx i 5xx):\n"
REPORT_BODY+=$(awk '$9 ~ /^[45]/ {print $0}' "$TEMP_LOG" | head -20) 
# (Ограничим вывод 20 строками, чтобы не заспамить письмо, если ошибок много)
REPORT_BODY+="\n\n"

# Список всех кодов возврата
REPORT_BODY+="Statistika po HTTP-kodam:\n"
REPORT_BODY+=$(awk '{print $9}' "$TEMP_LOG" | sort | uniq -c | sort -rn)
REPORT_BODY+="\n\n"

# 6. Отправка почты
echo -e "$REPORT_BODY" | mail -s "$SUBJECT" "$EMAIL"

# 7. Сохранение новой позиции
echo "$CURRENT_LINES" > "$OFFSET_FILE"
