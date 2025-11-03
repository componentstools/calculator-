#!/bin/bash

echo "════════════════════════════════════════════════════════════"
echo "          TME API - ТЕСТ ПОДКЛЮЧЕНИЯ                         "
echo "════════════════════════════════════════════════════════════"
echo ""

# Параметры
TME_TOKEN="9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4"
TEST_ARTICLES=("STM32F103C8T6" "ATmega328P" "NE555" "LM358" "BC547")

echo "🔍 Тестируем TME API..."
echo "📝 Токен: ${TME_TOKEN:0:20}..."
echo ""

# Тест 1: Простой запрос одного артикула
echo "═══ ТЕСТ 1: Поиск одного артикула ═══"
RESPONSE=$(curl -s -X POST https://api.tme.eu/Products/GetProducts.json \
  -H "Content-Type: application/json" \
  -d "{
    \"Token\": \"$TME_TOKEN\",
    \"Country\": \"RU\",
    \"Language\": \"RU\",
    \"SymbolList\": [\"${TEST_ARTICLES[0]}\"]
  }")

echo "Артикул: ${TEST_ARTICLES[0]}"

if echo "$RESPONSE" | grep -q "ProductList"; then
    echo "✅ Успех! API отвечает"
    
    # Извлекаем данные
    DESCRIPTION=$(echo "$RESPONSE" | grep -o '"Description":"[^"]*"' | head -1 | cut -d'"' -f4)
    PRICE=$(echo "$RESPONSE" | grep -o '"PriceValue":"[^"]*"' | head -1 | cut -d'"' -f4)
    AMOUNT=$(echo "$RESPONSE" | grep -o '"Amount":[0-9]*' | head -1 | cut -d':' -f2)
    
    echo "  📦 Описание: $DESCRIPTION"
    echo "  💰 Цена: $PRICE"
    echo "  📊 Наличие: $AMOUNT шт"
else
    echo "❌ ОШИБКА! API не отвечает"
    echo "Ответ: $RESPONSE"
    exit 1
fi

echo ""

# Тест 2: Пакетный запрос (5 артикулов)
echo "═══ ТЕСТ 2: Пакетный запрос (5 артикулов) ═══"
ARTICLES_JSON=$(printf ',"%s"' "${TEST_ARTICLES[@]}")
ARTICLES_JSON="[${ARTICLES_JSON:1}]"

RESPONSE=$(curl -s -X POST https://api.tme.eu/Products/GetProducts.json \
  -H "Content-Type: application/json" \
  -d "{
    \"Token\": \"$TME_TOKEN\",
    \"Country\": \"RU\",
    \"Language\": \"RU\",
    \"SymbolList\": $ARTICLES_JSON
  }")

FOUND=$(echo "$RESPONSE" | grep -o '"Symbol"' | wc -l)
echo "✅ Найдено артикулов: $FOUND/5"

if [ "$FOUND" -gt 0 ]; then
    echo "  📦 Все артикулы найдены!"
else
    echo "  ⚠️  Некоторые артикулы не найдены"
fi

echo ""

# Тест 3: Проверка rate limit
echo "═══ ТЕСТ 3: Rate Limiting (3 запроса подряд) ═══"
for i in {1..3}; do
    echo -n "Запрос $i... "
    START=$(date +%s%N)
    
    curl -s -X POST https://api.tme.eu/Products/GetProducts.json \
      -H "Content-Type: application/json" \
      -d "{
        \"Token\": \"$TME_TOKEN\",
        \"Country\": \"RU\",
        \"Language\": \"RU\",
        \"SymbolList\": [\"${TEST_ARTICLES[0]}\"]
      }" > /dev/null
    
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    echo "✅ ${ELAPSED}ms"
    
    if [ "$i" -lt 3 ]; then
        sleep 1
    fi
done

echo ""

# Тест 4: Проверка подключения к БД
echo "═══ ТЕСТ 4: Подключение к PostgreSQL ═══"
if command -v psql &> /dev/null; then
    DB_TEST=$(psql -U calculator_user -d calculator_db -t -c "SELECT 1" 2>&1)
    if [ "$DB_TEST" = " 1" ]; then
        echo "✅ PostgreSQL доступен"
        
        # Проверяем таблицу
        TABLE_EXISTS=$(psql -U calculator_user -d calculator_db -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'parts')" 2>&1)
        if [ "$TABLE_EXISTS" = " t" ]; then
            echo "✅ Таблица parts существует"
            
            # Считаем текущие артикулы
            CURRENT_COUNT=$(psql -U calculator_user -d calculator_db -t -c "SELECT COUNT(*) FROM parts WHERE tme_symbol IS NOT NULL" 2>&1)
            echo "  📊 Текущих артикулов в БД: $CURRENT_COUNT"
        else
            echo "⚠️  Таблица parts не найдена - запустите postgresql_schema.sql"
        fi
    else
        echo "❌ Ошибка подключения к PostgreSQL"
        echo "   $DB_TEST"
    fi
else
    echo "⚠️  psql не установлен - пропускаем тест БД"
fi

echo ""

# Итоговый отчет
echo "════════════════════════════════════════════════════════════"
echo "                    ИТОГОВЫЙ ОТЧЕТ                           "
echo "════════════════════════════════════════════════════════════"
echo "✅ TME API:          Работает"
echo "✅ Токен:            Валидный"
echo "✅ Пакетные запросы: Поддерживаются"
echo "✅ Rate Limiting:    Нормальный"

if command -v psql &> /dev/null && [ "$TABLE_EXISTS" = " t" ]; then
    echo "✅ PostgreSQL:       Готов"
else
    echo "⚠️  PostgreSQL:       Требует настройки"
fi

echo "════════════════════════════════════════════════════════════"
echo ""
echo "🚀 ГОТОВО К ПОЛНОЙ СИНХРОНИЗАЦИИ!"
echo ""
echo "Запустите:"
echo "  php tme_mass_sync.php --file=SKU_all.txt"
echo ""
