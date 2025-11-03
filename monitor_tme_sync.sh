#!/bin/bash

# TME Sync Monitor - Мониторинг синхронизации в реальном времени
# Показывает статистику, скорость, прогноз завершения

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/tme_sync.log"
DB_NAME="calculator_db"
DB_USER="calculator_user"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}           TME СИНХРОНИЗАЦИЯ - МОНИТОРИНГ                    ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Функция получения статистики из БД
get_db_stats() {
    psql -U $DB_USER -d $DB_NAME -t -A -F'|' -c "
        SELECT 
            COUNT(*) as total,
            COUNT(CASE WHEN tme_symbol IS NOT NULL THEN 1 END) as synced,
            COUNT(CASE WHEN tme_price_eur > 0 THEN 1 END) as with_price,
            COUNT(CASE WHEN tme_availability > 0 THEN 1 END) as available,
            COUNT(CASE WHEN tme_last_sync > NOW() - INTERVAL '1 hour' THEN 1 END) as last_hour,
            COUNT(CASE WHEN tme_last_sync > NOW() - INTERVAL '5 minutes' THEN 1 END) as last_5min
        FROM parts
    " 2>/dev/null
}

# Функция парсинга лога
get_log_stats() {
    if [ -f "$LOG_FILE" ]; then
        TOTAL_BATCHES=$(grep -c "Пакет" "$LOG_FILE" 2>/dev/null || echo "0")
        ERRORS=$(grep -c "Ошибка" "$LOG_FILE" 2>/dev/null || echo "0")
        LAST_LINE=$(tail -n 1 "$LOG_FILE" 2>/dev/null)
        
        echo "$TOTAL_BATCHES|$ERRORS|$LAST_LINE"
    else
        echo "0|0|Лог не найден"
    fi
}

# Начальные значения
START_TIME=$(date +%s)
PREV_SYNCED=0

# Главный цикл мониторинга
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    # Получаем статистику из БД
    DB_STATS=$(get_db_stats)
    
    if [ -n "$DB_STATS" ]; then
        IFS='|' read -r TOTAL SYNCED WITH_PRICE AVAILABLE LAST_HOUR LAST_5MIN <<< "$DB_STATS"
        
        # Расчет прогресса
        if [ "$TOTAL" -gt 0 ]; then
            PROGRESS=$(awk "BEGIN {printf \"%.2f\", ($SYNCED/$TOTAL)*100}")
        else
            PROGRESS="0.00"
        fi
        
        # Расчет скорости
        if [ "$ELAPSED" -gt 0 ] && [ "$SYNCED" -gt "$PREV_SYNCED" ]; then
            SPEED=$(awk "BEGIN {printf \"%.2f\", ($SYNCED-$PREV_SYNCED)/10}")
        else
            SPEED="0.00"
        fi
        
        # Расчет оставшегося времени
        if [ "$SPEED" != "0.00" ]; then
            REMAINING=$((TOTAL - SYNCED))
            ETA=$(awk "BEGIN {printf \"%.0f\", $REMAINING/$SPEED}")
            ETA_HOURS=$((ETA / 3600))
            ETA_MINS=$(((ETA % 3600) / 60))
            ETA_TEXT="${ETA_HOURS}ч ${ETA_MINS}мин"
        else
            ETA_TEXT="Неизвестно"
        fi
        
        PREV_SYNCED=$SYNCED
    else
        TOTAL=0
        SYNCED=0
        WITH_PRICE=0
        AVAILABLE=0
        PROGRESS="0.00"
        SPEED="0.00"
        ETA_TEXT="Ожидание БД"
    fi
    
    # Получаем статистику из лога
    LOG_STATS=$(get_log_stats)
    IFS='|' read -r TOTAL_BATCHES ERRORS LAST_LINE <<< "$LOG_STATS"
    
    # Очищаем экран и выводим статистику
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}           TME СИНХРОНИЗАЦИЯ - МОНИТОРИНГ                    ${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${GREEN}📊 СТАТИСТИКА БД:${NC}"
    echo -e "  Всего артикулов:         ${YELLOW}$TOTAL${NC}"
    echo -e "  Синхронизировано:        ${GREEN}$SYNCED${NC} (${PROGRESS}%)"
    echo -e "  С ценами:                ${BLUE}$WITH_PRICE${NC}"
    echo -e "  В наличии:               ${CYAN}$AVAILABLE${NC}"
    echo ""
    
    # Прогресс-бар
    BAR_LENGTH=50
    FILLED=$(awk "BEGIN {printf \"%.0f\", $PROGRESS/100*$BAR_LENGTH}")
    BAR=$(printf '%*s' "$FILLED" | tr ' ' '█')
    EMPTY=$(printf '%*s' "$((BAR_LENGTH - FILLED))" | tr ' ' '░')
    
    echo -e "${GREEN}📈 ПРОГРЕСС:${NC}"
    echo -e "  [${GREEN}$BAR${NC}${EMPTY}] ${PROGRESS}%"
    echo ""
    
    echo -e "${GREEN}⚡ СКОРОСТЬ:${NC}"
    echo -e "  Текущая:                 ${YELLOW}${SPEED}${NC} артикулов/сек"
    echo -e "  За последний час:        ${BLUE}$LAST_HOUR${NC} артикулов"
    echo -e "  За последние 5 мин:      ${CYAN}$LAST_5MIN${NC} артикулов"
    echo ""
    
    echo -e "${GREEN}⏱️  ВРЕМЯ:${NC}"
    echo -e "  Прошло:                  ${YELLOW}$(date -u -d @${ELAPSED} +'%H:%M:%S')${NC}"
    echo -e "  Осталось (примерно):     ${CYAN}$ETA_TEXT${NC}"
    echo ""
    
    echo -e "${GREEN}📋 ЛОГИ:${NC}"
    echo -e "  Обработано пакетов:      ${BLUE}$TOTAL_BATCHES${NC}"
    echo -e "  Ошибок:                  ${RED}$ERRORS${NC}"
    echo ""
    
    if [ -f "$LOG_FILE" ]; then
        echo -e "${GREEN}📝 ПОСЛЕДНИЕ СОБЫТИЯ:${NC}"
        tail -n 5 "$LOG_FILE" | while IFS= read -r line; do
            if [[ "$line" == *"Ошибка"* ]] || [[ "$line" == *"❌"* ]]; then
                echo -e "  ${RED}$line${NC}"
            elif [[ "$line" == *"Успех"* ]] || [[ "$line" == *"✅"* ]]; then
                echo -e "  ${GREEN}$line${NC}"
            elif [[ "$line" == *"Пакет"* ]]; then
                echo -e "  ${CYAN}$line${NC}"
            else
                echo -e "  ${YELLOW}$line${NC}"
            fi
        done
    fi
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}⏸️  Нажмите Ctrl+C для остановки мониторинга${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    
    # Проверка завершения
    if [ "$PROGRESS" == "100.00" ]; then
        echo ""
        echo -e "${GREEN}✅ СИНХРОНИЗАЦИЯ ЗАВЕРШЕНА!${NC}"
        echo ""
        
        # Финальная статистика
        echo -e "${GREEN}📊 ИТОГОВАЯ СТАТИСТИКА:${NC}"
        echo -e "  Всего синхронизировано:  ${GREEN}$SYNCED${NC} из ${YELLOW}$TOTAL${NC}"
        echo -e "  Успешно:                 ${GREEN}$WITH_PRICE${NC}"
        echo -e "  Ошибок:                  ${RED}$ERRORS${NC}"
        echo -e "  Время работы:            ${YELLOW}$(date -u -d @${ELAPSED} +'%H:%M:%S')${NC}"
        
        break
    fi
    
    # Обновление каждые 10 секунд
    sleep 10
done
