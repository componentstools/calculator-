# ИНСТРУКЦИЯ ПО РАЗВЕРТЫВАНИЮ НА CENTOS 7

## 🎯 ЧТО ДЕЛАТЬ

Разместить HTML калькулятор на вашем сервере с CentOS 7, чтобы менеджеры могли считать онлайн.

---

## 📋 ВАРИАНТ 1: NGINX (Рекомендуется)

### Шаг 1: Подключитесь к серверу

```bash
ssh root@your-server-ip
```

### Шаг 2: Установите NGINX (если еще не установлен)

```bash
# Обновите систему
yum update -y

# Установите NGINX
yum install epel-release -y
yum install nginx -y

# Запустите и включите автозапуск
systemctl start nginx
systemctl enable nginx
```

### Шаг 3: Настройте файрвол

```bash
# Откройте порты 80 и 443
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

### Шаг 4: Создайте директорию для калькулятора

```bash
# Создайте папку
mkdir -p /var/www/calculator

# Установите права
chown -R nginx:nginx /var/www/calculator
chmod -R 755 /var/www/calculator
```

### Шаг 5: Загрузите файл calculator.html

**Вариант А: Через SCP (с вашего компьютера)**

```bash
scp calculator.html root@your-server-ip:/var/www/calculator/index.html
```

**Вариант Б: Через nano на сервере**

```bash
nano /var/www/calculator/index.html
# Скопируйте содержимое calculator.html
# Ctrl+X → Y → Enter для сохранения
```

**Вариант В: Через wget (если файл на GitHub или другом сервере)**

```bash
cd /var/www/calculator
wget https://your-url/calculator.html -O index.html
```

### Шаг 6: Настройте NGINX для калькулятора

```bash
nano /etc/nginx/conf.d/calculator.conf
```

Вставьте следующую конфигурацию:

```nginx
server {
    listen 80;
    server_name calculator.components.tools;  # Замените на ваш домен

    root /var/www/calculator;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    # Кэширование для производительности
    location ~* \.(html|css|js)$ {
        expires 1h;
        add_header Cache-Control "public, must-revalidate, proxy-revalidate";
    }

    # Gzip сжатие
    gzip on;
    gzip_types text/html text/css application/javascript;
    gzip_min_length 1000;
}
```

### Шаг 7: Проверьте конфигурацию и перезапустите NGINX

```bash
# Проверка конфигурации
nginx -t

# Если OK, перезапустите
systemctl restart nginx
```

### Шаг 8: Настройте DNS

Добавьте А-запись в вашем DNS провайдере:

```
calculator.components.tools → IP_вашего_сервера
```

### Шаг 9: (Опционально) Установите SSL сертификат

```bash
# Установите Certbot
yum install certbot python2-certbot-nginx -y

# Получите сертификат
certbot --nginx -d calculator.components.tools

# Автообновление (добавить в cron)
echo "0 3 * * * /usr/bin/certbot renew --quiet" | crontab -
```

### Шаг 10: Проверьте работу

Откройте в браузере:
```
http://calculator.components.tools
```

или

```
https://calculator.components.tools
```

---

## 📋 ВАРИАНТ 2: APACHE (Альтернатива)

### Шаг 1: Установите Apache

```bash
yum install httpd -y
systemctl start httpd
systemctl enable httpd
```

### Шаг 2: Настройте файрвол

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

### Шаг 3: Создайте директорию

```bash
mkdir -p /var/www/calculator
chown -R apache:apache /var/www/calculator
chmod -R 755 /var/www/calculator
```

### Шаг 4: Загрузите файл

```bash
# Через nano
nano /var/www/calculator/index.html
# Вставьте содержимое calculator.html
```

### Шаг 5: Настройте виртуальный хост

```bash
nano /etc/httpd/conf.d/calculator.conf
```

Вставьте:

```apache
<VirtualHost *:80>
    ServerName calculator.components.tools
    DocumentRoot /var/www/calculator

    <Directory /var/www/calculator>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/calculator-error.log
    CustomLog /var/log/httpd/calculator-access.log combined
</VirtualHost>
```

### Шаг 6: Перезапустите Apache

```bash
systemctl restart httpd
```

---

## 📋 ВАРИАНТ 3: ИНТЕГРАЦИЯ В СУЩЕСТВУЮЩИЙ САЙТ

Если на components.tools уже работает сайт:

### Для NGINX:

```bash
# Создайте папку в существующем DocumentRoot
mkdir -p /var/www/components.tools/calculator

# Загрузите файл
cp calculator.html /var/www/components.tools/calculator/index.html

# Убедитесь что права правильные
chown -R nginx:nginx /var/www/components.tools/calculator
chmod -R 755 /var/www/components.tools/calculator
```

Доступ будет по адресу:
```
https://components.tools/calculator/
```

### Для Apache:

```bash
mkdir -p /var/www/html/calculator
cp calculator.html /var/www/html/calculator/index.html
chown -R apache:apache /var/www/html/calculator
```

---

## 🔧 НАСТРОЙКА БЕЗОПАСНОСТИ

### 1. Базовая аутентификация (если нужен пароль)

```bash
# Установите утилиты
yum install httpd-tools -y

# Создайте файл паролей
htpasswd -c /etc/nginx/.htpasswd manager

# Добавьте в конфигурацию NGINX
location / {
    auth_basic "Доступ только для менеджеров";
    auth_basic_user_file /etc/nginx/.htpasswd;
    try_files $uri $uri/ =404;
}
```

### 2. Ограничение по IP (если нужно)

```nginx
location / {
    # Разрешить только офисный IP
    allow 123.123.123.123;
    deny all;
    
    try_files $uri $uri/ =404;
}
```

### 3. Rate Limiting (защита от DDoS)

```nginx
# В http блок /etc/nginx/nginx.conf
limit_req_zone $binary_remote_addr zone=calculator:10m rate=10r/s;

# В location блок
location / {
    limit_req zone=calculator burst=20 nodelay;
    try_files $uri $uri/ =404;
}
```

---

## 📊 МОНИТОРИНГ И ЛОГИ

### Просмотр логов NGINX:

```bash
# Логи доступа
tail -f /var/log/nginx/access.log

# Логи ошибок
tail -f /var/log/nginx/error.log
```

### Просмотр логов Apache:

```bash
# Логи доступа
tail -f /var/log/httpd/calculator-access.log

# Логи ошибок
tail -f /var/log/httpd/calculator-error.log
```

### Статистика использования:

```bash
# Количество обращений за сегодня
grep $(date +%d/%b/%Y) /var/log/nginx/access.log | wc -l

# Топ IP адресов
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10
```

---

## 🎨 КАСТОМИЗАЦИЯ ПОД ВАШ БРЕНД

Если нужно изменить цвета под ваш фирменный стиль:

### 1. Откройте файл на редактирование:

```bash
nano /var/www/calculator/index.html
```

### 2. Найдите и замените цвета в секции `<style>`:

```css
/* Главный цвет (заголовок, кнопки) */
background: linear-gradient(135deg, #366092 0%, #4a7bb0 100%);
/* Замените на ваши цвета */
background: linear-gradient(135deg, #YOUR_COLOR_1 0%, #YOUR_COLOR_2 100%);

/* Кнопки */
.btn {
    background: linear-gradient(135deg, #366092 0%, #4a7bb0 100%);
}
/* Замените на ваши */

/* Цвет текста заголовка */
color: #366092;
/* Замените на ваш */
```

### 3. Сохраните (Ctrl+X → Y → Enter)

### 4. Очистите кэш браузера (Ctrl+F5)

---

## 🐛 РЕШЕНИЕ ПРОБЛЕМ

### Проблема: Страница не открывается

```bash
# Проверьте статус сервиса
systemctl status nginx
# или
systemctl status httpd

# Проверьте права на файлы
ls -la /var/www/calculator/

# Проверьте файрвол
firewall-cmd --list-all

# Проверьте логи
tail -100 /var/log/nginx/error.log
```

### Проблема: 403 Forbidden

```bash
# Исправьте права
chown -R nginx:nginx /var/www/calculator
chmod -R 755 /var/www/calculator

# Проверьте SELinux
getenforce
# Если Enforcing:
setenforce 0  # Временно
# Постоянно:
nano /etc/selinux/config
# Установите SELINUX=permissive
```

### Проблема: Изменения не видны

```bash
# Очистите кэш NGINX
rm -rf /var/cache/nginx/*
systemctl restart nginx

# Или в браузере: Ctrl+Shift+R (жесткая перезагрузка)
```

---

## 📦 BACKUP

### Настройте автоматический бэкап:

```bash
# Создайте скрипт
nano /root/backup-calculator.sh
```

Вставьте:

```bash
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR="/root/backups"
mkdir -p $BACKUP_DIR
tar -czf $BACKUP_DIR/calculator-$DATE.tar.gz /var/www/calculator
find $BACKUP_DIR -name "calculator-*.tar.gz" -mtime +30 -delete
```

Сделайте исполняемым и добавьте в cron:

```bash
chmod +x /root/backup-calculator.sh
echo "0 2 * * * /root/backup-calculator.sh" | crontab -
```

---

## 🚀 ГОТОВО!

Калькулятор развернут и готов к использованию!

**Доступ:**
- http://calculator.components.tools
- или https://calculator.components.tools (с SSL)
- или https://components.tools/calculator/ (если в подпапке)

**Следующие шаги:**
1. Протестируйте калькулятор
2. Поделитесь ссылкой с менеджерами
3. Настройте мониторинг
4. Настройте SSL сертификат (если еще не сделали)

---

## 📞 ПОДДЕРЖКА

Если возникнут проблемы:

1. Проверьте логи
2. Проверьте права на файлы
3. Проверьте файрвол
4. Проверьте конфигурацию веб-сервера

Удачи! 🎉
