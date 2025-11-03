#!/bin/bash

# TME System Check - Быстрая проверка статуса всей системы
# Проверяет: БД, API, файлы, синхронизацию

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}              ПРОВЕРКА СИСТЕМЫ                               ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Счетчики
PASSED=0
FAILED=0
WARNINGS=0

# Функция проверки с выводом результата
check() {
    local name=$1
    local command=$2
    local success_msg=$3
    local fail_msg=$4
    
    echo -n "  $name... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $success_msg"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $fail_msg"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

check_warning() {
    local name=$1
    local command=$2
    local success_msg=$3
    local warn_msg=$4
    
    echo -n "  $name... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $success_msg"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $warn_msg"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

# 1. ФАЙЛЫ
echo -e "${BLUE}1. ПРОВЕРКА ФАЙЛОВ${NC}"
check "API скрипт" "test -f $SCRIPT_DIR/api.php" "Найден" "Не найден"
check "TME синхронизация" "test -f $SCRIPT_DIR/tme_mass_sync.php" "Найден" "Не найден"
check "Калькулятор админа" "test -f $SCRIPT_DIR/calculator_components_tools.html" "Найден" "Не найден"
check "Калькулятор менеджера" "test -f $SCRIPT_DIR/calculator_manager.html" "Найден" "Не найден"
check_warning "Файл артикулов" "test -f $SCRIPT_DIR/SKU_all.txt" "Найден" "Не найден (загрузите SKU_all.txt)"
echo ""

# 2. ЗАВИСИМОСТИ
echo -e "${BLUE}2. ПРОВЕРКА ЗАВИСИМОСТЕЙ${NC}"
check "PHP" "command -v php" "$(php -v | head -1 | cut -d' ' -f2)" "Не установлен"
check "PostgreSQL" "command -v psql" "$(psql --version | cut -d' ' -f3)" "Не установлен"
check "curl" "command -v curl" "Установлен" "Не установлен"
check_warning "jq" "command -v jq" "Установлен" "Не установлен (рекомендуется для JSON)"
echo ""

# 3. БАЗА ДАННЫХ
echo -e "${BLUE}3. ПРОВЕРКА БАЗЫ ДАННЫХ${NC}"

DB_USER="calculator_user"
DB_NAME="calculator_db"

check "Подключение к БД" "psql -U $DB_USER -d $DB_NAME -c 'SELECT 1' 2>&1 | grep -q '1'" "Успешно" "Ошибка подключения"

if psql -U $DB_USER -d $DB_NAME -c 'SELECT 1' > /dev/null 2>&1; then
    # Проверяем таблицы
    check "Таблица parts" "psql -U $DB_USER -d $DB_NAME -c \"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'parts')\" | grep -q 't'" "Существует" "Не найдена"
    
    check "Таблица manufacturers" "psql -U $DB_USER -d $DB_NAME -c \"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'manufacturers')\" | grep -q 't'" "Существует" "Не найдена"
    
    # Статистика
    if psql -U $DB_USER -d $DB_NAME -c "SELECT 1 FROM parts LIMIT 1" > /dev/null 2>&1; then
        TOTAL=$(psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM parts" 2>/dev/null | xargs)
        TME_SYNCED=$(psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM parts WHERE tme_symbol IS NOT NULL" 2>/dev/null | xargs)
        WITH_PRICE=$(psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM parts WHERE tme_price_eur > 0" 2>/dev/null | xargs)
        
        echo -e "  ${GREEN}✓${NC} Статистика БД:"
        echo "      Всего артикулов: $TOTAL"
        echo "      TME синхронизировано: $TME_SYNCED"
        echo "      С ценами: $WITH_PRICE"
        PASSED=$((PASSED + 1))
    fi
fi
echo ""

# 4. TME API
echo -e "${BLUE}4. ПРОВЕРКА TME API${NC}"

TME_TOKEN="9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4"

echo -n "  Тестовый запрос к TME... "
TME_RESPONSE=$(curl -s -X POST https://api.tme.eu/Products/GetProducts.json \
    -H "Content-Type: application/json" \
    -d "{
        \"Token\": \"$TME_TOKEN\",
        \"Country\": \"RU\",
        \"Language\": \"RU\",
        \"SymbolList\": [\"STM32F103C8T6\"]
    }")

if echo "$TME_RESPONSE" | grep -q "ProductList"; then
    echo -e "${GREEN}✓${NC} API работает"
    PASSED=$((PASSED + 1))
    
    # Проверяем детали ответа
    if echo "$TME_RESPONSE" | grep -q "Description"; then
        echo -e "    ${GREEN}✓${NC} Получены данные продукта"
    fi
else
    echo -e "${RED}✗${NC} API не отвечает или ошибка токена"
    FAILED=$((FAILED + 1))
fi
echo ""

# 5. ПРОЦЕССЫ СИНХРОНИЗАЦИИ
echo -e "${BLUE}5. ПРОВЕРКА ПРОЦЕССОВ${NC}"

echo -n "  Активная синхронизация... "
if pgrep -f "tme_mass_sync.php" > /dev/null; then
    SYNC_PID=$(pgrep -f "tme_mass_sync.php")
    echo -e "${GREEN}✓${NC} Запущена (PID: $SYNC_PID)"
    PASSED=$((PASSED + 1))
    
    # Проверяем лог
    if [ -f "/var/log/tme_sync.log" ]; then
        LAST_UPDATE=$(stat -c %y /var/log/tme_sync.log | cut -d'.' -f1)
        echo "      Последнее обновление: $LAST_UPDATE"
    fi
else
    echo -e "${YELLOW}⚠${NC} Не запущена"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 6. WEB-СЕРВЕР
echo -e "${BLUE}6. ПРОВЕРКА WEB-СЕРВЕРА${NC}"

check_warning "Nginx" "systemctl is-active --quiet nginx" "Запущен" "Не запущен или не установлен"
check_warning "Apache" "systemctl is-active --quiet httpd || systemctl is-active --quiet apache2" "Запущен" "Не запущен или не установлен"

# Проверяем доступность API
if systemctl is-active --quiet nginx || systemctl is-active --quiet httpd || systemctl is-active --quiet apache2; then
    echo -n "  API endpoint... "
    if curl -s "http://localhost/api.php/health" | grep -q "ok"; then
        echo -e "${GREEN}✓${NC} Доступен"
        PASSED=$((PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} Недоступен (проверьте настройки)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi
echo ""

# 7. ЛОГИ
echo -e "${BLUE}7. ПРОВЕРКА ЛОГОВ${NC}"

check_warning "TME sync лог" "test -f /var/log/tme_sync.log" "Найден" "Не найден"

if [ -f "/var/log/tme_sync.log" ]; then
    ERRORS=$(grep -c "Ошибка" /var/log/tme_sync.log 2>/dev/null || echo "0")
    if [ "$ERRORS" -gt 0 ]; then
        echo -e "    ${YELLOW}⚠${NC} Найдено ошибок в логе: $ERRORS"
        echo "      Последние 3 ошибки:"
        grep "Ошибка" /var/log/tme_sync.log | tail -3 | while read line; do
            echo "        - ${line:0:80}..."
        done
    else
        echo -e "    ${GREEN}✓${NC} Ошибок не найдено"
    fi
fi
echo ""

# ИТОГОВЫЙ ОТЧЕТ
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}                  ИТОГОВЫЙ ОТЧЕТ                             ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL=$((PASSED + FAILED + WARNINGS))

echo -e "${GREEN}✓ Успешно:${NC}      $PASSED/$TOTAL"
echo -e "${RED}✗ Ошибок:${NC}       $FAILED/$TOTAL"
echo -e "${YELLOW}⚠ Предупреждений:${NC} $WARNINGS/$TOTAL"
echo ""

# Рекомендации
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}❌ СИСТЕМА НЕ ГОТОВА К РАБОТЕ${NC}"
    echo ""
    echo "Рекомендации:"
    
    if ! command -v php &> /dev/null; then
        echo "  • Установите PHP: yum install php php-pgsql"
    fi
    
    if ! psql -U $DB_USER -d $DB_NAME -c 'SELECT 1' > /dev/null 2>&1; then
        echo "  • Настройте PostgreSQL: см. INSTALLATION_GUIDE.md"
    fi
    
    if [ ! -f "$SCRIPT_DIR/SKU_all.txt" ]; then
        echo "  • Загрузите файл SKU_all.txt на сервер"
    fi
    
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  СИСТЕМА ЧАСТИЧНО ГОТОВА${NC}"
    echo ""
    echo "Предупреждения можно проигнорировать,"
    echo "но рекомендуется исправить для полной функциональности"
else
    echo -e "${GREEN}✅ СИСТЕМА ПОЛНОСТЬЮ ГОТОВА К РАБОТЕ!${NC}"
    echo ""
    echo "Следующие шаги:"
    echo "  1. Запустить тест TME:"
    echo "     ./test_tme.sh"
    echo ""
    echo "  2. Запустить синхронизацию:"
    echo "     php tme_mass_sync.php --file=SKU_all.txt"
    echo ""
    echo "  3. Мониторить процесс:"
    echo "     ./monitor_tme_sync.sh"
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
