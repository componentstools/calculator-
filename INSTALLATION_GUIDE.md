# 🚀 ПОЛНОЕ РУКОВОДСТВО ПО УСТАНОВКЕ СИСТЕМЫ КАЛЬКУЛЯТОРОВ

## 📋 СОДЕРЖАНИЕ

1. [Обзор системы](#обзор-системы)
2. [Требования](#требования)
3. [Установка PostgreSQL](#установка-postgresql)
4. [Настройка базы данных](#настройка-базы-данных)
5. [Установка PHP API](#установка-php-api)
6. [Настройка Nexar/Octopart](#настройка-nexaroctopart)
7. [Настройка TME](#настройка-tme)
8. [Развертывание калькуляторов](#развертывание-калькуляторов)
9. [Интеграция с Битрикс](#интеграция-с-битрикс)
10. [Автоматизация](#автоматизация)

---

## 🎯 ОБЗОР СИСТЕМЫ

Система состоит из:

### **Компоненты:**
1. **PostgreSQL БД** - хранение 1+ млн артикулов, расчетов, истории
2. **PHP API** - бэкенд с интеграцией Nexar/Octopart и TME
3. **Административный калькулятор** - полный функционал для руководства
4. **Менеджерский калькулятор** - упрощенный интерфейс с авторизацией
5. **Модуль синхронизации TME** - автообновление цен и наличия
6. **Модуль интеграции Битрикс** - синхронизация каталога

### **Особенности:**
- ✅ 1+ миллион артикулов
- ✅ Автообновление цен через TME API
- ✅ Поиск деталей через Nexar/Octopart
- ✅ Индивидуальная авторизация менеджеров
- ✅ История всех расчетов
- ✅ Интеграция с Битрикс и OpenCart
- ✅ Кэширование для производительности

---

## 🔧 ТРЕБОВАНИЯ

### **Сервер:**
- OS: CentOS 7 / Ubuntu 20.04+
- RAM: минимум 4GB (рекомендуется 8GB)
- CPU: 2+ ядра
- Диск: 50GB+ SSD

### **Софт:**
```bash
- PostgreSQL 14+
- PHP 7.4+ (лучше 8.0+)
- Nginx или Apache
- Composer (для PHP зависимостей)
- Cron (для автоматизации)
```

### **PHP расширения:**
```bash
php-pgsql
php-curl
php-json
php-mbstring
php-xml
```

---

## 📦 УСТАНОВКА POSTGRESQL

### **CentOS 7:**

```bash
# 1. Добавляем репозиторий PostgreSQL 14
sudo yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# 2. Устанавливаем PostgreSQL
sudo yum install -y postgresql14-server postgresql14-contrib

# 3. Инициализируем базу данных
sudo /usr/pgsql-14/bin/postgresql-14-setup initdb

# 4. Запускаем и добавляем в автозагрузку
sudo systemctl enable postgresql-14
sudo systemctl start postgresql-14

# 5. Проверяем статус
sudo systemctl status postgresql-14
```

### **Ubuntu 20.04+:**

```bash
# 1. Добавляем репозиторий
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# 2. Обновляем и устанавливаем
sudo apt update
sudo apt install -y postgresql-14 postgresql-contrib-14

# 3. Проверяем
sudo systemctl status postgresql
```

---

## 🗄️ НАСТРОЙКА БАЗЫ ДАННЫХ

### **1. Создаем пользователя и БД:**

```bash
# Переключаемся на пользователя postgres
sudo -u postgres psql

# В psql выполняем:
CREATE DATABASE calculator_db;
CREATE USER calculator_user WITH ENCRYPTED PASSWORD 'ваш_сложный_пароль';
GRANT ALL PRIVILEGES ON DATABASE calculator_db TO calculator_user;

# Для PostgreSQL 15+:
\c calculator_db
GRANT ALL ON SCHEMA public TO calculator_user;

# Выходим
\q
```

### **2. Настраиваем доступ:**

```bash
# Редактируем pg_hba.conf
sudo nano /var/lib/pgsql/14/data/pg_hba.conf

# Добавляем строку (для локального доступа):
host    calculator_db    calculator_user    127.0.0.1/32    md5

# Перезапускаем PostgreSQL
sudo systemctl restart postgresql-14
```

### **3. Загружаем схему:**

```bash
# Копируем файл postgresql_schema.sql на сервер
scp postgresql_schema.sql root@ваш-сервер:/tmp/

# На сервере:
sudo -u postgres psql -d calculator_db -f /tmp/postgresql_schema.sql
```

### **4. Проверяем установку:**

```bash
sudo -u postgres psql -d calculator_db

# В psql:
\dt                          # Список таблиц
SELECT COUNT(*) FROM parts;  # Должно быть 0
\q
```

---

## 🐘 УСТАНОВКА PHP И ЗАВИСИМОСТЕЙ

### **CentOS 7:**

```bash
# 1. Добавляем EPEL и Remi репозитории
sudo yum install -y epel-release
sudo yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm

# 2. Включаем PHP 8.0
sudo yum install -y yum-utils
sudo yum-config-manager --enable remi-php80

# 3. Устанавливаем PHP и расширения
sudo yum install -y php php-cli php-fpm php-pgsql php-curl php-json php-mbstring php-xml

# 4. Проверяем
php -v
php -m | grep pgsql  # Должно вывести pgsql
```

### **Ubuntu:**

```bash
sudo apt install -y php8.0 php8.0-cli php8.0-fpm php8.0-pgsql php8.0-curl php8.0-json php8.0-mbstring php8.0-xml
```

---

## 🔌 УСТАНОВКА PHP API

### **1. Создаем директорию:**

```bash
sudo mkdir -p /var/www/calculator-api
sudo chown -R nginx:nginx /var/www/calculator-api  # Или apache:apache
```

### **2. Загружаем файлы:**

```bash
# Копируем api.php и tme_sync.php
scp api.php root@ваш-сервер:/var/www/calculator-api/
scp tme_sync.php root@ваш-сервер:/var/www/calculator-api/
```

### **3. Настраиваем api.php:**

```bash
sudo nano /var/www/calculator-api/api.php

# Изменяем строки:
define('DB_HOST', 'localhost');
define('DB_NAME', 'calculator_db');
define('DB_USER', 'calculator_user');
define('DB_PASS', 'ваш_пароль');

# Nexar credentials уже заполнены из вашего скриншота
```

### **4. Настраиваем Nginx:**

```bash
sudo nano /etc/nginx/conf.d/calculator-api.conf
```

Вставляем:

```nginx
server {
    listen 80;
    server_name api.components.tools;
    
    root /var/www/calculator-api;
    index api.php;
    
    # API endpoint
    location /api {
        try_files $uri $uri/ /api.php?$query_string;
    }
    
    # PHP обработка
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index api.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Безопасность
    location ~ /\.ht {
        deny all;
    }
}
```

```bash
# Проверяем и перезапускаем
sudo nginx -t
sudo systemctl restart nginx
```

---

## 🔐 НАСТРОЙКА NEXAR/OCTOPART

### **1. Добавляем Redirect URL в Nexar Console:**

Откройте: https://portal.nexar.com/apps/[ваш-app-id]/authorization

В поле "ДОБАВИТЬ URL-АДРЕС:" добавьте:
```
https://components.tools/calculator/oauth/callback
https://api.components.tools/oauth/callback
```

Нажмите "Редактировать раздел"

### **2. Тестируем подключение:**

```bash
curl "http://api.components.tools/api/octopart/search?mpn=ATmega328P"
```

Должен вернуть JSON с данными детали.

---

## 🛒 НАСТРОЙКА TME API

### **1. Получаем API ключи TME:**

1. Регистрируйтесь на https://www.tme.eu/
2. Переходите в "Мой аккаунт" → "API"
3. Создаете приложение и получаете:
   - API Key
   - API Secret

### **2. Настраиваем tme_sync.php:**

```bash
sudo nano /var/www/calculator-api/tme_sync.php

# Изменяем:
$tmeSync = new TMESync(
    'ВАШ_TME_API_KEY',
    'ВАШ_TME_API_SECRET',
    $db
);
```

### **3. Тестируем:**

```bash
cd /var/www/calculator-api
php tme_sync.php --mode=search --mpn=ATmega328P
```

Должно вывести информацию о детали.

---

## 🌐 РАЗВЕРТЫВАНИЕ КАЛЬКУЛЯТОРОВ

### **1. Создаем директории:**

```bash
sudo mkdir -p /var/www/components.tools/calculator
sudo mkdir -p /var/www/components.tools/calculator/manager
```

### **2. Загружаем файлы:**

```bash
# Административный калькулятор
scp calculator_components_tools.html root@сервер:/var/www/components.tools/calculator/index.html

# Менеджерский калькулятор
scp calculator_manager.html root@сервер:/var/www/components.tools/calculator/manager/index.html

# Excel калькулятор (для скачивания)
scp calculator_v2.xlsx root@сервер:/var/www/components.tools/calculator/calculator.xlsx
```

### **3. Настраиваем права:**

```bash
sudo chown -R nginx:nginx /var/www/components.tools
sudo chmod -R 755 /var/www/components.tools
```

### **4. Настраиваем Nginx для калькуляторов:**

```bash
sudo nano /etc/nginx/conf.d/components-tools.conf
```

```nginx
server {
    listen 80;
    server_name components.tools www.components.tools;
    
    root /var/www/components.tools;
    index index.html;
    
    # Административный калькулятор
    location /calculator {
        try_files $uri $uri/ /calculator/index.html;
    }
    
    # Менеджерский калькулятор
    location /calculator/manager {
        try_files $uri $uri/ /calculator/manager/index.html;
    }
    
    # Прокси к API
    location /api {
        proxy_pass http://api.components.tools;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```bash
sudo nginx -t
sudo systemctl restart nginx
```

### **5. Проверяем доступ:**

- Админ: https://components.tools/calculator/
- Менеджер: https://components.tools/calculator/manager/

---

## 🔄 СОЗДАНИЕ ПОЛЬЗОВАТЕЛЕЙ

### **1. Создаем администратора:**

```bash
sudo -u postgres psql -d calculator_db

INSERT INTO users (username, password_hash, email, role, default_profit_percent)
VALUES (
    'admin',
    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- пароль: admin123
    'admin@components.tools',
    'admin',
    25.00
);
```

### **2. Создаем менеджеров:**

```bash
# Для каждого менеджера:
INSERT INTO users (username, password_hash, email, role, default_profit_percent)
VALUES (
    'manager1',
    '$2y$10$хэш_пароля', -- генерируем через password_hash()
    'manager1@components.tools',
    'manager',
    25.00
);
```

Для генерации хэша пароля:
```php
<?php
echo password_hash('новый_пароль', PASSWORD_BCRYPT);
?>
```

---

## 🔄 АВТОМАТИЗАЦИЯ СИНХРОНИЗАЦИИ

### **1. Создаем cron задания:**

```bash
sudo crontab -e
```

Добавляем:

```bash
# Синхронизация TME каждые 2 часа
0 */2 * * * cd /var/www/calculator-api && php tme_sync.php --mode=queue --batch=100 >> /var/log/tme_sync.log 2>&1

# Очистка старых логов каждую ночь в 3:00
0 3 * * * psql -U calculator_user -d calculator_db -c "SELECT cleanup_old_logs(30);" >> /var/log/db_cleanup.log 2>&1

# Очистка кэша каждый час
0 * * * * psql -U calculator_user -d calculator_db -c "SELECT cleanup_expired_cache();" >> /var/log/cache_cleanup.log 2>&1

# Бэкап БД каждый день в 4:00
0 4 * * * pg_dump -U calculator_user calculator_db | gzip > /backups/calculator_db_$(date +\%Y\%m\%d).sql.gz
```

### **2. Создаем директории для логов:**

```bash
sudo mkdir -p /var/log/calculator
sudo mkdir -p /backups
sudo chown calculator_user:calculator_user /var/log/calculator
sudo chown calculator_user:calculator_user /backups
```

---

## 🔗 ИНТЕГРАЦИЯ С БИТРИКС

### **Модуль для Битрикс (PHP):**

Создайте файл `/local/modules/componenttools.calculator/`:

```php
<?php
// /local/modules/componenttools.calculator/lib/sync.php

namespace ComponentTools\Calculator;

use Bitrix\Main\Loader;

class Sync {
    private $apiUrl = 'https://api.components.tools/api';
    
    /**
     * Синхронизация деталей из калькулятора в каталог Битрикс
     */
    public function syncParts($limit = 100) {
        Loader::includeModule('iblock');
        
        // Получаем детали из API
        $response = file_get_contents($this->apiUrl . '/parts/list?limit=' . $limit);
        $data = json_decode($response, true);
        
        if (!$data['success']) {
            return false;
        }
        
        foreach ($data['data'] as $part) {
            $this->syncPart($part);
        }
        
        return true;
    }
    
    /**
     * Синхронизация одной детали
     */
    private function syncPart($partData) {
        $iblockId = 17; // ID вашего инфоблока каталога
        
        // Ищем элемент по внешнему коду
        $arFilter = ['IBLOCK_ID' => $iblockId, 'EXTERNAL_ID' => 'PART_' . $partData['id']];
        $rsElement = \CIBlockElement::GetList([], $arFilter, false, false, ['ID']);
        
        $fields = [
            'IBLOCK_ID' => $iblockId,
            'NAME' => $partData['mpn'] . ' - ' . $partData['manufacturer_name'],
            'ACTIVE' => 'Y',
            'EXTERNAL_ID' => 'PART_' . $partData['id'],
            'PROPERTY_VALUES' => [
                'MPN' => $partData['mpn'],
                'MANUFACTURER' => $partData['manufacturer_name'],
                'DESCRIPTION' => $partData['description'],
                'PRICE' => $partData['our_price_rub'],
                'QUANTITY' => $partData['our_stock'],
                'DELIVERY_DAYS' => $partData['our_delivery_days']
            ]
        ];
        
        $el = new \CIBlockElement;
        
        if ($arElement = $rsElement->Fetch()) {
            // Обновляем
            $el->Update($arElement['ID'], $fields);
        } else {
            // Создаем
            $el->Add($fields);
        }
    }
}
```

### **Агент для автообновления:**

```php
// /local/php_interface/init.php

use ComponentTools\Calculator\Sync;

// Добавляем агент на синхронизацию каждые 2 часа
\CAgent::AddAgent(
    "\\ComponentTools\\Calculator\\Sync::syncParts(100);",
    "",
    "N",
    7200, // 2 часа
    "",
    "Y",
    "",
    1
);
```

---

## 📊 МОНИТОРИНГ

### **1. Проверка работы API:**

```bash
# Тест поиска детали
curl "https://api.components.tools/api/octopart/search?mpn=ATmega328P"

# Тест профиля
curl "https://api.components.tools/api/profile/active"
```

### **2. Проверка БД:**

```bash
sudo -u postgres psql -d calculator_db

-- Количество деталей
SELECT COUNT(*) FROM parts;

-- Количество расчетов
SELECT COUNT(*) FROM calculations;

-- Топ менеджеров
SELECT * FROM v_manager_stats;

-- Статистика по деталям
SELECT 
    category,
    COUNT(*) as total,
    SUM(CASE WHEN tme_price_eur IS NOT NULL THEN 1 ELSE 0 END) as with_tme_price
FROM parts
GROUP BY category;
```

### **3. Логи:**

```bash
# Логи TME синхронизации
tail -f /var/log/tme_sync.log

# Логи Nginx
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# Логи PostgreSQL
tail -f /var/lib/pgsql/14/data/log/postgresql-*.log
```

---

## 🎯 ТЕСТИРОВАНИЕ СИСТЕМЫ

### **1. Тест поиска детали через Nexar:**

```bash
curl "https://api.components.tools/api/octopart/search?mpn=ATmega328P"
```

Ожидаемый ответ:
```json
{
  "success": true,
  "data": {
    "found": true,
    "mpn": "ATmega328P",
    "manufacturer": "Microchip",
    ...
  }
}
```

### **2. Тест TME синхронизации:**

```bash
cd /var/www/calculator-api
php tme_sync.php --mode=search --mpn=STM32F103C8T6
```

### **3. Тест расчета цены:**

```bash
curl -X POST "https://api.components.tools/api/calculate" \
  -H "Content-Type: application/json" \
  -d '{
    "purchasePriceEur": 5.50,
    "desiredProfitPercent": 25
  }'
```

---

## 🆘 РЕШЕНИЕ ПРОБЛЕМ

### **Проблема: API не отвечает**

```bash
# Проверка PHP-FPM
sudo systemctl status php-fpm

# Перезапуск
sudo systemctl restart php-fpm

# Логи
tail -f /var/log/php-fpm/error.log
```

### **Проблема: БД не подключается**

```bash
# Проверка PostgreSQL
sudo systemctl status postgresql-14

# Проверка подключения
psql -U calculator_user -d calculator_db -h localhost

# Если не подключается - проверьте pg_hba.conf
```

### **Проблема: Nexar API ошибки**

Проверьте:
1. Credentials в api.php
2. Redirect URLs в Nexar Console
3. Логи: `/var/log/nginx/error.log`

---

## 📚 ДОПОЛНИТЕЛЬНЫЕ РЕСУРСЫ

- **TME API Документация:** https://api-doc.tme.eu/
- **Nexar API Документация:** https://support.nexar.com/
- **PostgreSQL Документация:** https://www.postgresql.org/docs/
- **Битрикс разработчику:** https://dev.1c-bitrix.ru/

---

## ✅ ЧЕКЛИСТ УСТАНОВКИ

- [ ] PostgreSQL установлен и настроен
- [ ] База данных создана и схема загружена
- [ ] PHP и расширения установлены
- [ ] API развернут и доступен
- [ ] Nexar/Octopart настроен и работает
- [ ] TME API настроен
- [ ] Калькуляторы развернуты
- [ ] Пользователи созданы
- [ ] Cron задания настроены
- [ ] Бэкапы настроены
- [ ] Все тесты пройдены

---

🎉 **СИСТЕМА ГОТОВА К РАБОТЕ!**

Теперь ваши менеджеры могут:
- Искать детали по артикулу
- Получать актуальные цены
- Рассчитывать цену продажи
- Выставлять счета клиентам

А администраторы могут:
- Управлять настройками
- Анализировать расчеты
- Интегрировать с Битрикс/OpenCart
- Автоматизировать обновление цен
