#!/bin/bash

# TME Parallel Sync - Параллельная синхронизация для ускорения процесса
# Разбивает файл на части и запускает несколько процессов одновременно

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-SKU_all.txt}"
PARALLEL_JOBS="${2:-3}"  # Количество параллельных процессов
TME_TOKEN="${3:-9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4}"

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}        TME ПАРАЛЛЕЛЬНАЯ СИНХРОНИЗАЦИЯ                       ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Проверка файла
if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}❌ Ошибка: Файл $INPUT_FILE не найден${NC}"
    echo ""
    echo "Использование:"
    echo "  ./parallel_tme_sync.sh [файл] [процессов] [токен]"
    echo ""
    echo "Пример:"
    echo "  ./parallel_tme_sync.sh SKU_all.txt 3"
    exit 1
fi

# Проверка PHP скрипта
if [ ! -f "$SCRIPT_DIR/tme_mass_sync.php" ]; then
    echo -e "${RED}❌ Ошибка: tme_mass_sync.php не найден${NC}"
    exit 1
fi

# Подсчет строк
TOTAL_LINES=$(wc -l < "$INPUT_FILE")
echo -e "${GREEN}📦 Всего артикулов:${NC} $TOTAL_LINES"
echo -e "${BLUE}🔄 Параллельных процессов:${NC} $PARALLEL_JOBS"
echo ""

# Расчет строк на процесс
LINES_PER_JOB=$((TOTAL_LINES / PARALLEL_JOBS))
REMAINDER=$((TOTAL_LINES % PARALLEL_JOBS))

echo -e "${YELLOW}📊 Распределение:${NC}"
echo "  Строк на процесс: ~$LINES_PER_JOB"
echo "  Остаток: $REMAINDER (добавится к последнему процессу)"
echo ""

# Создание временной директории
TEMP_DIR="$SCRIPT_DIR/temp_parallel_sync"
mkdir -p "$TEMP_DIR"

echo -e "${CYAN}🔪 Разбиваем файл на части...${NC}"

# Разбиение файла
CURRENT_LINE=1
for i in $(seq 1 $PARALLEL_JOBS); do
    OUTPUT_FILE="$TEMP_DIR/part_$i.txt"
    
    if [ $i -eq $PARALLEL_JOBS ]; then
        # Последний файл - включаем остаток
        LINES_TO_TAKE=$((LINES_PER_JOB + REMAINDER))
    else
        LINES_TO_TAKE=$LINES_PER_JOB
    fi
    
    tail -n +$CURRENT_LINE "$INPUT_FILE" | head -n $LINES_TO_TAKE > "$OUTPUT_FILE"
    
    ACTUAL_LINES=$(wc -l < "$OUTPUT_FILE")
    echo -e "  ${GREEN}✓${NC} Часть $i: $ACTUAL_LINES артикулов → $OUTPUT_FILE"
    
    CURRENT_LINE=$((CURRENT_LINE + LINES_TO_TAKE))
done

echo ""
echo -e "${CYAN}🚀 Запускаем параллельную синхронизацию...${NC}"
echo ""

# Массив для PID процессов
declare -a PIDS

# Запуск процессов
for i in $(seq 1 $PARALLEL_JOBS); do
    INPUT_PART="$TEMP_DIR/part_$i.txt"
    LOG_FILE="$TEMP_DIR/sync_part_$i.log"
    
    echo -e "${BLUE}[Процесс $i]${NC} Запуск..."
    
    # Запускаем в фоне
    php "$SCRIPT_DIR/tme_mass_sync.php" \
        --file="$INPUT_PART" \
        --token="$TME_TOKEN" \
        > "$LOG_FILE" 2>&1 &
    
    PID=$!
    PIDS[$i]=$PID
    
    echo -e "${GREEN}[Процесс $i]${NC} PID: $PID"
    
    # Небольшая задержка между запусками
    sleep 2
done

echo ""
echo -e "${YELLOW}⏳ Ожидание завершения всех процессов...${NC}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo "  Мониторинг:"
echo "    tail -f $TEMP_DIR/sync_part_1.log"
echo "    tail -f $TEMP_DIR/sync_part_2.log"
echo "    tail -f $TEMP_DIR/sync_part_3.log"
echo ""
echo "  Или запустите в другом терминале:"
echo "    ./monitor_tme_sync.sh"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Функция проверки статуса процесса
check_process_status() {
    local pid=$1
    local process_num=$2
    
    if ps -p $pid > /dev/null 2>&1; then
        return 0  # Процесс работает
    else
        wait $pid
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}✅ [Процесс $process_num]${NC} Завершен успешно"
            return 0
        else
            echo -e "${RED}❌ [Процесс $process_num]${NC} Завершен с ошибкой (код: $exit_code)"
            return 1
        fi
    fi
}

# Мониторинг процессов
COMPLETED=0
FAILED=0

while [ $COMPLETED -lt $PARALLEL_JOBS ]; do
    for i in $(seq 1 $PARALLEL_JOBS); do
        PID=${PIDS[$i]}
        
        if [ -n "$PID" ]; then
            if ! ps -p $PID > /dev/null 2>&1; then
                # Процесс завершен
                wait $PID
                EXIT_CODE=$?
                
                if [ $EXIT_CODE -eq 0 ]; then
                    echo -e "${GREEN}✅ [Процесс $i]${NC} Завершен успешно (PID: $PID)"
                else
                    echo -e "${RED}❌ [Процесс $i]${NC} Завершен с ошибкой (код: $EXIT_CODE, PID: $PID)"
                    FAILED=$((FAILED + 1))
                fi
                
                COMPLETED=$((COMPLETED + 1))
                PIDS[$i]=""  # Очищаем PID
            fi
        fi
    done
    
    sleep 5
done

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 ВСЕ ПРОЦЕССЫ ЗАВЕРШЕНЫ!${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Статистика
echo -e "${GREEN}📊 ИТОГОВАЯ СТАТИСТИКА:${NC}"
echo ""

TOTAL_SUCCESS=0
TOTAL_FAILED=0
TOTAL_PROCESSED=0

for i in $(seq 1 $PARALLEL_JOBS); do
    LOG_FILE="$TEMP_DIR/sync_part_$i.log"
    
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}[Процесс $i]${NC}"
        
        # Извлекаем статистику из лога
        SUCCESS=$(grep "Обработано успешно:" "$LOG_FILE" | tail -1 | grep -oP '\d+' || echo "0")
        FAILED_COUNT=$(grep "Ошибок:" "$LOG_FILE" | tail -1 | grep -oP '\d+' || echo "0")
        PROCESSED=$(grep "Всего артикулов:" "$LOG_FILE" | tail -1 | grep -oP '\d+' || echo "0")
        
        echo "  Обработано: $PROCESSED"
        echo "  Успешно: $SUCCESS"
        echo "  Ошибок: $FAILED_COUNT"
        echo ""
        
        TOTAL_SUCCESS=$((TOTAL_SUCCESS + SUCCESS))
        TOTAL_FAILED=$((TOTAL_FAILED + FAILED_COUNT))
        TOTAL_PROCESSED=$((TOTAL_PROCESSED + PROCESSED))
    fi
done

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}ОБЩАЯ СТАТИСТИКА:${NC}"
echo "  Всего обработано: $TOTAL_PROCESSED"
echo "  Успешно: $TOTAL_SUCCESS"
echo "  Ошибок: $TOTAL_FAILED"

if [ $TOTAL_PROCESSED -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_SUCCESS/$TOTAL_PROCESSED)*100}")
    echo "  Успешность: ${SUCCESS_RATE}%"
fi

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Проверка в БД
echo -e "${YELLOW}🔍 Проверяем БД...${NC}"
DB_COUNT=$(psql -U calculator_user -d calculator_db -t -c "SELECT COUNT(*) FROM parts WHERE tme_symbol IS NOT NULL" 2>/dev/null || echo "N/A")
echo "  Артикулов в БД: $DB_COUNT"
echo ""

# Очистка или сохранение временных файлов
echo -e "${YELLOW}🗑️  Очистка временных файлов...${NC}"
read -p "Удалить временные файлы? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC} Временные файлы удалены"
else
    echo -e "${BLUE}ℹ${NC}  Временные файлы сохранены в: $TEMP_DIR"
    echo "  Логи доступны для анализа"
fi

echo ""
echo -e "${GREEN}✅ ПАРАЛЛЕЛЬНАЯ СИНХРОНИЗАЦИЯ ЗАВЕРШЕНА!${NC}"
echo ""
