<?php
// Gerekli dosyaları dahil et
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Hata ayıklama modu
$debug = true; // Geliştirme aşamasında hata ayıklama modunu aktif et

// Yanıt formatı
header('Content-Type: application/json');

// Şehir ID kontrolü
if (!isset($_GET['city_id']) || empty($_GET['city_id'])) {
    echo json_encode(['error' => true, 'message' => 'Şehir ID\'si belirtilmedi', 'districts' => []]);
    exit;
}

$city_id = $_GET['city_id'];

try {
    // API URL'sini oluştur
    $api_url = SUPABASE_REST_URL . '/districts';
    
    // Filtre parametreleri
    $params = [
        'select' => '*',
        'city_id' => 'eq.' . $city_id,
        'order' => 'name.asc'
    ];
    
    $url = $api_url . '?' . http_build_query($params);
    
    if ($debug) {
        error_log('Request URL: ' . $url);
    }
    
    // cURL isteği oluştur
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'apikey: ' . SUPABASE_API_KEY,
        'Authorization: ' . SUPABASE_AUTH_HEADER,
        'Content-Type: application/json'
    ]);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // Geliştirme ortamında SSL kontrolünü devre dışı bırak
    
    // API yanıtını al
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_error = curl_error($ch);
    
    curl_close($ch);
    
    if ($debug) {
        error_log('Response Status: ' . $http_code);
        error_log('Response Body: ' . $response);
        if ($curl_error) {
            error_log('cURL Error: ' . $curl_error);
        }
    }
    
    // API hata kontrolü
    if ($http_code !== 200) {
        throw new Exception('HTTP Error: ' . $http_code);
    }
    
    if ($curl_error) {
        throw new Exception('cURL Error: ' . $curl_error);
    }
    
    // JSON yanıtını çöz
    $districts_data = json_decode($response, true);
    
    // JSON ayrıştırma hatası kontrolü
    if ($districts_data === null && json_last_error() !== JSON_ERROR_NONE) {
        throw new Exception('JSON parse error: ' . json_last_error_msg() . ' Response: ' . $response);
    }
    
    // JSON array bekliyoruz, değilse boş array oluştur
    if (!is_array($districts_data)) {
        $districts_data = [];
        if ($debug) {
            error_log('Warning: Expected JSON array but got: ' . gettype($districts_data));
        }
    }
    
    // Başarılı yanıt
    echo json_encode([
        'error' => false,
        'districts' => $districts_data
    ]);
    
} catch (Exception $e) {
    if ($debug) {
        echo json_encode([
            'error' => true,
            'message' => 'İlçeler yüklenirken bir hata oluştu: ' . $e->getMessage(),
            'districts' => []
        ]);
    } else {
        echo json_encode([
            'error' => true,
            'message' => 'İlçeler yüklenirken bir hata oluştu',
            'districts' => []
        ]);
    }
}
?>