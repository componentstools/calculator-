-- =====================================================
-- POSTGRESQL СХЕМА ДЛЯ КАЛЬКУЛЯТОРОВ И КАТАЛОГА ДЕТАЛЕЙ
-- Оптимизирована для 1+ млн артикулов
-- Интеграция: TME API, Nexar API, Битрикс, OpenCart
-- =====================================================

-- Включаем расширения
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- Для быстрого поиска
CREATE EXTENSION IF NOT EXISTS "btree_gin"; -- Для составных индексов

-- =====================================================
-- 1. ТАБЛИЦА ПРОИЗВОДИТЕЛЕЙ
-- =====================================================
CREATE TABLE manufacturers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    name_normalized VARCHAR(255), -- Нормализованное имя для поиска
    website VARCHAR(500),
    logo_url VARCHAR(500),
    
    -- Интеграция
    tme_id VARCHAR(100),
    nexar_id VARCHAR(100),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_manufacturers_name ON manufacturers USING gin(name_normalized gin_trgm_ops);
CREATE INDEX idx_manufacturers_tme ON manufacturers(tme_id);

-- =====================================================
-- 2. ГЛАВНАЯ ТАБЛИЦА ДЕТАЛЕЙ (ПАРТИЦИОНИРОВАННАЯ)
-- =====================================================
CREATE TABLE parts (
    id BIGSERIAL,
    
    -- Основные данные
    mpn VARCHAR(255) NOT NULL, -- Manufacturer Part Number
    manufacturer_id INT REFERENCES manufacturers(id),
    
    -- Описание
    description TEXT,
    category VARCHAR(255),
    subcategory VARCHAR(255),
    
    -- Технические характеристики (JSONB для гибкости)
    specifications JSONB,
    
    -- Данные от TME
    tme_symbol VARCHAR(255),
    tme_price_eur DECIMAL(10,4),
    tme_availability INT DEFAULT 0,
    tme_delivery_days INT,
    tme_moq INT, -- Minimum Order Quantity
    tme_data JSONB, -- Полный ответ от TME API
    tme_last_sync TIMESTAMP,
    
    -- Данные от Nexar/Octopart
    nexar_data JSONB,
    nexar_min_price DECIMAL(10,4),
    nexar_availability INT DEFAULT 0,
    nexar_last_sync TIMESTAMP,
    
    -- Наши данные
    our_price_rub DECIMAL(10,2),
    our_stock INT DEFAULT 0,
    our_delivery_days INT,
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Статистика
    view_count INT DEFAULT 0,
    calculation_count INT DEFAULT 0,
    order_count INT DEFAULT 0,
    last_viewed TIMESTAMP,
    
    -- Метаданные
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (id, category)
) PARTITION BY LIST (category);

-- Создаем партиции по категориям (примеры)
CREATE TABLE parts_electronics PARTITION OF parts FOR VALUES IN ('electronics', 'semiconductors', 'passive');
CREATE TABLE parts_connectors PARTITION OF parts FOR VALUES IN ('connectors', 'cables');
CREATE TABLE parts_mechanical PARTITION OF parts FOR VALUES IN ('mechanical', 'hardware');
CREATE TABLE parts_other PARTITION OF parts DEFAULT;

-- Индексы для быстрого поиска
CREATE INDEX idx_parts_mpn ON parts(mpn);
CREATE INDEX idx_parts_mpn_trgm ON parts USING gin(mpn gin_trgm_ops);
CREATE INDEX idx_parts_manufacturer ON parts(manufacturer_id);
CREATE INDEX idx_parts_tme_symbol ON parts(tme_symbol);
CREATE INDEX idx_parts_active ON parts(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_parts_tme_price ON parts(tme_price_eur) WHERE tme_price_eur IS NOT NULL;
CREATE INDEX idx_parts_specifications ON parts USING gin(specifications);
CREATE INDEX idx_parts_updated ON parts(updated_at);

-- Full-text search индекс
CREATE INDEX idx_parts_fulltext ON parts USING gin(
    to_tsvector('english', coalesce(mpn, '') || ' ' || coalesce(description, ''))
);

-- =====================================================
-- 3. ТАБЛИЦА ПРОФИЛЕЙ РАСХОДОВ
-- =====================================================
CREATE TABLE expense_profiles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    
    -- Логистика
    delivery_under_2kg DECIMAL(10,2) DEFAULT 35.00,
    delivery_rf DECIMAL(10,2) DEFAULT 0.00,
    
    -- Переводы
    transfer_method VARCHAR(20) DEFAULT 'cash', -- 'cash' или 'crypto'
    eur_rub_rate DECIMAL(10,4) DEFAULT 105.00,
    commission_ip DECIMAL(5,2) DEFAULT 10.00,
    eur_usdt_rate DECIMAL(10,6) DEFAULT 1.19,
    usdt_rub_rate DECIMAL(10,2) DEFAULT 83.43,
    commission_crypto DECIMAL(5,2) DEFAULT 2.00,
    commission_agent DECIMAL(10,2) DEFAULT 19908.72,
    
    -- Документы
    document_cost_percent DECIMAL(5,2) DEFAULT 10.00,
    target_official_profit DECIMAL(5,2) DEFAULT 3.00,
    
    -- Налоги
    vat_percent DECIMAL(5,2) DEFAULT 20.00,
    profit_tax_percent DECIMAL(5,2) DEFAULT 20.00,
    
    -- Конкуренты
    competitor_price_min DECIMAL(10,2) DEFAULT 0.00,
    competitor_price_max DECIMAL(10,2) DEFAULT 0.00,
    
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INT
);

CREATE INDEX idx_expense_profiles_default ON expense_profiles(is_default);

-- =====================================================
-- 4. ТАБЛИЦА ПОЛЬЗОВАТЕЛЕЙ
-- =====================================================
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    
    -- Интеграция с Битрикс
    bitrix_user_id INT UNIQUE,
    
    -- Авторизация
    username VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    
    -- Роль
    role VARCHAR(20) DEFAULT 'manager', -- 'admin' или 'manager'
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Настройки менеджера
    default_profit_percent DECIMAL(5,2) DEFAULT 25.00,
    
    -- Статистика
    last_login TIMESTAMP,
    login_count INT DEFAULT 0,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_bitrix ON users(bitrix_user_id);
CREATE INDEX idx_users_role ON users(role);

-- =====================================================
-- 5. ТАБЛИЦА РАСЧЕТОВ
-- =====================================================
CREATE TABLE calculations (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID DEFAULT uuid_generate_v4(),
    
    -- Связи
    profile_id INT REFERENCES expense_profiles(id),
    user_id INT REFERENCES users(id),
    part_id BIGINT, -- Ссылка на parts, но не FK из-за партиций
    
    -- Входные данные
    article_number VARCHAR(255),
    purchase_price_eur DECIMAL(10,2) NOT NULL,
    delivery_invoice_eur DECIMAL(10,2) DEFAULT 0.00,
    
    -- Данные детали
    manufacturer_name VARCHAR(255),
    part_description TEXT,
    tme_availability INT,
    tme_delivery_days INT,
    nexar_availability INT,
    nexar_delivery_days INT,
    
    -- Расчеты
    desired_profit_rub DECIMAL(10,2),
    desired_profit_percent DECIMAL(5,2),
    calculated_price_with_vat DECIMAL(10,2) NOT NULL,
    calculated_price_without_vat DECIMAL(10,2) NOT NULL,
    
    -- Анализ
    breakeven_point DECIMAL(10,2),
    margin_percent DECIMAL(5,2),
    competitor_avg_price DECIMAL(10,2),
    price_difference DECIMAL(10,2),
    
    -- Детализация расходов (JSONB для гибкости)
    expenses JSONB,
    
    -- Тип и статус
    calculation_type VARCHAR(20) DEFAULT 'manager', -- 'admin' или 'manager'
    status VARCHAR(20) DEFAULT 'draft', -- 'draft', 'calculated', 'approved', 'rejected'
    notes TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_calculations_user ON calculations(user_id);
CREATE INDEX idx_calculations_article ON calculations(article_number);
CREATE INDEX idx_calculations_created ON calculations(created_at DESC);
CREATE INDEX idx_calculations_status ON calculations(status);
CREATE INDEX idx_calculations_uuid ON calculations(uuid);

-- =====================================================
-- 6. ТАБЛИЦА СИНХРОНИЗАЦИИ С TME
-- =====================================================
CREATE TABLE tme_sync_queue (
    id BIGSERIAL PRIMARY KEY,
    
    part_id BIGINT,
    mpn VARCHAR(255),
    tme_symbol VARCHAR(255),
    
    priority INT DEFAULT 0, -- Чем выше, тем важнее
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'
    
    attempts INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    
    error_message TEXT,
    
    scheduled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tme_sync_status ON tme_sync_queue(status, priority DESC);
CREATE INDEX idx_tme_sync_scheduled ON tme_sync_queue(scheduled_at);

-- =====================================================
-- 7. ТАБЛИЦА ИСТОРИИ ЦЕН (для аналитики)
-- =====================================================
CREATE TABLE price_history (
    id BIGSERIAL PRIMARY KEY,
    
    part_id BIGINT,
    mpn VARCHAR(255),
    
    source VARCHAR(50), -- 'tme', 'nexar', 'manual'
    
    price_eur DECIMAL(10,4),
    availability INT,
    delivery_days INT,
    
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (recorded_at);

-- Партиции по месяцам (создаются автоматически)
CREATE TABLE price_history_2025_01 PARTITION OF price_history 
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE price_history_2025_02 PARTITION OF price_history 
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
-- И так далее...

CREATE INDEX idx_price_history_part ON price_history(part_id, recorded_at DESC);
CREATE INDEX idx_price_history_mpn ON price_history(mpn, recorded_at DESC);

-- =====================================================
-- 8. ТАБЛИЦА КЭША API
-- =====================================================
CREATE TABLE api_cache (
    id SERIAL PRIMARY KEY,
    
    cache_key VARCHAR(500) NOT NULL UNIQUE,
    cache_type VARCHAR(50), -- 'tme', 'nexar', 'calculation'
    
    data JSONB NOT NULL,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    
    hit_count INT DEFAULT 0
);

CREATE INDEX idx_api_cache_key ON api_cache(cache_key);
CREATE INDEX idx_api_cache_expires ON api_cache(expires_at);

-- =====================================================
-- 9. ТАБЛИЦА ЛОГОВ
-- =====================================================
CREATE TABLE api_logs (
    id BIGSERIAL PRIMARY KEY,
    
    endpoint VARCHAR(255),
    method VARCHAR(10),
    
    user_id INT,
    ip_address INET,
    
    request_data JSONB,
    response_data JSONB,
    
    status_code INT,
    execution_time DECIMAL(8,3),
    
    error_message TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (created_at);

-- Партиции по дням
CREATE TABLE api_logs_2025_11 PARTITION OF api_logs 
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE INDEX idx_api_logs_user ON api_logs(user_id, created_at DESC);
CREATE INDEX idx_api_logs_endpoint ON api_logs(endpoint, created_at DESC);

-- =====================================================
-- 10. ТАБЛИЦА ИНТЕГРАЦИИ С БИТРИКС
-- =====================================================
CREATE TABLE bitrix_sync (
    id SERIAL PRIMARY KEY,
    
    part_id BIGINT,
    bitrix_product_id INT UNIQUE,
    
    sync_status VARCHAR(20) DEFAULT 'pending',
    last_sync TIMESTAMP,
    sync_errors TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_bitrix_sync_part ON bitrix_sync(part_id);
CREATE INDEX idx_bitrix_sync_product ON bitrix_sync(bitrix_product_id);
CREATE INDEX idx_bitrix_sync_status ON bitrix_sync(sync_status);

-- =====================================================
-- 11. ТАБЛИЦА ИНТЕГРАЦИИ С OPENCART
-- =====================================================
CREATE TABLE opencart_sync (
    id SERIAL PRIMARY KEY,
    
    part_id BIGINT,
    opencart_product_id INT UNIQUE,
    
    sync_status VARCHAR(20) DEFAULT 'pending',
    last_sync TIMESTAMP,
    sync_errors TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_opencart_sync_part ON opencart_sync(part_id);
CREATE INDEX idx_opencart_sync_product ON opencart_sync(opencart_product_id);

-- =====================================================
-- НАЧАЛЬНЫЕ ДАННЫЕ
-- =====================================================

-- Профиль по умолчанию
INSERT INTO expense_profiles (
    name, is_default
) VALUES (
    'Профиль по умолчанию', TRUE
);

-- Администратор (пароль: admin123)
INSERT INTO users (
    username, password_hash, email, role, default_profit_percent
) VALUES (
    'admin',
    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
    'admin@components.tools',
    'admin',
    25.00
);

-- =====================================================
-- ПРЕДСТАВЛЕНИЯ (VIEWS)
-- =====================================================

-- Полная информация о деталях
CREATE VIEW v_parts_full AS
SELECT 
    p.*,
    m.name as manufacturer_name,
    m.website as manufacturer_website,
    CASE 
        WHEN p.tme_price_eur IS NOT NULL THEN p.tme_price_eur
        WHEN p.nexar_min_price IS NOT NULL THEN p.nexar_min_price
        ELSE NULL
    END as best_price_eur,
    COALESCE(p.tme_availability, 0) + COALESCE(p.nexar_availability, 0) as total_availability
FROM parts p
LEFT JOIN manufacturers m ON p.manufacturer_id = m.id;

-- Статистика менеджеров
CREATE VIEW v_manager_stats AS
SELECT 
    u.id,
    u.username,
    u.email,
    COUNT(c.id) as total_calculations,
    AVG(c.calculated_price_with_vat) as avg_price,
    SUM(c.desired_profit_rub) as total_profit,
    MAX(c.created_at) as last_calculation
FROM users u
LEFT JOIN calculations c ON u.id = c.user_id
WHERE u.role = 'manager'
GROUP BY u.id, u.username, u.email;

-- Топ деталей
CREATE VIEW v_top_parts AS
SELECT 
    p.mpn,
    m.name as manufacturer,
    p.description,
    p.view_count,
    p.calculation_count,
    p.order_count,
    p.tme_price_eur,
    p.tme_availability
FROM parts p
LEFT JOIN manufacturers m ON p.manufacturer_id = m.id
WHERE p.is_active = TRUE
ORDER BY p.calculation_count DESC, p.view_count DESC
LIMIT 100;

-- =====================================================
-- ФУНКЦИИ
-- =====================================================

-- Функция для автообновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггеры для всех таблиц
CREATE TRIGGER update_manufacturers_updated_at BEFORE UPDATE ON manufacturers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_parts_updated_at BEFORE UPDATE ON parts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_expense_profiles_updated_at BEFORE UPDATE ON expense_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Функция для нормализации имен производителей
CREATE OR REPLACE FUNCTION normalize_manufacturer_name()
RETURNS TRIGGER AS $$
BEGIN
    NEW.name_normalized = lower(regexp_replace(NEW.name, '[^a-zA-Z0-9]', '', 'g'));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER normalize_manufacturer BEFORE INSERT OR UPDATE ON manufacturers
    FOR EACH ROW EXECUTE FUNCTION normalize_manufacturer_name();

-- Функция для очистки старых логов
CREATE OR REPLACE FUNCTION cleanup_old_logs(days_to_keep INT DEFAULT 30)
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    DELETE FROM api_logs WHERE created_at < CURRENT_TIMESTAMP - (days_to_keep || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Функция для очистки истекшего кэша
CREATE OR REPLACE FUNCTION cleanup_expired_cache()
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    DELETE FROM api_cache WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- КОММЕНТАРИИ
-- =====================================================

COMMENT ON TABLE parts IS 'Главная таблица деталей, партиционированная по категориям для оптимизации работы с миллионами записей';
COMMENT ON TABLE tme_sync_queue IS 'Очередь для синхронизации цен и наличия с TME API';
COMMENT ON TABLE price_history IS 'История изменения цен для аналитики и прогнозирования';
COMMENT ON TABLE bitrix_sync IS 'Синхронизация с каталогом Битрикс';
COMMENT ON TABLE opencart_sync IS 'Синхронизация с каталогом OpenCart';

-- =====================================================
-- ЗАДАНИЯ ДЛЯ АВТОМАТИЗАЦИИ (pg_cron или crontab)
-- =====================================================

-- Очистка старых логов каждый день в 3:00
-- SELECT cron.schedule('cleanup-logs', '0 3 * * *', 'SELECT cleanup_old_logs(30)');

-- Очистка кэша каждый час
-- SELECT cron.schedule('cleanup-cache', '0 * * * *', 'SELECT cleanup_expired_cache()');

-- =====================================================
-- ФИНАЛ
-- =====================================================

-- Анализ и оптимизация
VACUUM ANALYZE;

-- Вывод статистики
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
