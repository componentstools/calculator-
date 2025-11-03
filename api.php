<?php
/**
 * API для системы калькуляторов импорта
 * Интегрируется с Nexar/Octopart для получения данных о деталях
 * 
 * Endpoints:
 * - POST /api/auth/login - Авторизация
 * - GET /api/profile/active - Получить активный профиль расходов
 * - POST /api/calculate - Рассчитать цену
 * - GET /api/octopart/search - Поиск детали по артикулу
 * - POST /api/calculation/save - Сохранить расчет
 * - GET /api/calculations/history - История расчетов
 */

// Настройки
define('DB_HOST', 'localhost');
define('DB_NAME', 'calculator_db');
define('DB_USER', 'calculator_user');
define('DB_PASS', 'your_password_here');

// Nexar API настройки
define('NEXAR_CLIENT_ID', '56c235c4-6100-446d-9246-b9f7e0a986cd');
define('NEXAR_CLIENT_SECRET', 'yF2n6Ww_Ato9rKXxWdwVKULTZYk3ECQHHz34');
define('NEXAR_TOKEN_URL', 'https://identity.nexar.com/connect/token');
define('NEXAR_GRAPHQL_URL', 'https://api.nexar.com/graphql');

// CORS заголовки
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Content-Type: application/json; charset=utf-8');

// Обработка preflight запросов
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Подключение к БД
class Database {
    private static $instance = null;
    private $conn;
    
    private function __construct() {
        try {
            $this->conn = new PDO(
                "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
                DB_USER,
                DB_PASS,
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_EMULATE_PREPARES => false
                ]
            );
        } catch(PDOException $e) {
            die(json_encode(['error' => 'Database connection failed: ' . $e->getMessage()]));
        }
    }
    
    public static function getInstance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    public function getConnection() {
        return $this->conn;
    }
}

// Класс для работы с Nexar API
class NexarAPI {
    private $accessToken = null;
    private $tokenExpiry = 0;
    
    /**
     * Получить Access Token от Nexar
     */
    private function getAccessToken() {
        // Проверяем кэш токена
        if ($this->accessToken && time() < $this->tokenExpiry) {
            return $this->accessToken;
        }
        
        $ch = curl_init(NEXAR_TOKEN_URL);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
            CURLOPT_POSTFIELDS => http_build_query([
                'grant_type' => 'client_credentials',
                'client_id' => NEXAR_CLIENT_ID,
                'client_secret' => NEXAR_CLIENT_SECRET
            ])
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode !== 200) {
            throw new Exception('Failed to get Nexar access token: ' . $response);
        }
        
        $data = json_decode($response, true);
        $this->accessToken = $data['access_token'];
        $this->tokenExpiry = time() + ($data['expires_in'] - 300); // -5 минут для безопасности
        
        return $this->accessToken;
    }
    
    /**
     * Поиск детали по артикулу через Nexar GraphQL
     */
    public function searchPart($mpn) {
        $token = $this->getAccessToken();
        
        // GraphQL запрос
        $query = <<<'GRAPHQL'
query SearchPart($mpn: String!) {
  supSearchMpn(q: $mpn, limit: 1) {
    results {
      part {
        mpn
        manufacturer {
          name
        }
        shortDescription
        descriptions {
          text
        }
        specs {
          attribute {
            name
          }
          displayValue
        }
      }
      offers {
        clickUrl
        inventoryLevel
        moq
        prices {
          quantity
          price
          currency
        }
        seller {
          name
        }
        sku
        packaging
        leadTime
      }
    }
  }
}
GRAPHQL;
        
        $ch = curl_init(NEXAR_GRAPHQL_URL);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Authorization: Bearer ' . $token
            ],
            CURLOPT_POSTFIELDS => json_encode([
                'query' => $query,
                'variables' => ['mpn' => $mpn]
            ])
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode !== 200) {
            throw new Exception('Nexar API request failed: ' . $response);
        }
        
        $data = json_decode($response, true);
        
        if (isset($data['errors'])) {
            throw new Exception('Nexar GraphQL error: ' . json_encode($data['errors']));
        }
        
        return $this->parseNexarResponse($data);
    }
    
    /**
     * Парсинг ответа Nexar в удобный формат
     */
    private function parseNexarResponse($data) {
        if (!isset($data['data']['supSearchMpn']['results'][0])) {
            return [
                'found' => false,
                'error' => 'Part not found'
            ];
        }
        
        $result = $data['data']['supSearchMpn']['results'][0];
        $part = $result['part'];
        $offers = $result['offers'] ?? [];
        
        // Находим минимальную цену
        $minPrice = null;
        $currency = 'EUR';
        $availability = 0;
        $deliveryDays = null;
        
        foreach ($offers as $offer) {
            if (isset($offer['inventoryLevel'])) {
                $availability += $offer['inventoryLevel'];
            }
            
            if (isset($offer['leadTime'])) {
                $leadDays = $this->parseLeadTime($offer['leadTime']);
                if ($deliveryDays === null || $leadDays < $deliveryDays) {
                    $deliveryDays = $leadDays;
                }
            }
            
            if (isset($offer['prices'][0])) {
                $price = $offer['prices'][0]['price'];
                if ($minPrice === null || $price < $minPrice) {
                    $minPrice = $price;
                    $currency = $offer['prices'][0]['currency'] ?? 'EUR';
                }
            }
        }
        
        return [
            'found' => true,
            'mpn' => $part['mpn'],
            'manufacturer' => $part['manufacturer']['name'] ?? 'Unknown',
            'description' => $part['shortDescription'] ?? ($part['descriptions'][0]['text'] ?? ''),
            'availability' => $availability,
            'deliveryDays' => $deliveryDays ?? 14, // По умолчанию 2 недели
            'minPrice' => $minPrice,
            'currency' => $currency,
            'specs' => $part['specs'] ?? [],
            'offers' => array_slice($offers, 0, 5), // Топ 5 предложений
            'rawData' => $data // Полный ответ для логирования
        ];
    }
    
    /**
     * Парсинг строки срока поставки в дни
     */
    private function parseLeadTime($leadTime) {
        // Примеры: "2-3 weeks", "5 days", "1 week"
        $leadTime = strtolower($leadTime);
        
        if (preg_match('/(\d+)\s*week/i', $leadTime, $matches)) {
            return (int)$matches[1] * 7;
        }
        
        if (preg_match('/(\d+)\s*day/i', $leadTime, $matches)) {
            return (int)$matches[1];
        }
        
        return 14; // По умолчанию
    }
}

// Класс калькулятора
class Calculator {
    private $db;
    
    public function __construct() {
        $this->db = Database::getInstance()->getConnection();
    }
    
    /**
     * Получить активный профиль расходов
     */
    public function getActiveProfile() {
        $stmt = $this->db->query("SELECT * FROM b_calculator_expense_profiles WHERE is_default = TRUE LIMIT 1");
        $profile = $stmt->fetch();
        
        if (!$profile) {
            throw new Exception('No active expense profile found');
        }
        
        return $profile;
    }
    
    /**
     * Рассчитать цену продажи
     * 
     * @param float $purchasePriceEur - Цена закупки в EUR
     * @param float $desiredProfitRub - Желаемая прибыль в RUB (для админа)
     * @param float $desiredProfitPercent - Желаемая прибыль в % (для менеджера)
     * @param array $profile - Профиль расходов
     * @param float $deliveryInvoiceEur - Доставка по инвойсу
     */
    public function calculatePrice($purchasePriceEur, $desiredProfitRub = null, $desiredProfitPercent = null, $profile = null, $deliveryInvoiceEur = 0) {
        if ($profile === null) {
            $profile = $this->getActiveProfile();
        }
        
        // Доставка Европа
        $deliveryEur = ($purchasePriceEur * 1.1 <= 2) ? $profile['delivery_under_2kg'] : $deliveryInvoiceEur;
        $totalEur = $purchasePriceEur + $deliveryEur;
        
        // Курс и комиссия в зависимости от способа
        if ($profile['transfer_method'] === 'cash') {
            $kurs = $profile['eur_rub_rate'];
            $komisPerevod = $profile['commission_ip'] / 100;
            $komisAgent = 0;
        } else {
            $kurs = $profile['eur_usdt_rate'] * $profile['usdt_rub_rate'];
            $komisPerevod = $profile['commission_crypto'] / 100;
            $komisAgent = $profile['commission_agent'];
        }
        
        // Расчет суммы к выводу
        $kVivodu = $totalEur * $kurs * (1 + $komisPerevod) + $komisAgent;
        
        // Прямые расходы
        $pryamieRashodi = $kVivodu + $profile['delivery_rf'];
        
        // Налоги
        $nds = $profile['vat_percent'] / 100;
        $nalogNaPribil = $profile['profit_tax_percent'] / 100;
        $stoimostDocs = $profile['document_cost_percent'] / 100;
        $celProfit = $profile['target_official_profit'] / 100;
        
        // Если задана прибыль в процентах (менеджер), конвертируем в рубли
        if ($desiredProfitPercent !== null) {
            // Формула обратного расчета для процента
            // Цена = (Прямые расходы) / (1 - Процент прибыли - Расходы на документы - Налоги)
            $viruchkaBezNDS = $pryamieRashodi / (1 - ($desiredProfitPercent / 100) - $stoimostDocs * (1 - $celProfit) - $celProfit * $nalogNaPribil);
            $desiredProfitRub = $viruchkaBezNDS * ($desiredProfitPercent / 100);
        }
        
        // Формула обратного расчета от прибыли к цене
        $viruchkaBezNDS = ($desiredProfitRub + $pryamieRashodi) / (1 - $stoimostDocs * (1 - $celProfit) - $celProfit * $nalogNaPribil);
        
        $ndsSum = $viruchkaBezNDS * $nds;
        $cenaProdaji = $viruchkaBezNDS + $ndsSum;
        
        // Детализация расходов
        $zakupkaRub = $purchasePriceEur * $kurs;
        $dostavkaEvropaRub = $deliveryEur * $kurs;
        $komisRub = $kVivodu - $zakupkaRub - $dostavkaEvropaRub;
        
        $perviyPrihod = $zakupkaRub * 0.10;
        $celevayaPribil = $viruchkaBezNDS * $celProfit;
        $dopPrihod = $viruchkaBezNDS - $perviyPrihod - $celevayaPribil;
        $stoimostDokov = ($perviyPrihod + $dopPrihod) * $stoimostDocs;
        $nalogNaPribilSum = $celevayaPribil * $nalogNaPribil;
        
        // Точка безубыточности
        $breakeven = $pryamieRashodi + $stoimostDokov + $nalogNaPribilSum + $ndsSum;
        
        // Анализ конкурентов
        $competitorAvg = 0;
        $priceDifference = 0;
        if ($profile['competitor_price_min'] > 0 || $profile['competitor_price_max'] > 0) {
            $competitorAvg = ($profile['competitor_price_min'] + $profile['competitor_price_max']) / 2;
            $priceDifference = $cenaProdaji - $competitorAvg;
        }
        
        return [
            'price' => [
                'withVat' => round($cenaProdaji, 2),
                'withoutVat' => round($viruchkaBezNDS, 2),
                'vat' => round($ndsSum, 2),
                'breakeven' => round($breakeven, 2)
            ],
            'profit' => [
                'amount' => round($desiredProfitRub, 2),
                'percent' => round(($desiredProfitRub / $cenaProdaji) * 100, 2)
            ],
            'expenses' => [
                'purchase' => round($zakupkaRub, 2),
                'deliveryEurope' => round($dostavkaEvropaRub, 2),
                'commission' => round($komisRub, 2),
                'deliveryRf' => round($profile['delivery_rf'], 2),
                'documents' => round($stoimostDokov, 2),
                'vat' => round($ndsSum, 2),
                'profitTax' => round($nalogNaPribilSum, 2),
                'total' => round($zakupkaRub + $dostavkaEvropaRub + $komisRub + $profile['delivery_rf'] + $stoimostDokov + $ndsSum + $nalogNaPribilSum, 2)
            ],
            'expensesPercent' => [
                'purchase' => round(($zakupkaRub / $cenaProdaji) * 100, 2),
                'deliveryEurope' => round(($dostavkaEvropaRub / $cenaProdaji) * 100, 2),
                'commission' => round(($komisRub / $cenaProdaji) * 100, 2),
                'deliveryRf' => round(($profile['delivery_rf'] / $cenaProdaji) * 100, 2),
                'documents' => round(($stoimostDokov / $cenaProdaji) * 100, 2),
                'vat' => round(($ndsSum / $cenaProdaji) * 100, 2),
                'profitTax' => round(($nalogNaPribilSum / $cenaProdaji) * 100, 2)
            ],
            'competitors' => [
                'average' => round($competitorAvg, 2),
                'difference' => round($priceDifference, 2),
                'differencePercent' => $competitorAvg > 0 ? round(($priceDifference / $competitorAvg) * 100, 2) : 0,
                'cheaper' => $priceDifference < 0
            ]
        ];
    }
    
    /**
     * Сохранить расчет в БД
     */
    public function saveCalculation($data) {
        $stmt = $this->db->prepare("
            INSERT INTO b_calculator_calculations (
                profile_id, user_id, article_number, purchase_price_eur, delivery_invoice_eur,
                octopart_manufacturer, octopart_part_name, octopart_availability, octopart_delivery_days,
                octopart_min_price, octopart_data_json,
                desired_profit_rub, desired_profit_percent, calculated_price_with_vat, calculated_price_without_vat,
                breakeven_point, margin_percent, competitor_avg_price, price_difference,
                expense_purchase, expense_delivery_europe, expense_commission, expense_delivery_rf,
                expense_documents, expense_vat, expense_profit_tax, expense_total,
                calculation_type, status
            ) VALUES (
                :profile_id, :user_id, :article_number, :purchase_price_eur, :delivery_invoice_eur,
                :octopart_manufacturer, :octopart_part_name, :octopart_availability, :octopart_delivery_days,
                :octopart_min_price, :octopart_data_json,
                :desired_profit_rub, :desired_profit_percent, :calculated_price_with_vat, :calculated_price_without_vat,
                :breakeven_point, :margin_percent, :competitor_avg_price, :price_difference,
                :expense_purchase, :expense_delivery_europe, :expense_commission, :expense_delivery_rf,
                :expense_documents, :expense_vat, :expense_profit_tax, :expense_total,
                :calculation_type, 'calculated'
            )
        ");
        
        $stmt->execute($data);
        return $this->db->lastInsertId();
    }
    
    /**
     * Получить историю расчетов
     */
    public function getCalculationsHistory($userId = null, $limit = 50) {
        $sql = "SELECT * FROM v_calculations_full";
        if ($userId !== null) {
            $sql .= " WHERE user_id = :user_id";
        }
        $sql .= " ORDER BY created_at DESC LIMIT :limit";
        
        $stmt = $this->db->prepare($sql);
        if ($userId !== null) {
            $stmt->bindValue(':user_id', $userId, PDO::PARAM_INT);
        }
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        
        return $stmt->fetchAll();
    }
}

// Роутинг
$method = $_SERVER['REQUEST_METHOD'];
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$path = str_replace('/api', '', $path);

try {
    // GET /profile/active - Получить активный профиль
    if ($method === 'GET' && $path === '/profile/active') {
        $calc = new Calculator();
        $profile = $calc->getActiveProfile();
        
        echo json_encode([
            'success' => true,
            'data' => $profile
        ]);
    }
    
    // GET /octopart/search?mpn=... - Поиск детали
    elseif ($method === 'GET' && strpos($path, '/octopart/search') === 0) {
        $mpn = $_GET['mpn'] ?? '';
        
        if (empty($mpn)) {
            throw new Exception('MPN is required');
        }
        
        // Проверяем кэш
        $db = Database::getInstance()->getConnection();
        $stmt = $db->prepare("SELECT * FROM b_calculator_octopart_cache WHERE article_number = ? AND cache_valid = TRUE AND expires_at > NOW()");
        $stmt->execute([$mpn]);
        $cached = $stmt->fetch();
        
        if ($cached) {
            echo json_encode([
                'success' => true,
                'data' => json_decode($cached['full_response_json'], true),
                'cached' => true
            ]);
        } else {
            // Запрашиваем у Nexar
            $nexar = new NexarAPI();
            $result = $nexar->searchPart($mpn);
            
            // Сохраняем в кэш
            if ($result['found']) {
                $stmt = $db->prepare("
                    INSERT INTO b_calculator_octopart_cache (
                        article_number, manufacturer, part_name, availability, delivery_days,
                        min_price, currency, full_response_json, expires_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 24 HOUR))
                    ON DUPLICATE KEY UPDATE
                        manufacturer = VALUES(manufacturer),
                        part_name = VALUES(part_name),
                        availability = VALUES(availability),
                        delivery_days = VALUES(delivery_days),
                        min_price = VALUES(min_price),
                        currency = VALUES(currency),
                        full_response_json = VALUES(full_response_json),
                        expires_at = VALUES(expires_at),
                        cached_at = NOW(),
                        cache_valid = TRUE
                ");
                $stmt->execute([
                    $mpn,
                    $result['manufacturer'],
                    $result['description'],
                    $result['availability'],
                    $result['deliveryDays'],
                    $result['minPrice'],
                    $result['currency'],
                    json_encode($result)
                ]);
            }
            
            echo json_encode([
                'success' => true,
                'data' => $result,
                'cached' => false
            ]);
        }
    }
    
    // POST /calculate - Рассчитать цену
    elseif ($method === 'POST' && $path === '/calculate') {
        $input = json_decode(file_get_contents('php://input'), true);
        
        $purchasePriceEur = $input['purchasePriceEur'] ?? 0;
        $desiredProfitRub = $input['desiredProfitRub'] ?? null;
        $desiredProfitPercent = $input['desiredProfitPercent'] ?? null;
        $deliveryInvoiceEur = $input['deliveryInvoiceEur'] ?? 0;
        
        $calc = new Calculator();
        $result = $calc->calculatePrice($purchasePriceEur, $desiredProfitRub, $desiredProfitPercent, null, $deliveryInvoiceEur);
        
        echo json_encode([
            'success' => true,
            'data' => $result
        ]);
    }
    
    // POST /calculation/save - Сохранить расчет
    elseif ($method === 'POST' && $path === '/calculation/save') {
        $input = json_decode(file_get_contents('php://input'), true);
        
        $calc = new Calculator();
        $calculationId = $calc->saveCalculation($input);
        
        echo json_encode([
            'success' => true,
            'data' => ['calculationId' => $calculationId]
        ]);
    }
    
    // GET /calculations/history - История расчетов
    elseif ($method === 'GET' && strpos($path, '/calculations/history') === 0) {
        $userId = $_GET['userId'] ?? null;
        $limit = $_GET['limit'] ?? 50;
        
        $calc = new Calculator();
        $history = $calc->getCalculationsHistory($userId, $limit);
        
        echo json_encode([
            'success' => true,
            'data' => $history
        ]);
    }
    
    else {
        throw new Exception('Endpoint not found');
    }
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
