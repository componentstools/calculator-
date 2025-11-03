# ⚡ QUICK START GUIDE - ЗАПУСК ЗА 10 МИНУТ

## 🎯 ЦЕЛЬ

Запустить полностью рабочую систему калькуляторов с TME синхронизацией за **10 минут**.

---

## 📋 ЧТО ПОНАДОБИТСЯ

- ✅ VPS/Сервер (CentOS 7+, Ubuntu 20+, или аналог)
- ✅ Root доступ
- ✅ Файл `SKU_all.txt` (979,904 артикулов)
- ✅ TME API Token: `9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4`

---

## 🚀 УСТАНОВКА - 3 КОМАНДЫ

### **Шаг 1: Скачать и распаковать проект**

```bash
# Создать директорию
mkdir -p /var/www/calculator-api
cd /var/www/calculator-api

# Загрузить файлы (замените на ваш метод)
# Вариант А: через SCP
scp -r /path/to/outputs/* root@your-server:/var/www/calculator-api/

# Вариант Б: через Git (если есть репозиторий)
git clone https://github.com/your-repo/calculator-api.git .

# Вариант В: вручную загрузить через FTP/SFTP
```

### **Шаг 2: Установить зависимости**

```bash
# Запустить автоматический инсталлятор
chmod +x install.sh
./install.sh
```

**ИЛИ вручную:**

```bash
# CentOS 7
yum install -y epel-release
yum install -y postgresql postgresql-server postgresql-contrib php php-pgsql nginx

# Ubuntu 20.04+
apt update
apt install -y postgresql postgresql-contrib php php-pgsql nginx

# Инициализация PostgreSQL (только CentOS)
postgresql-setup initdb
systemctl start postgresql
systemctl enable postgresql
```

### **Шаг 3: Настроить базу данных**

```bash
# Создать БД и пользователя
sudo -u postgres psql << EOF
CREATE DATABASE calculator_db;
CREATE USER calculator_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE calculator_db TO calculator_user;
\c calculator_db
GRANT ALL ON SCHEMA public TO calculator_user;
EOF

# Импортировать схему
psql -U calculator_user -d calculator_db -f postgresql_schema.sql
```

---

## ✅ ПРОВЕРКА СИСТЕМЫ

```bash
# Запустить проверку
chmod +x check_system.sh
./check_system.sh
```

**Ожидаемый результат:**
```
════════════════════════════════════════════════════════════
                  ИТОГОВЫЙ ОТЧЕТ                             
════════════════════════════════════════════════════════════

✓ Успешно:      15/15
✗ Ошибок:       0/15
⚠ Предупреждений: 0/15

✅ СИСТЕМА ПОЛНОСТЬЮ ГОТОВА К РАБОТЕ!
```

---

## 🔄 ЗАПУСК TME СИНХРОНИЗАЦИИ

### **Вариант 1: Быстрый тест (5 артикулов)**

```bash
# Протестировать TME API
chmod +x test_tme.sh
./test_tme.sh
```

### **Вариант 2: Полная синхронизация (14-18 часов)**

```bash
# Загрузить файл артикулов
scp SKU_all.txt root@your-server:/var/www/calculator-api/

# Запустить синхронизацию
php tme_mass_sync.php --file=SKU_all.txt
```

### **Вариант 3: Параллельная синхронизация (5-6 часов)** ⚡ **РЕКОМЕНДУЕТСЯ**

```bash
chmod +x parallel_tme_sync.sh
./parallel_tme_sync.sh SKU_all.txt 3
```

### **Мониторинг в реальном времени**

```bash
# В отдельном терминале
chmod +x monitor_tme_sync.sh
./monitor_tme_sync.sh
```

---

## 🌐 НАСТРОЙКА WEB-ДОСТУПА

### **Nginx конфигурация**

```bash
cat > /etc/nginx/conf.d/calculator.conf << 'EOF'
server {
    listen 80;
    server_name your-domain.com;
    
    root /var/www/calculator-api;
    index calculator_components_tools.html;
    
    # Статические файлы
    location / {
        try_files $uri $uri/ =404;
    }
    
    # API
    location /api.php {
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Логи
    access_log /var/log/nginx/calculator_access.log;
    error_log /var/log/nginx/calculator_error.log;
}
EOF

# Перезапустить Nginx
nginx -t
systemctl restart nginx
```

### **Проверка доступности**

```bash
# Локально
curl http://localhost/calculator_components_tools.html

# Удаленно
curl http://your-domain.com/calculator_components_tools.html
```

---

## 🔐 БЕЗОПАСНОСТЬ

### **1. Настроить PostgreSQL пароли**

```bash
# Отредактировать pg_hba.conf
nano /var/lib/pgsql/data/pg_hba.conf

# Изменить:
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5

# Перезапустить
systemctl restart postgresql
```

### **2. Настроить файрвол**

```bash
# CentOS
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Ubuntu
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

### **3. SSL сертификат (Let's Encrypt)**

```bash
# Установить certbot
yum install -y certbot python-certbot-nginx  # CentOS
apt install -y certbot python3-certbot-nginx  # Ubuntu

# Получить сертификат
certbot --nginx -d your-domain.com
```

---

## 👥 ДОБАВЛЕНИЕ МЕНЕДЖЕРОВ

### **Через SQL**

```sql
INSERT INTO users (username, password_hash, role, full_name, is_active)
VALUES 
    ('manager1', crypt('password123', gen_salt('bf')), 'manager', 'Иван Иванов', TRUE),
    ('manager2', crypt('password456', gen_salt('bf')), 'manager', 'Петр Петров', TRUE);
```

### **Или через API** (после настройки)

```bash
curl -X POST http://your-domain.com/api.php/users \
  -H "Content-Type: application/json" \
  -d '{
    "username": "manager1",
    "password": "password123",
    "role": "manager",
    "full_name": "Иван Иванов"
  }'
```

---

## 📊 ПРОВЕРКА РАБОТЫ

### **1. Открыть калькуляторы**

- **Админ:** `http://your-domain.com/calculator_components_tools.html`
- **Менеджер:** `http://your-domain.com/calculator_manager.html`

### **2. Протестировать поиск**

```
Введите артикул: STM32F103C8T6
Нажмите "Найти деталь"

Ожидаемый результат:
  ✅ Производитель: STMicroelectronics
  ✅ Описание: ARM Cortex-M3 32-bit MCU
  ✅ Цена: 2.50 EUR
  ✅ В наличии: 15000 шт
```

### **3. Проверить БД**

```sql
-- Количество синхронизированных артикулов
SELECT COUNT(*) FROM parts WHERE tme_symbol IS NOT NULL;

-- Последние 10 добавленных
SELECT mpn, manufacturer_id, tme_price_eur, tme_availability 
FROM parts 
WHERE tme_symbol IS NOT NULL 
ORDER BY created_at DESC 
LIMIT 10;
```

---

## 🔄 АВТОМАТИЧЕСКОЕ ОБНОВЛЕНИЕ ЦЕН

### **Настроить cron**

```bash
crontab -e
```

Добавить:

```bash
# Обновление ТОП-1000 артикулов каждый час
0 * * * * cd /var/www/calculator-api && php tme_mass_sync.php --file=/tmp/top_parts.txt >> /var/log/tme_sync_cron.log 2>&1

# Полное обновление раз в неделю (воскресенье 02:00)
0 2 * * 0 cd /var/www/calculator-api && php tme_mass_sync.php --file=SKU_all.txt >> /var/log/tme_sync_weekly.log 2>&1
```

### **Создать файл топ-артикулов**

```bash
# Экспортировать топ-1000
psql -U calculator_user -d calculator_db -c "
  COPY (
    SELECT mpn 
    FROM parts 
    WHERE calculation_count > 0 
    ORDER BY calculation_count DESC 
    LIMIT 1000
  ) TO '/tmp/top_parts.txt'
"
```

---

## 🐛 TROUBLESHOOTING

### **Проблема: PostgreSQL не подключается**

```bash
# Проверить статус
systemctl status postgresql

# Проверить порт
netstat -an | grep 5432

# Проверить логи
tail -f /var/lib/pgsql/data/pg_log/postgresql-*.log
```

### **Проблема: TME API не отвечает**

```bash
# Проверить вручную
curl -X POST https://api.tme.eu/Products/GetProducts.json \
  -H "Content-Type: application/json" \
  -d '{
    "Token": "9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4",
    "Country": "RU",
    "Language": "RU",
    "SymbolList": ["STM32F103C8T6"]
  }'
```

### **Проблема: Синхронизация медленная**

```bash
# Увеличить batch size
php tme_mass_sync.php --file=SKU_all.txt --batch=50

# Или использовать параллельную синхронизацию
./parallel_tme_sync.sh SKU_all.txt 4
```

### **Проблема: Nginx 502 Bad Gateway**

```bash
# Проверить PHP-FPM
systemctl status php-fpm

# Запустить если не работает
systemctl start php-fpm
systemctl enable php-fpm

# Проверить сокет
ls -la /var/run/php-fpm/
```

---

## 📈 МОНИТОРИНГ

### **Доступные скрипты**

```bash
# Проверка системы
./check_system.sh

# Мониторинг синхронизации
./monitor_tme_sync.sh

# Тест TME API
./test_tme.sh
```

### **Логи**

```bash
# TME синхронизация
tail -f /var/log/tme_sync.log

# Nginx
tail -f /var/log/nginx/calculator_access.log
tail -f /var/log/nginx/calculator_error.log

# PostgreSQL
tail -f /var/lib/pgsql/data/pg_log/postgresql-*.log
```

---

## ✅ ЧЕКЛИСТ УСПЕШНОГО ЗАПУСКА

- [ ] PostgreSQL установлен и работает
- [ ] База данных создана
- [ ] Схема импортирована
- [ ] PHP и Nginx настроены
- [ ] TME API отвечает на запросы
- [ ] check_system.sh показывает 100% успех
- [ ] Файл SKU_all.txt загружен
- [ ] Синхронизация запущена
- [ ] Калькуляторы доступны через браузер
- [ ] Поиск работает и возвращает результаты

---

## 🎉 ГОТОВО!

Система запущена и готова к работе!

**Следующие шаги:**
1. ✅ Дождаться завершения синхронизации (14-18 часов или 5-6 с параллелью)
2. ✅ Добавить менеджеров
3. ✅ Настроить автообновление цен
4. ✅ Начать использовать калькуляторы

**Нужна помощь?**
- Проверьте логи: `/var/log/tme_sync.log`
- Запустите: `./check_system.sh`
- Смотрите: `TROUBLESHOOTING` раздел выше

---

## 📞 КОНТАКТЫ

**Документация:**
- README.md - общее описание
- INSTALLATION_GUIDE.md - подробная установка
- TME_SYNC_GUIDE.md - TME синхронизация
- ROADMAP.md - план развития

**Логи:**
- `/var/log/tme_sync.log`
- `/var/log/nginx/calculator_access.log`
- `/var/log/nginx/calculator_error.log`

---

⚡ **ВРЕМЯ УСТАНОВКИ: ~10 минут**  
⏱️ **ВРЕМЯ СИНХРОНИЗАЦИИ: 5-18 часов** (зависит от метода)  
✅ **РЕЗУЛЬТАТ: Полностью рабочая система!**
