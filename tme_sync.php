<?php
/**
 * Модуль синхронизации с TME.EU API
 * 
 * Функции:
 * - Автоматическое обновление цен и наличия
 * - Поиск деталей по артикулу
 * - Массовая загрузка каталога
 * - Кэширование данных
 */

class TMESync {
    private $apiKey;
    private $apiSecret;
    private $baseUrl = 'https://api.tme.eu';
    private $db;
    
    // Rate limiting
    private $requestsPerMinute = 60;
    private $lastRequestTime = 0;
    
    public function __construct($apiKey, $apiSecret, $dbConnection) {
        $this->apiKey = $apiKey;
        $this->apiSecret = $apiSecret;
        $this->db = $dbConnection;
    }
    
    /**
     * Поиск детали по артикулу в TME
     */
    public function searchPart($mpn) {
        $endpoint = '/Products/Search.json';
        
        $params = [
            'Country' => 'RU',
            'Language' => 'RU',
            'SearchPlain' => $mpn
        ];
        
        $response = $this->makeRequest($endpoint, $params);
        
        if (empty($response['ProductList'])) {
            return [
                'found' => false,
                'message' => 'Деталь не найдена в TME'
            ];
        }
        
        // Берем первый результат
        $product = $response['ProductList'][0];
        
        return [
            'found' => true,
            'tme_symbol' => $product['Symbol'],
            'manufacturer' => $product['Producer'],
            'description' => $product['Description'],
            'category' => $product['CategoryTree'][0]['Name'] ?? null,
            'photo' => $product['Photo'],
            'price_eur' => $this->convertToEur($product['PriceList'][0]['PriceValue'] ?? 0),
            'availability' => $product['Amount'] ?? 0,
            'delivery_days' => $product['DeliveryDate'] ?? 14,
            'moq' => $product['MinAmount'] ?? 1,
            'datasheet_url' => $product['DocumentUrl'] ?? null,
            'full_data' => $product
        ];
    }
    
    /**
     * Получить детальную информацию о детали
     */
    public function getProductDetails($tmeSymbol) {
        $endpoint = '/Products/GetProducts.json';
        
        $params = [
            'Country' => 'RU',
            'Language' => 'RU',
            'SymbolList' => [$tmeSymbol]
        ];
        
        $response = $this->makeRequest($endpoint, $params);
        
        if (empty($response['ProductList'])) {
            return null;
        }
        
        $product = $response['ProductList'][0];
        
        // Получаем параметры
        $paramsEndpoint = '/Products/GetParameters.json';
        $paramsData = $this->makeRequest($paramsEndpoint, [
            'Country' => 'RU',
            'Language' => 'RU',
            'SymbolList' => [$tmeSymbol]
        ]);
        
        $parameters = [];
        if (!empty($paramsData['ProductList'][0]['ParameterList'])) {
            foreach ($paramsData['ProductList'][0]['ParameterList'] as $param) {
                $parameters[$param['ParameterName']] = $param['ParameterValue'];
            }
        }
        
        return [
            'tme_symbol' => $tmeSymbol,
            'mpn' => $product['OriginalSymbol'],
            'manufacturer' => $product['Producer'],
            'description' => $product['Description'],
            'category' => $product['CategoryTree'][0]['Name'] ?? null,
            'subcategory' => $product['CategoryTree'][1]['Name'] ?? null,
            'photo' => $product['Photo'],
            'price_eur' => $this->convertToEur($product['PriceList'][0]['PriceValue'] ?? 0),
            'availability' => $product['Amount'] ?? 0,
            'delivery_days' => $product['DeliveryDate'] ?? 14,
            'moq' => $product['MinAmount'] ?? 1,
            'datasheet_url' => $product['DocumentUrl'] ?? null,
            'parameters' => $parameters,
            'full_data' => $product
        ];
    }
    
    /**
     * Синхронизировать деталь в БД
     */
    public function syncPartToDatabase($mpn) {
        try {
            // Ищем деталь
            $tmeData = $this->searchPart($mpn);
            
            if (!$tmeData['found']) {
                return [
                    'success' => false,
                    'message' => 'Деталь не найдена в TME'
                ];
            }
            
            // Получаем детальную информацию
            $details = $this->getProductDetails($tmeData['tme_symbol']);
            
            // Ищем или создаем производителя
            $manufacturerId = $this->getOrCreateManufacturer($details['manufacturer']);
            
            // Определяем категорию
            $category = $this->mapCategory($details['category']);
            
            // Проверяем, есть ли деталь в БД
            $stmt = $this->db->prepare("
                SELECT id FROM parts 
                WHERE mpn = ? AND manufacturer_id = ?
                LIMIT 1
            ");
            $stmt->execute([$mpn, $manufacturerId]);
            $existing = $stmt->fetch();
            
            if ($existing) {
                // Обновляем
                $stmt = $this->db->prepare("
                    UPDATE parts SET
                        description = ?,
                        category = ?,
                        subcategory = ?,
                        specifications = ?::jsonb,
                        tme_symbol = ?,
                        tme_price_eur = ?,
                        tme_availability = ?,
                        tme_delivery_days = ?,
                        tme_moq = ?,
                        tme_data = ?::jsonb,
                        tme_last_sync = CURRENT_TIMESTAMP,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                ");
                
                $stmt->execute([
                    $details['description'],
                    $category,
                    $details['subcategory'],
                    json_encode($details['parameters']),
                    $details['tme_symbol'],
                    $details['price_eur'],
                    $details['availability'],
                    $details['delivery_days'],
                    $details['moq'],
                    json_encode($details['full_data']),
                    $existing['id']
                ]);
                
                $partId = $existing['id'];
                $action = 'updated';
            } else {
                // Вставляем новую
                $stmt = $this->db->prepare("
                    INSERT INTO parts (
                        mpn, manufacturer_id, description, category, subcategory,
                        specifications, tme_symbol, tme_price_eur, tme_availability,
                        tme_delivery_days, tme_moq, tme_data, tme_last_sync
                    ) VALUES (?, ?, ?, ?, ?, ?::jsonb, ?, ?, ?, ?, ?, ?::jsonb, CURRENT_TIMESTAMP)
                    RETURNING id
                ");
                
                $stmt->execute([
                    $mpn,
                    $manufacturerId,
                    $details['description'],
                    $category,
                    $details['subcategory'],
                    json_encode($details['parameters']),
                    $details['tme_symbol'],
                    $details['price_eur'],
                    $details['availability'],
                    $details['delivery_days'],
                    $details['moq'],
                    json_encode($details['full_data'])
                ]);
                
                $result = $stmt->fetch();
                $partId = $result['id'];
                $action = 'created';
            }
            
            // Сохраняем в историю цен
            $this->savePriceHistory($partId, $mpn, 'tme', $details['price_eur'], $details['availability'], $details['delivery_days']);
            
            return [
                'success' => true,
                'action' => $action,
                'part_id' => $partId,
                'data' => $details
            ];
            
        } catch (Exception $e) {
            return [
                'success' => false,
                'error' => $e->getMessage()
            ];
        }
    }
    
    /**
     * Массовая синхронизация из очереди
     */
    public function processSyncQueue($batchSize = 50) {
        $stmt = $this->db->prepare("
            SELECT * FROM tme_sync_queue
            WHERE status = 'pending' 
            AND attempts < max_attempts
            ORDER BY priority DESC, scheduled_at ASC
            LIMIT ?
        ");
        $stmt->execute([$batchSize]);
        $queue = $stmt->fetchAll();
        
        $results = [
            'processed' => 0,
            'success' => 0,
            'failed' => 0,
            'errors' => []
        ];
        
        foreach ($queue as $item) {
            // Обновляем статус на processing
            $this->db->prepare("
                UPDATE tme_sync_queue 
                SET status = 'processing', started_at = CURRENT_TIMESTAMP, attempts = attempts + 1
                WHERE id = ?
            ")->execute([$item['id']]);
            
            // Синхронизируем
            $result = $this->syncPartToDatabase($item['mpn']);
            
            $results['processed']++;
            
            if ($result['success']) {
                // Успех
                $this->db->prepare("
                    UPDATE tme_sync_queue 
                    SET status = 'completed', completed_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                ")->execute([$item['id']]);
                
                $results['success']++;
            } else {
                // Ошибка
                $this->db->prepare("
                    UPDATE tme_sync_queue 
                    SET status = 'failed', error_message = ?
                    WHERE id = ?
                ")->execute([$result['error'] ?? $result['message'], $item['id']]);
                
                $results['failed']++;
                $results['errors'][] = [
                    'mpn' => $item['mpn'],
                    'error' => $result['error'] ?? $result['message']
                ];
            }
            
            // Rate limiting
            $this->waitForRateLimit();
        }
        
        return $results;
    }
    
    /**
     * Добавить деталь в очередь синхронизации
     */
    public function addToSyncQueue($mpn, $tmeSymbol = null, $priority = 0) {
        $stmt = $this->db->prepare("
            INSERT INTO tme_sync_queue (mpn, tme_symbol, priority, scheduled_at)
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT (mpn) DO UPDATE SET
                priority = GREATEST(tme_sync_queue.priority, EXCLUDED.priority),
                scheduled_at = CURRENT_TIMESTAMP,
                status = 'pending'
        ");
        
        return $stmt->execute([$mpn, $tmeSymbol, $priority]);
    }
    
    /**
     * Получить или создать производителя
     */
    private function getOrCreateManufacturer($name) {
        $stmt = $this->db->prepare("SELECT id FROM manufacturers WHERE name = ?");
        $stmt->execute([$name]);
        $result = $stmt->fetch();
        
        if ($result) {
            return $result['id'];
        }
        
        // Создаем нового
        $stmt = $this->db->prepare("
            INSERT INTO manufacturers (name) VALUES (?)
            RETURNING id
        ");
        $stmt->execute([$name]);
        $result = $stmt->fetch();
        
        return $result['id'];
    }
    
    /**
     * Сохранить историю цен
     */
    private function savePriceHistory($partId, $mpn, $source, $price, $availability, $deliveryDays) {
        $stmt = $this->db->prepare("
            INSERT INTO price_history (part_id, mpn, source, price_eur, availability, delivery_days)
            VALUES (?, ?, ?, ?, ?, ?)
        ");
        
        return $stmt->execute([$partId, $mpn, $source, $price, $availability, $deliveryDays]);
    }
    
    /**
     * Маппинг категорий TME в наши категории
     */
    private function mapCategory($tmeCategory) {
        $mapping = [
            'Semiconductors' => 'electronics',
            'Passive components' => 'electronics',
            'Electromechanics' => 'connectors',
            'Connectors' => 'connectors',
            'Power supplies' => 'electronics',
            'Cables' => 'connectors',
            'Mechanics' => 'mechanical',
            'Tools' => 'mechanical'
        ];
        
        foreach ($mapping as $pattern => $category) {
            if (stripos($tmeCategory, $pattern) !== false) {
                return $category;
            }
        }
        
        return 'other';
    }
    
    /**
     * Конвертировать цену TME в EUR
     */
    private function convertToEur($price) {
        // TME возвращает цены в разных валютах
        // Здесь нужна логика конвертации
        return $price; // Упрощенно
    }
    
    /**
     * Выполнить HTTP запрос к TME API
     */
    private function makeRequest($endpoint, $params = []) {
        $this->waitForRateLimit();
        
        $url = $this->baseUrl . $endpoint;
        
        // Подготовка аутентификации
        $token = base64_encode($this->apiKey . ':' . $this->apiSecret);
        
        $ch = curl_init();
        
        if (!empty($params)) {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($params));
        }
        
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Authorization: Bearer ' . $token
            ]
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode !== 200) {
            throw new Exception("TME API error: HTTP $httpCode - $response");
        }
        
        $data = json_decode($response, true);
        
        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new Exception('TME API returned invalid JSON');
        }
        
        return $data;
    }
    
    /**
     * Rate limiting
     */
    private function waitForRateLimit() {
        $minInterval = 60 / $this->requestsPerMinute;
        $elapsed = microtime(true) - $this->lastRequestTime;
        
        if ($elapsed < $minInterval) {
            usleep(($minInterval - $elapsed) * 1000000);
        }
        
        $this->lastRequestTime = microtime(true);
    }
}

/**
 * CLI скрипт для запуска синхронизации
 * 
 * Использование:
 * php tme_sync.php --mode=queue --batch=50
 * php tme_sync.php --mode=search --mpn=ATmega328P
 */

if (php_sapi_name() === 'cli') {
    // Настройки
    $options = getopt('', ['mode:', 'mpn:', 'batch:']);
    
    // Подключение к БД
    $db = new PDO(
        "pgsql:host=localhost;dbname=calculator_db",
        "calculator_user",
        "your_password"
    );
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // TME API ключи
    $tmeSync = new TMESync(
        'YOUR_TME_API_KEY',
        'YOUR_TME_API_SECRET',
        $db
    );
    
    $mode = $options['mode'] ?? 'queue';
    
    switch ($mode) {
        case 'queue':
            echo "🔄 Обработка очереди синхронизации...\n";
            $batchSize = $options['batch'] ?? 50;
            $result = $tmeSync->processSyncQueue($batchSize);
            echo "✅ Обработано: {$result['processed']}\n";
            echo "✅ Успешно: {$result['success']}\n";
            echo "❌ Ошибок: {$result['failed']}\n";
            if (!empty($result['errors'])) {
                echo "\nОшибки:\n";
                foreach ($result['errors'] as $error) {
                    echo "  - {$error['mpn']}: {$error['error']}\n";
                }
            }
            break;
            
        case 'search':
            $mpn = $options['mpn'] ?? null;
            if (!$mpn) {
                die("❌ Укажите --mpn=АРТИКУЛ\n");
            }
            echo "🔍 Поиск детали: $mpn\n";
            $result = $tmeSync->syncPartToDatabase($mpn);
            if ($result['success']) {
                echo "✅ Деталь синхронизирована (ID: {$result['part_id']})\n";
                print_r($result['data']);
            } else {
                echo "❌ Ошибка: {$result['error']}\n";
            }
            break;
            
        default:
            echo "❌ Неизвестный режим: $mode\n";
            echo "Доступные режимы:\n";
            echo "  --mode=queue     Обработать очередь\n";
            echo "  --mode=search    Найти деталь по MPN\n";
            break;
    }
}
