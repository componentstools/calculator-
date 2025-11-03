-- =====================================================
-- СХЕМА БД ДЛЯ КАЛЬКУЛЯТОРОВ ИМПОРТА
-- Совместима с Битрикс (используем префикс b_)
-- =====================================================

-- 1. ТАБЛИЦА ПРОФИЛЕЙ РАСХОДОВ (настройки администратора)
CREATE TABLE IF NOT EXISTS b_calculator_expense_profiles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL COMMENT 'Название профиля (например: Электроника, Автозапчасти)',
    
    -- Логистика
    delivery_under_2kg DECIMAL(10,2) DEFAULT 35.00 COMMENT 'Доставка до 2кг (EUR)',
    delivery_rf DECIMAL(10,2) DEFAULT 0.00 COMMENT 'Доставка по России (RUB)',
    
    -- Переводы
    transfer_method ENUM('cash', 'crypto') DEFAULT 'cash' COMMENT 'Способ перевода',
    eur_rub_rate DECIMAL(10,4) DEFAULT 105.00 COMMENT 'Курс EUR/RUB для наличных',
    commission_ip DECIMAL(5,2) DEFAULT 10.00 COMMENT 'Комиссия ИП (%)',
    eur_usdt_rate DECIMAL(10,6) DEFAULT 1.19 COMMENT 'Курс EUR/USDT',
    usdt_rub_rate DECIMAL(10,2) DEFAULT 83.43 COMMENT 'Курс USDT/RUB',
    commission_crypto DECIMAL(5,2) DEFAULT 2.00 COMMENT 'Комиссия крипты (%)',
    commission_agent DECIMAL(10,2) DEFAULT 19908.72 COMMENT 'Комиссия агента (RUB)',
    
    -- Документы
    document_cost_percent DECIMAL(5,2) DEFAULT 10.00 COMMENT 'Стоимость покупки документов (%)',
    target_official_profit DECIMAL(5,2) DEFAULT 3.00 COMMENT 'Целевая официальная прибыль (%)',
    
    -- Налоги
    vat_percent DECIMAL(5,2) DEFAULT 20.00 COMMENT 'НДС (%)',
    profit_tax_percent DECIMAL(5,2) DEFAULT 20.00 COMMENT 'Налог на прибыль (%)',
    
    -- Конкуренты (диапазон)
    competitor_price_min DECIMAL(10,2) DEFAULT 0.00 COMMENT 'Мин. цена конкурентов (RUB)',
    competitor_price_max DECIMAL(10,2) DEFAULT 0.00 COMMENT 'Макс. цена конкурентов (RUB)',
    
    -- Служебные поля
    is_default BOOLEAN DEFAULT FALSE COMMENT 'Профиль по умолчанию',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by INT COMMENT 'ID пользователя Битрикс',
    
    INDEX idx_default (is_default),
    INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Профили расходов для расчетов';

-- 2. ТАБЛИЦА РАСЧЕТОВ (история всех расчетов)
CREATE TABLE IF NOT EXISTS b_calculator_calculations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    
    -- Связи
    profile_id INT NOT NULL COMMENT 'ID профиля расходов',
    user_id INT COMMENT 'ID менеджера (из Битрикс)',
    
    -- Входные данные
    article_number VARCHAR(255) COMMENT 'Артикул товара',
    purchase_price_eur DECIMAL(10,2) NOT NULL COMMENT 'Цена закупки (EUR)',
    delivery_invoice_eur DECIMAL(10,2) DEFAULT 0.00 COMMENT 'Доставка по инвойсу (EUR)',
    
    -- Данные из Octopart
    octopart_manufacturer VARCHAR(255) COMMENT 'Производитель',
    octopart_part_name VARCHAR(500) COMMENT 'Название детали',
    octopart_availability INT COMMENT 'Наличие',
    octopart_delivery_days INT COMMENT 'Срок поставки (дней)',
    octopart_min_price DECIMAL(10,2) COMMENT 'Мин. цена с Octopart',
    octopart_data_json TEXT COMMENT 'Полный JSON ответ от Octopart',
    
    -- Расчеты (результаты)
    desired_profit_rub DECIMAL(10,2) NOT NULL COMMENT 'Желаемая прибыль (RUB)',
    desired_profit_percent DECIMAL(5,2) COMMENT 'Желаемая прибыль (%)',
    calculated_price_with_vat DECIMAL(10,2) NOT NULL COMMENT 'Рассчитанная цена с НДС (RUB)',
    calculated_price_without_vat DECIMAL(10,2) NOT NULL COMMENT 'Рассчитанная цена без НДС (RUB)',
    
    -- Анализ
    breakeven_point DECIMAL(10,2) COMMENT 'Точка безубыточности (RUB)',
    margin_percent DECIMAL(5,2) COMMENT 'Маржинальность (%)',
    competitor_avg_price DECIMAL(10,2) COMMENT 'Средняя цена конкурентов (RUB)',
    price_difference DECIMAL(10,2) COMMENT 'Разница с конкурентами (RUB)',
    
    -- Расходы (детализация)
    expense_purchase DECIMAL(10,2) COMMENT 'Закупка (RUB)',
    expense_delivery_europe DECIMAL(10,2) COMMENT 'Доставка Европа (RUB)',
    expense_commission DECIMAL(10,2) COMMENT 'Комиссия перевода (RUB)',
    expense_delivery_rf DECIMAL(10,2) COMMENT 'Доставка РФ (RUB)',
    expense_documents DECIMAL(10,2) COMMENT 'Покупка документов (RUB)',
    expense_vat DECIMAL(10,2) COMMENT 'НДС (RUB)',
    expense_profit_tax DECIMAL(10,2) COMMENT 'Налог на прибыль (RUB)',
    expense_total DECIMAL(10,2) COMMENT 'Всего расходов (RUB)',
    
    -- Метаданные
    calculation_type ENUM('admin', 'manager') DEFAULT 'admin' COMMENT 'Тип расчета',
    status ENUM('draft', 'calculated', 'approved', 'rejected') DEFAULT 'draft',
    notes TEXT COMMENT 'Примечания',
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (profile_id) REFERENCES b_calculator_expense_profiles(id) ON DELETE CASCADE,
    INDEX idx_user (user_id),
    INDEX idx_article (article_number),
    INDEX idx_created (created_at),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='История всех расчетов';

-- 3. ТАБЛИЦА СЦЕНАРИЕВ ОПТИМИЗАЦИИ
CREATE TABLE IF NOT EXISTS b_calculator_optimization_scenarios (
    id INT AUTO_INCREMENT PRIMARY KEY,
    calculation_id INT NOT NULL COMMENT 'ID расчета',
    
    scenario_name VARCHAR(255) NOT NULL COMMENT 'Название сценария',
    scenario_description TEXT COMMENT 'Описание',
    potential_saving DECIMAL(10,2) NOT NULL COMMENT 'Потенциальная экономия (RUB)',
    saving_percent DECIMAL(5,2) COMMENT 'Экономия (%)',
    
    -- Детали
    parameter_changed VARCHAR(100) COMMENT 'Что меняется',
    old_value DECIMAL(10,2) COMMENT 'Старое значение',
    new_value DECIMAL(10,2) COMMENT 'Новое значение',
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (calculation_id) REFERENCES b_calculator_calculations(id) ON DELETE CASCADE,
    INDEX idx_calculation (calculation_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Сценарии оптимизации для расчетов';

-- 4. ТАБЛИЦА ПОЛЬЗОВАТЕЛЕЙ (менеджеры)
CREATE TABLE IF NOT EXISTS b_calculator_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    bitrix_user_id INT UNIQUE COMMENT 'ID пользователя из b_user Битрикс',
    
    username VARCHAR(100) NOT NULL UNIQUE COMMENT 'Логин',
    password_hash VARCHAR(255) NOT NULL COMMENT 'Хэш пароля',
    email VARCHAR(255),
    
    role ENUM('admin', 'manager') DEFAULT 'manager',
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Настройки менеджера
    default_profit_percent DECIMAL(5,2) DEFAULT 25.00 COMMENT 'Процент прибыли по умолчанию',
    
    last_login TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_bitrix_user (bitrix_user_id),
    INDEX idx_username (username),
    INDEX idx_role (role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Пользователи системы калькуляторов';

-- 5. ТАБЛИЦА КЭША OCTOPART (для оптимизации)
CREATE TABLE IF NOT EXISTS b_calculator_octopart_cache (
    id INT AUTO_INCREMENT PRIMARY KEY,
    
    article_number VARCHAR(255) NOT NULL UNIQUE COMMENT 'Артикул',
    
    -- Данные
    manufacturer VARCHAR(255),
    part_name VARCHAR(500),
    description TEXT,
    availability INT,
    delivery_days INT,
    min_price DECIMAL(10,2),
    currency VARCHAR(10),
    
    -- Полный ответ
    full_response_json TEXT COMMENT 'Полный JSON от Octopart',
    
    -- Кэш
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP COMMENT 'Когда истекает',
    cache_valid BOOLEAN DEFAULT TRUE,
    
    INDEX idx_article (article_number),
    INDEX idx_expires (expires_at),
    INDEX idx_valid (cache_valid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Кэш данных от Octopart API';

-- 6. ТАБЛИЦА ЛОГОВ API
CREATE TABLE IF NOT EXISTS b_calculator_api_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    
    endpoint VARCHAR(255) NOT NULL COMMENT 'Вызванный endpoint',
    method VARCHAR(10) COMMENT 'GET/POST/etc',
    
    user_id INT COMMENT 'ID пользователя',
    ip_address VARCHAR(45) COMMENT 'IP адрес',
    
    request_data TEXT COMMENT 'Данные запроса',
    response_data TEXT COMMENT 'Данные ответа',
    
    status_code INT COMMENT 'HTTP статус',
    execution_time DECIMAL(8,3) COMMENT 'Время выполнения (сек)',
    
    error_message TEXT COMMENT 'Сообщение об ошибке',
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_endpoint (endpoint),
    INDEX idx_user (user_id),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Логи вызовов API';

-- =====================================================
-- НАЧАЛЬНЫЕ ДАННЫЕ
-- =====================================================

-- Создаем профиль по умолчанию
INSERT INTO b_calculator_expense_profiles (
    name,
    delivery_under_2kg,
    delivery_rf,
    transfer_method,
    eur_rub_rate,
    commission_ip,
    document_cost_percent,
    target_official_profit,
    vat_percent,
    profit_tax_percent,
    is_default
) VALUES (
    'Профиль по умолчанию',
    35.00,
    0.00,
    'cash',
    105.00,
    10.00,
    10.00,
    3.00,
    20.00,
    20.00,
    TRUE
);

-- Создаем администратора по умолчанию
-- Пароль: admin123 (хэш для bcrypt)
INSERT INTO b_calculator_users (
    username,
    password_hash,
    email,
    role,
    default_profit_percent
) VALUES (
    'admin',
    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- admin123
    'admin@components.tools',
    'admin',
    25.00
);

-- =====================================================
-- ПРЕДСТАВЛЕНИЯ (VIEWS) ДЛЯ УДОБСТВА
-- =====================================================

-- Представление для быстрого доступа к расчетам с профилями
CREATE OR REPLACE VIEW v_calculations_full AS
SELECT 
    c.*,
    p.name as profile_name,
    u.username as user_name,
    u.email as user_email
FROM b_calculator_calculations c
LEFT JOIN b_calculator_expense_profiles p ON c.profile_id = p.id
LEFT JOIN b_calculator_users u ON c.user_id = u.id;

-- Представление статистики по менеджерам
CREATE OR REPLACE VIEW v_manager_statistics AS
SELECT 
    u.id,
    u.username,
    u.email,
    COUNT(c.id) as total_calculations,
    AVG(c.calculated_price_with_vat) as avg_price,
    SUM(c.desired_profit_rub) as total_profit,
    MAX(c.created_at) as last_calculation
FROM b_calculator_users u
LEFT JOIN b_calculator_calculations c ON u.id = c.user_id
WHERE u.role = 'manager'
GROUP BY u.id, u.username, u.email;

-- =====================================================
-- ХРАНИМЫЕ ПРОЦЕДУРЫ
-- =====================================================

DELIMITER //

-- Процедура получения активного профиля
CREATE PROCEDURE sp_get_active_profile()
BEGIN
    SELECT * FROM b_calculator_expense_profiles 
    WHERE is_default = TRUE 
    LIMIT 1;
END //

-- Процедура сохранения расчета
CREATE PROCEDURE sp_save_calculation(
    IN p_profile_id INT,
    IN p_user_id INT,
    IN p_article_number VARCHAR(255),
    IN p_purchase_price_eur DECIMAL(10,2),
    IN p_desired_profit_rub DECIMAL(10,2),
    IN p_calculated_price DECIMAL(10,2),
    IN p_calculation_type VARCHAR(20)
)
BEGIN
    INSERT INTO b_calculator_calculations (
        profile_id,
        user_id,
        article_number,
        purchase_price_eur,
        desired_profit_rub,
        calculated_price_with_vat,
        calculation_type,
        status
    ) VALUES (
        p_profile_id,
        p_user_id,
        p_article_number,
        p_purchase_price_eur,
        p_desired_profit_rub,
        p_calculated_price,
        p_calculation_type,
        'calculated'
    );
    
    SELECT LAST_INSERT_ID() as calculation_id;
END //

-- Процедура очистки старого кэша
CREATE PROCEDURE sp_cleanup_old_cache()
BEGIN
    DELETE FROM b_calculator_octopart_cache 
    WHERE expires_at < NOW() 
    OR cached_at < DATE_SUB(NOW(), INTERVAL 7 DAY);
    
    SELECT ROW_COUNT() as deleted_rows;
END //

DELIMITER ;

-- =====================================================
-- ИНДЕКСЫ ДЛЯ ОПТИМИЗАЦИИ
-- =====================================================

-- Составные индексы для частых запросов
CREATE INDEX idx_calc_user_date ON b_calculator_calculations(user_id, created_at);
CREATE INDEX idx_calc_article_date ON b_calculator_calculations(article_number, created_at);
CREATE INDEX idx_cache_article_valid ON b_calculator_octopart_cache(article_number, cache_valid);

-- =====================================================
-- КОММЕНТАРИИ К ТАБЛИЦАМ
-- =====================================================

ALTER TABLE b_calculator_expense_profiles 
COMMENT = 'Профили расходов и настроек для калькуляторов. Используется администратором для настройки базовых параметров расчетов.';

ALTER TABLE b_calculator_calculations 
COMMENT = 'История всех расчетов цен. Хранит входные данные, результаты и детализацию расходов.';

ALTER TABLE b_calculator_optimization_scenarios 
COMMENT = 'Сценарии оптимизации для каждого расчета. Показывает потенциальные возможности экономии.';

ALTER TABLE b_calculator_users 
COMMENT = 'Пользователи системы (администраторы и менеджеры). Интегрируется с пользователями Битрикс.';

ALTER TABLE b_calculator_octopart_cache 
COMMENT = 'Кэш данных от Octopart API для снижения количества запросов и ускорения работы.';

ALTER TABLE b_calculator_api_logs 
COMMENT = 'Логи всех обращений к API системы для мониторинга и отладки.';
