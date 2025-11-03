<?php
/**
 * TME API Массовая Синхронизация
 * 
 * Оптимизировано для загрузки 980K+ артикулов
 * - Пакетные запросы
 * - Rate limiting (1 запрос/сек)
 * - Автовосстановление при ошибках
 * - Прогресс-бар
 */

class TMEMassSync {
    private $apiToken;
    private $apiUrl = 'https://api.tme.eu';
    private $db;
    
    // Rate limiting: 1 запрос в секунду (безопасно)
    private $requestDelay = 1.0; // секунды
    private $lastRequestTime = 0;
    
    // Пакетная обработка
    private $batchSize = 20; // Артикулов в одном запросе
    
    // Статистика
    private $stats = [
        'total' => 0,
        'processed' => 0,
        'success' => 0,
        'failed' => 0,
        'skipped' => 0,
        'start_time' => 0
    ];
    
    public function __construct($apiToken, $dbConnection) {
        $this->apiToken = $apiToken;
        $this->db = $dbConnection;
    }
    
    /**
     * Массовая загрузка из файла
     */
    public function importFromFile($filename) {
        if (!file_exists($filename)) {
            throw new Exception("File not found: $filename");
        }
        
        $this->stats['start_time'] = time();
        
        // Читаем файл построчно (экономим память)
        $file = fopen($filename, 'r');
        $articles = [];
        
        while (($line = fgets($file)) !== false) {
            $article = trim($line);
            if (!empty($article)) {
                $articles[] = $article;
            }
        }
        fclose($file);
        
        $this->stats['total'] = count($articles);
        
        $this->log("📦 Загружено артикулов из файла: " . $this->stats['total']);
        $this->log("⏱️  Время начала: " . date('Y-m-d H:i:s'));
        $this->log("🔄 Начинаем синхронизацию...\n");
        
        // Обрабатываем пакетами
        $batches = array_chunk($articles, $this->batchSize);
        $totalBatches = count($batches);
        
        foreach ($batches as $batchIndex => $batch) {
            $batchNum = $batchIndex + 1;
            $this->log("📦 Пакет $batchNum/$totalBatches (" . count($batch) . " артикулов)");
            
            $this->processBatch($batch);
            
            // Прогресс
            $progress = ($batchNum / $totalBatches) * 100;
            $this->showProgress($progress);
            
            // Rate limiting между пакетами
            if ($batchNum < $totalBatches) {
                $this->waitForRateLimit();
            }
        }
        
        $this->printFinalReport();
    }
    
    /**
     * Обработка одного пакета артикулов
     */
    private function processBatch($articles) {
        try {
            // Запрашиваем данные у TME
            $tmeData = $this->searchMultipleProducts($articles);
            
            if (empty($tmeData['ProductList'])) {
                $this->log("  ⚠️  Пакет пуст");
                $this->stats['skipped'] += count($articles);
                return;
            }
            
            // Сохраняем в БД
            foreach ($tmeData['ProductList'] as $product) {
                try {
                    $this->saveProduct($product);
                    $this->stats['success']++;
                } catch (Exception $e) {
                    $this->log("  ❌ Ошибка сохранения: " . $e->getMessage());
                    $this->stats['failed']++;
                }
                $this->stats['processed']++;
            }
            
        } catch (Exception $e) {
            $this->log("  ❌ Ошибка пакета: " . $e->getMessage());
            $this->stats['failed'] += count($articles);
            $this->stats['processed'] += count($articles);
        }
    }
    
    /**
     * Поиск нескольких продуктов через TME API
     */
    private function searchMultipleProducts($symbols) {
        $endpoint = '/Products/GetProducts.json';
        
        $params = [
            'Country' => 'RU',
            'Language' => 'RU',
            'Token' => $this->apiToken,
            'SymbolList' => $symbols
        ];
        
        return $this->makeRequest($endpoint, $params);
    }
    
    /**
     * Сохранение продукта в БД
     */
    private function saveProduct($product) {
        // Получаем или создаем производителя
        $manufacturerId = $this->getOrCreateManufacturer($product['Producer'] ?? 'Unknown');
        
        // Определяем категорию
        $category = 'electronics'; // По умолчанию
        if (!empty($product['CategoryTree'][0]['Name'])) {
            $category = $this->mapCategory($product['CategoryTree'][0]['Name']);
        }
        
        // Парсим цену
        $priceEur = 0;
        if (!empty($product['PriceList'][0]['PriceValue'])) {
            $priceEur = $this->parsePrice($product['PriceList'][0]['PriceValue']);
        }
        
        // Проверяем существование
        $stmt = $this->db->prepare("
            SELECT id FROM parts 
            WHERE tme_symbol = ? 
            LIMIT 1
        ");
        $stmt->execute([$product['Symbol']]);
        $existing = $stmt->fetch();
        
        if ($existing) {
            // Обновляем
            $stmt = $this->db->prepare("
                UPDATE parts SET
                    mpn = ?,
                    manufacturer_id = ?,
                    description = ?,
                    category = ?,
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
                $product['OriginalSymbol'] ?? $product['Symbol'],
                $manufacturerId,
                $product['Description'] ?? '',
                $category,
                $priceEur,
                $product['Amount'] ?? 0,
                $this->parseDeliveryDate($product['DeliveryDate'] ?? ''),
                $product['MinAmount'] ?? 1,
                json_encode($product),
                $existing['id']
            ]);
        } else {
            // Вставляем
            $stmt = $this->db->prepare("
                INSERT INTO parts (
                    mpn, manufacturer_id, description, category,
                    tme_symbol, tme_price_eur, tme_availability,
                    tme_delivery_days, tme_moq, tme_data,
                    tme_last_sync, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb, CURRENT_TIMESTAMP, TRUE)
            ");
            
            $stmt->execute([
                $product['OriginalSymbol'] ?? $product['Symbol'],
                $manufacturerId,
                $product['Description'] ?? '',
                $category,
                $product['Symbol'],
                $priceEur,
                $product['Amount'] ?? 0,
                $this->parseDeliveryDate($product['DeliveryDate'] ?? ''),
                $product['MinAmount'] ?? 1,
                json_encode($product)
            ]);
        }
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
        
        $stmt = $this->db->prepare("
            INSERT INTO manufacturers (name) VALUES (?)
            ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
            RETURNING id
        ");
        $stmt->execute([$name]);
        $result = $stmt->fetch();
        
        return $result['id'];
    }
    
    /**
     * Маппинг категорий
     */
    private function mapCategory($tmeCategory) {
        $mapping = [
            'Semiconductors' => 'electronics',
            'Passive' => 'electronics',
            'Electromechanics' => 'connectors',
            'Connectors' => 'connectors',
            'Power' => 'electronics',
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
     * Парсинг цены
     */
    private function parsePrice($priceString) {
        // Убираем все кроме цифр и точки
        $price = preg_replace('/[^0-9.]/', '', $priceString);
        return floatval($price);
    }
    
    /**
     * Парсинг срока поставки
     */
    private function parseDeliveryDate($dateString) {
        // Извлекаем число дней
        if (preg_match('/(\d+)/', $dateString, $matches)) {
            return (int)$matches[1];
        }
        return 14; // По умолчанию 2 недели
    }
    
    /**
     * HTTP запрос к TME API
     */
    private function makeRequest($endpoint, $params = []) {
        $url = $this->apiUrl . $endpoint;
        
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => json_encode($params),
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Accept: application/json'
            ],
            CURLOPT_TIMEOUT => 30
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);
        
        if ($error) {
            throw new Exception("CURL error: $error");
        }
        
        if ($httpCode !== 200) {
            throw new Exception("TME API error: HTTP $httpCode - $response");
        }
        
        $data = json_decode($response, true);
        
        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new Exception('Invalid JSON response from TME API');
        }
        
        return $data;
    }
    
    /**
     * Rate limiting
     */
    private function waitForRateLimit() {
        $elapsed = microtime(true) - $this->lastRequestTime;
        
        if ($elapsed < $this->requestDelay) {
            usleep(($this->requestDelay - $elapsed) * 1000000);
        }
        
        $this->lastRequestTime = microtime(true);
    }
    
    /**
     * Прогресс-бар
     */
    private function showProgress($percent) {
        $barLength = 50;
        $filled = round($barLength * $percent / 100);
        $bar = str_repeat('█', $filled) . str_repeat('░', $barLength - $filled);
        
        $elapsed = time() - $this->stats['start_time'];
        $speed = $elapsed > 0 ? $this->stats['processed'] / $elapsed : 0;
        $remaining = $speed > 0 ? ($this->stats['total'] - $this->stats['processed']) / $speed : 0;
        
        echo "\r" . sprintf(
            "[%s] %.1f%% | %d/%d | ⚡ %.1f/с | ⏱️  %s осталось",
            $bar,
            $percent,
            $this->stats['processed'],
            $this->stats['total'],
            $speed,
            $this->formatTime($remaining)
        );
        
        if ($percent >= 100) {
            echo "\n";
        }
    }
    
    /**
     * Итоговый отчет
     */
    private function printFinalReport() {
        $elapsed = time() - $this->stats['start_time'];
        
        echo "\n";
        echo "════════════════════════════════════════════════════════════\n";
        echo "                 ИТОГОВЫЙ ОТЧЕТ СИНХРОНИЗАЦИИ               \n";
        echo "════════════════════════════════════════════════════════════\n";
        echo sprintf("📊 Всего артикулов:        %d\n", $this->stats['total']);
        echo sprintf("✅ Обработано успешно:     %d\n", $this->stats['success']);
        echo sprintf("❌ Ошибок:                 %d\n", $this->stats['failed']);
        echo sprintf("⏭️  Пропущено:              %d\n", $this->stats['skipped']);
        echo sprintf("⏱️  Общее время:            %s\n", $this->formatTime($elapsed));
        echo sprintf("⚡ Средняя скорость:       %.2f артикулов/сек\n", $this->stats['processed'] / max($elapsed, 1));
        echo sprintf("💾 Данных записано:        ~%.2f MB\n", $this->stats['success'] * 2 / 1024); // Примерно 2KB на артикул
        echo "════════════════════════════════════════════════════════════\n";
        
        if ($this->stats['failed'] > 0) {
            echo "⚠️  ВНИМАНИЕ: Есть ошибки! Проверьте логи.\n";
        } else {
            echo "✅ Синхронизация завершена успешно!\n";
        }
    }
    
    /**
     * Форматирование времени
     */
    private function formatTime($seconds) {
        if ($seconds < 60) {
            return sprintf("%d сек", $seconds);
        } elseif ($seconds < 3600) {
            return sprintf("%d мин", floor($seconds / 60));
        } else {
            return sprintf("%d ч %d мин", floor($seconds / 3600), floor(($seconds % 3600) / 60));
        }
    }
    
    /**
     * Логирование
     */
    private function log($message) {
        $timestamp = date('[Y-m-d H:i:s]');
        echo "$timestamp $message\n";
        
        // Также записываем в файл
        file_put_contents(
            '/var/log/tme_sync.log',
            "$timestamp $message\n",
            FILE_APPEND
        );
    }
}

/**
 * CLI интерфейс
 */
if (php_sapi_name() === 'cli') {
    echo "════════════════════════════════════════════════════════════\n";
    echo "           TME API МАССОВАЯ СИНХРОНИЗАЦИЯ                   \n";
    echo "════════════════════════════════════════════════════════════\n\n";
    
    // Параметры
    $options = getopt('', ['file:', 'batch:', 'token:']);
    
    $filename = $options['file'] ?? 'SKU_all.txt';
    $batchSize = $options['batch'] ?? 20;
    $apiToken = $options['token'] ?? '9c403f793a7fca44dd5d8b0dc5d8b02f3b4a6c0eecf3f943b08a4';
    
    // Подключение к БД
    try {
        $db = new PDO(
            "pgsql:host=localhost;dbname=calculator_db",
            "calculator_user",
            "your_password_here"
        );
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        // Создаем синхронизатор
        $sync = new TMEMassSync($apiToken, $db);
        $sync->importFromFile($filename);
        
    } catch (Exception $e) {
        echo "❌ КРИТИЧЕСКАЯ ОШИБКА: " . $e->getMessage() . "\n";
        exit(1);
    }
}
?>
