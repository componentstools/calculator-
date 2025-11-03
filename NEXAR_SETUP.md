# 🔐 НАСТРОЙКА NEXAR OAUTH

## Быстрая инструкция по добавлению Redirect URLs

### ✅ ЧТО НУЖНО СДЕЛАТЬ

1. **Откройте Nexar Portal:**
   ```
   https://portal.nexar.com/apps/e6cb4739-b509-4ea9-aa1b-57d71dc14b3d/details/authorization
   ```

2. **В разделе "URL-адреса перенаправления":**
   
   Найдите поле **"ДОБАВИТЬ URL-АДРЕС:"**
   
   ![Скриншот](2025-11-02_22-49-51.png)

3. **Добавьте следующие URL:**

   **Для production:**
   ```
   https://components.tools/calculator/oauth/callback
   https://api.components.tools/api/oauth/callback
   ```
   
   **Для разработки (если нужно):**
   ```
   http://localhost:3000/login
   http://localhost:8000/api/oauth/callback
   ```

4. **Нажмите "Редактировать раздел"** или аналогичную кнопку сохранения

---

## 📋 ТЕКУЩИЕ УЧЕТНЫЕ ДАННЫЕ

Из вашего скриншота видны следующие данные:

### **Реквизиты для входа:**

```
ИДЕНТИФИКАТОР КЛИЕНТА:
56c235c4-6100-446d-9246-b9f7e0a986cd

СЕКРЕТ КЛИЕНТА:
yF2n6Ww_Ato9rKXxWdwVKULTZYk3ECQHHz34
```

### **Типы грантов:**
- ✅ Код авторизации
- ✅ Учетные данные клиента

### **Настраиваемый:**
- ✅ Пароль владельца ресурса

---

## 🔄 КАК ЭТО РАБОТАЕТ

### **1. Client Credentials Flow (используется в API):**

```
API → Nexar Token URL → Получение Access Token → GraphQL запросы
```

**Код в api.php уже настроен:**
```php
define('NEXAR_CLIENT_ID', '56c235c4-6100-446d-9246-b9f7e0a986cd');
define('NEXAR_CLIENT_SECRET', 'yF2n6Ww_Ato9rKXxWdwVKULTZYk3ECQHHz34');
define('NEXAR_TOKEN_URL', 'https://identity.nexar.com/connect/token');
define('NEXAR_GRAPHQL_URL', 'https://api.nexar.com/graphql');
```

### **2. Authorization Code Flow (для OAuth авторизации):**

Если в будущем понадобится OAuth авторизация пользователей:

```
1. Redirect → https://identity.nexar.com/connect/authorize
2. User logs in
3. Callback → https://components.tools/calculator/oauth/callback
4. Exchange code for token
```

---

## ✅ ПРОВЕРКА НАСТРОЙКИ

### **Тест через curl:**

```bash
# Получаем токен
curl -X POST https://identity.nexar.com/connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=56c235c4-6100-446d-9246-b9f7e0a986cd" \
  -d "client_secret=yF2n6Ww_Ato9rKXxWdwVKULTZYk3ECQHHz34"
```

Должен вернуть:
```json
{
  "access_token": "eyJhbGci...",
  "expires_in": 3600,
  "token_type": "Bearer"
}
```

### **Тест GraphQL запроса:**

```bash
# Используем полученный токен
TOKEN="ваш_access_token"

curl -X POST https://api.nexar.com/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query { supSearchMpn(q: \"ATmega328P\", limit: 1) { results { part { mpn } } } }"
  }'
```

---

## 🚨 ВАЖНЫЕ ЗАМЕЧАНИЯ

### **1. Безопасность:**
- ❌ **НЕ ПУБЛИКУЙТЕ** Client Secret в публичных репозиториях
- ✅ Храните credentials в переменных окружения или защищенных конфигах
- ✅ Используйте HTTPS для production

### **2. Rate Limits:**
Nexar имеет лимиты на количество запросов:
- Обычно: **60 запросов/минуту**
- Кэшируйте результаты в БД
- Используйте таблицу `api_cache` для хранения ответов

### **3. Токены:**
- Access Token действует **1 час**
- Система автоматически обновляет токены
- Кэш токенов в памяти для оптимизации

---

## 📝 ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ В API

### **Поиск детали:**

```php
$nexar = new NexarAPI();
$result = $nexar->searchPart('ATmega328P');

if ($result['found']) {
    echo "Производитель: " . $result['manufacturer'];
    echo "Цена: " . $result['minPrice'] . " " . $result['currency'];
    echo "Наличие: " . $result['availability'];
}
```

### **В калькуляторе:**

```javascript
// JavaScript в браузере
fetch('/api/octopart/search?mpn=ATmega328P')
  .then(response => response.json())
  .then(data => {
    if (data.success && data.data.found) {
      console.log('Найдено:', data.data);
      // Автоматически подставляем цену
      document.getElementById('purchasePrice').value = data.data.minPrice;
    }
  });
```

---

## 🔧 TROUBLESHOOTING

### **Ошибка: "invalid_client"**
- Проверьте Client ID и Secret
- Убедитесь что нет лишних пробелов

### **Ошибка: "invalid_redirect_uri"**
- URL в коде должен точно совпадать с URL в Nexar Portal
- Проверьте протокол (http vs https)

### **Ошибка: "access_denied"**
- Проверьте что приложение активно в Nexar Portal
- Проверьте что типы грантов включены

---

## 📚 ПОЛЕЗНЫЕ ССЫЛКИ

- **Nexar Documentation:** https://support.nexar.com/support/solutions/101000253221/
- **Nexar GraphQL Explorer:** https://api.nexar.com/graphql (требует авторизации)
- **OAuth 2.0 Spec:** https://oauth.net/2/

---

## ✅ ЧЕКЛИСТ НАСТРОЙКИ

- [ ] Добавлены Redirect URLs в Nexar Portal
- [ ] Client ID и Secret скопированы в api.php
- [ ] Тест получения токена пройден
- [ ] Тест GraphQL запроса пройден
- [ ] Поиск детали работает в калькуляторе

---

🎉 **Nexar настроен и готов к использованию!**
