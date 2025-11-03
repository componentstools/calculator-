#!/bin/bash

# Автоматический инсталлятор Components Tools Calculator
# Устанавливает все зависимости и настраивает систему

set -e  # Останавливаться при ошибках

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Логирование
LOG_FILE="/var/log/calculator_install.log"
touch $LOG_FILE

log() {
    echo -e "$1" | tee -a $LOG_FILE
}

log_step() {
    echo -e "${CYAN}▶ $1${NC}" | tee -a $LOG_FILE
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a $LOG_FILE
}

log_error() {
    echo -e "${RED}✗ $1${NC}" | tee -a $LOG_FILE
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a $LOG_FILE
}

# Проверка root
if [ "$EUID" -ne 0 ]; then
    log_error "Запустите скрипт с правами root (sudo)"
    exit 1
fi

clear
log "${CYAN}════════════════════════════════════════════════════════════${NC}"
log "${CYAN}     АВТОМАТИЧЕСКАЯ УСТАНОВКА COMPONENTS TOOLS CALCULATOR    ${NC}"
log "${CYAN}════════════════════════════════════════════════════════════${NC}"
log ""

# Определение ОС
log_step "Определение операционной системы..."

if [ -f /etc/centos-release ]; then
    OS="centos"
    OS_VERSION=$(cat /etc/centos-release | grep -oP '\d+' | head -1)
    log_success "CentOS $OS_VERSION"
elif [ -f /etc/redhat-release ]; then
    OS="rhel"
    OS_VERSION=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
    log_success "RHEL $OS_VERSION"
elif [ -f /etc/lsb-release ]; then
    OS="ubuntu"
    OS_VERSION=$(lsb_release -rs)
    log_success "Ubuntu $OS_VERSION"
elif [ -f /etc/debian_version ]; then
    OS="debian"
    OS_VERSION=$(cat /etc/debian_version)
    log_success "Debian $OS_VERSION"
else
    log_error "Неподдерживаемая ОС"
    exit 1
fi

log ""

# Параметры БД
DB_NAME="calculator_db"
DB_USER="calculator_user"
DB_PASS=$(openssl rand -base64 16)

log_step "Параметры базы данных:"
log "  База: $DB_NAME"
log "  Пользователь: $DB_USER"
log "  Пароль: $DB_PASS"
log ""

# Установка пакетов
log_step "Установка необходимых пакетов..."

if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
    log "Добавление EPEL репозитория..."
    yum install -y epel-release >> $LOG_FILE 2>&1
    
    log "Установка пакетов..."
    yum install -y \
        postgresql-server \
        postgresql-contrib \
        php \
        php-pgsql \
        php-json \
        php-mbstring \
        nginx \
        curl \
        jq \
        >> $LOG_FILE 2>&1
    
    log_success "Пакеты установлены"
    
elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    log "Обновление списка пакетов..."
    apt-get update >> $LOG_FILE 2>&1
    
    log "Установка пакетов..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        postgresql \
        postgresql-contrib \
        php \
        php-pgsql \
        php-json \
        php-mbstring \
        php-fpm \
        nginx \
        curl \
        jq \
        >> $LOG_FILE 2>&1
    
    log_success "Пакеты установлены"
fi

log ""

# Настройка PostgreSQL
log_step "Настройка PostgreSQL..."

if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
    # Инициализация БД (только если не инициализирована)
    if [ ! -f /var/lib/pgsql/data/PG_VERSION ]; then
        log "Инициализация базы данных..."
        postgresql-setup initdb >> $LOG_FILE 2>&1
        log_success "База данных инициализирована"
    else
        log_warning "База данных уже инициализирована, пропускаем"
    fi
fi

# Запуск PostgreSQL
systemctl start postgresql >> $LOG_FILE 2>&1
systemctl enable postgresql >> $LOG_FILE 2>&1
log_success "PostgreSQL запущен"

# Ожидание запуска
sleep 3

# Создание БД и пользователя
log "Создание базы данных и пользователя..."

sudo -u postgres psql << EOF >> $LOG_FILE 2>&1
-- Создаем БД если не существует
SELECT 'CREATE DATABASE $DB_NAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec

-- Создаем пользователя
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_USER') THEN
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
  END IF;
END
\$\$;

-- Права
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

\c $DB_NAME

GRANT ALL ON SCHEMA public TO $DB_USER;
GRANT ALL ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
EOF

log_success "База данных настроена"

# Импорт схемы
if [ -f postgresql_schema.sql ]; then
    log "Импорт схемы базы данных..."
    PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -f postgresql_schema.sql >> $LOG_FILE 2>&1
    log_success "Схема импортирована"
else
    log_warning "postgresql_schema.sql не найден, пропускаем импорт"
fi

log ""

# Настройка PHP
log_step "Настройка PHP..."

PHP_INI=$(php --ini | grep "Loaded Configuration File" | cut -d':' -f2 | xargs)

if [ -n "$PHP_INI" ]; then
    log "PHP конфигурация: $PHP_INI"
    
    # Увеличиваем лимиты
    sed -i 's/memory_limit = .*/memory_limit = 512M/' $PHP_INI
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' $PHP_INI
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 50M/' $PHP_INI
    
    log_success "PHP настроен"
fi

# Запуск PHP-FPM (если установлен)
if systemctl list-unit-files | grep -q php-fpm; then
    systemctl start php-fpm >> $LOG_FILE 2>&1
    systemctl enable php-fpm >> $LOG_FILE 2>&1
    log_success "PHP-FPM запущен"
fi

log ""

# Настройка Nginx
log_step "Настройка Nginx..."

NGINX_CONF="/etc/nginx/conf.d/calculator.conf"

cat > $NGINX_CONF << 'NGINXCONF'
server {
    listen 80;
    server_name _;
    
    root /var/www/calculator-api;
    index calculator_components_tools.html index.html;
    
    # Увеличиваем таймауты
    client_max_body_size 50M;
    fastcgi_read_timeout 300;
    
    # Статические файлы
    location / {
        try_files $uri $uri/ =404;
    }
    
    # PHP API
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Логи
    access_log /var/log/nginx/calculator_access.log;
    error_log /var/log/nginx/calculator_error.log;
}
NGINXCONF

log_success "Nginx сконфигурирован"

# Создание директории проекта
mkdir -p /var/www/calculator-api
CURRENT_DIR=$(pwd)

# Копирование файлов если они не в /var/www/calculator-api
if [ "$CURRENT_DIR" != "/var/www/calculator-api" ]; then
    log "Копирование файлов в /var/www/calculator-api..."
    cp -r * /var/www/calculator-api/ 2>/dev/null || true
    log_success "Файлы скопированы"
fi

# Права доступа
chown -R nginx:nginx /var/www/calculator-api
chmod -R 755 /var/www/calculator-api

# Проверка и перезапуск Nginx
nginx -t >> $LOG_FILE 2>&1
if [ $? -eq 0 ]; then
    systemctl start nginx >> $LOG_FILE 2>&1
    systemctl enable nginx >> $LOG_FILE 2>&1
    log_success "Nginx запущен"
else
    log_error "Ошибка конфигурации Nginx"
fi

log ""

# Создание .env файла
log_step "Создание конфигурационного файла..."

cat > /var/www/calculator-api/.env << ENVFILE
# База данных
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

# TME API
TME_TOKEN=9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4

# Nexar API (опционально)
NEXAR_CLIENT_ID=
NEXAR_CLIENT_SECRET=

# Настройки
API_BASE_URL=http://localhost
ENABLE_DEBUG=false
ENVFILE

chmod 600 /var/www/calculator-api/.env
log_success "Конфигурация создана"

log ""

# Настройка файрвола
log_step "Настройка файрвола..."

if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-service=http >> $LOG_FILE 2>&1
    firewall-cmd --permanent --add-service=https >> $LOG_FILE 2>&1
    firewall-cmd --reload >> $LOG_FILE 2>&1
    log_success "Firewalld настроен"
elif command -v ufw &> /dev/null; then
    ufw allow 80/tcp >> $LOG_FILE 2>&1
    ufw allow 443/tcp >> $LOG_FILE 2>&1
    log_success "UFW настроен"
else
    log_warning "Файрвол не найден, настройте вручную"
fi

log ""

# Создание скриптов
log_step "Настройка утилит..."

chmod +x *.sh 2>/dev/null || true
log_success "Скрипты готовы к использованию"

log ""

# Финальная проверка
log_step "Финальная проверка..."

ERRORS=0

# PostgreSQL
if systemctl is-active --quiet postgresql; then
    log_success "PostgreSQL работает"
else
    log_error "PostgreSQL не запущен"
    ERRORS=$((ERRORS + 1))
fi

# Nginx
if systemctl is-active --quiet nginx; then
    log_success "Nginx работает"
else
    log_error "Nginx не запущен"
    ERRORS=$((ERRORS + 1))
fi

# База данных
if PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -c "SELECT 1" >> $LOG_FILE 2>&1; then
    log_success "База данных доступна"
else
    log_error "Ошибка подключения к БД"
    ERRORS=$((ERRORS + 1))
fi

# TME API
if curl -s -X POST https://api.tme.eu/Products/GetProducts.json \
    -H "Content-Type: application/json" \
    -d '{"Token":"9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4","Country":"RU","Language":"RU","SymbolList":["STM32F103C8T6"]}' \
    | grep -q "ProductList"; then
    log_success "TME API доступен"
else
    log_warning "TME API не отвечает (проверьте интернет)"
fi

log ""

# Итоговый отчет
log "${CYAN}════════════════════════════════════════════════════════════${NC}"
log "${CYAN}                  УСТАНОВКА ЗАВЕРШЕНА                        ${NC}"
log "${CYAN}════════════════════════════════════════════════════════════${NC}"
log ""

if [ $ERRORS -eq 0 ]; then
    log "${GREEN}✅ УСТАНОВКА ПРОШЛА УСПЕШНО!${NC}"
    log ""
    log "${GREEN}📋 ИНФОРМАЦИЯ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    log "  База данных: $DB_NAME"
    log "  Пользователь: $DB_USER"
    log "  Пароль: $DB_PASS"
    log "  (сохраните в безопасном месте!)"
    log ""
    log "${YELLOW}🔧 СЛЕДУЮЩИЕ ШАГИ:${NC}"
    log ""
    log "1. Загрузите файл артикулов:"
    log "   scp SKU_all.txt root@server:/var/www/calculator-api/"
    log ""
    log "2. Запустите проверку системы:"
    log "   cd /var/www/calculator-api"
    log "   ./check_system.sh"
    log ""
    log "3. Протестируйте TME API:"
    log "   ./test_tme.sh"
    log ""
    log "4. Запустите синхронизацию:"
    log "   php tme_mass_sync.php --file=SKU_all.txt"
    log ""
    log "   ИЛИ параллельную (быстрее):"
    log "   ./parallel_tme_sync.sh SKU_all.txt 3"
    log ""
    log "5. Откройте калькулятор в браузере:"
    log "   http://$(hostname -I | awk '{print $1}')/calculator_components_tools.html"
    log ""
    log "${CYAN}📖 ДОКУМЕНТАЦИЯ:${NC}"
    log "  • README.md - общее описание"
    log "  • QUICK_START.md - быстрый старт"
    log "  • INSTALLATION_GUIDE.md - подробная установка"
    log "  • TME_SYNC_GUIDE.md - синхронизация"
    log ""
else
    log "${RED}❌ УСТАНОВКА ЗАВЕРШЕНА С ОШИБКАМИ ($ERRORS)${NC}"
    log ""
    log "Проверьте лог для деталей: $LOG_FILE"
    log ""
fi

log "${CYAN}════════════════════════════════════════════════════════════${NC}"
log ""

# Сохранение пароля в файл
echo "DB_PASS=$DB_PASS" > /var/www/calculator-api/.db_password
chmod 600 /var/www/calculator-api/.db_password
log_success "Пароль БД сохранен в: /var/www/calculator-api/.db_password"

exit $ERRORS
