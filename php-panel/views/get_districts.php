<?php
// Gerekli dosyaları dahil et
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Hata ayıklama modu
$debug = false;

// Yanıt formatı
header('Content-Type: application/json');

// Şehir ID kontrolü
if (!isset($_GET['city_id']) || empty($_GET['city_id'])) {
    echo json_encode(['error' => true, 'message' => 'Şehir ID\'si belirtilmedi']);
    exit;
}

$city_id = $_GET['city_id'];

try {
    // Config dosyasından Supabase bilgilerini al
    global $supabase_url, $supabase_key, $supabase_anon_key;

    // API URL ve Key kontrolü
    if (empty($supabase_url) || empty($supabase_key)) {
        throw new Exception('Supabase API bilgileri eksik veya hatalı.');
    }
    
    // İlçeleri almak için API URL'si
    $api_url = $supabase_url . '/rest/v1/districts';
    
    // API isteği için başlıklar
    $headers = [
        'apikey: ' . $supabase_key,
        'Authorization: Bearer ' . $supabase_key,
        'Content-Type: application/json',
        'Prefer: return=representation'
    ];
    
    // İlçeleri şehir ID'sine göre filtrele
    $query_params = http_build_query([
        'select' => '*',
        'city_id' => 'eq.' . $city_id,
        'order' => 'name.asc'
    ]);
    
    // API URL'sini oluştur
    $request_url = $api_url . '?' . $query_params;
    
    // cURL ile istek yap
    $ch = curl_init($request_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // Geliştirme ortamında SSL doğrulama
    
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_error = curl_error($ch);
    
    curl_close($ch);
    
    // Hata kontrolü
    if ($http_code !== 200 || $curl_error) {
        throw new Exception('API isteği sırasında hata: ' . $curl_error . ' HTTP Kodu: ' . $http_code);
    }
    
    // JSON yanıtını çöz
    $districts_data = json_decode($response, true);
    
    if ($districts_data === null && json_last_error() !== JSON_ERROR_NONE) {
        throw new Exception('JSON yanıtı çözülemedi: ' . json_last_error_msg());
    }
    
    // Debug mod aktifse API yanıtını da logla
    if ($debug) {
        error_log('Districts API response: ' . print_r($districts_data, true));
    }
    
    // Yanıtı districts_response formatına dönüştür
    $districts_response = [
        'data' => $districts_data,
        'error' => null
    ];
    
    // Hata kontrolü
    if (isset($districts_response['error'])) {
        if ($debug) {
            echo json_encode([
                'error' => true, 
                'message' => 'İlçeler yüklenirken bir hata oluştu', 
                'api_error' => $districts_response['error']
            ]);
        } else {
            echo json_encode(['error' => true, 'message' => 'İlçeler yüklenirken bir hata oluştu']);
        }
        exit;
    }
    
    // İlçeleri diziye aktar
    $districts = [];
    if (isset($districts_response['data']) && is_array($districts_response['data'])) {
        foreach ($districts_response['data'] as $district) {
            $districts[] = [
                'id' => $district['id'],
                'name' => $district['name'],
                'city_id' => $district['city_id']
            ];
        }
    }
    
    // Sonuçları döndür
    echo json_encode([
        'error' => false,
        'districts' => $districts
    ]);
    
} catch (Exception $e) {
    if ($debug) {
        echo json_encode([
            'error' => true, 
            'message' => 'İstek sırasında bir hata oluştu', 
            'exception' => $e->getMessage()
        ]);
    } else {
        echo json_encode(['error' => true, 'message' => 'İstek sırasında bir hata oluştu']);
    }
}
?>