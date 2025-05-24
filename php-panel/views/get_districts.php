<?php
// Gerekli dosyaları dahil et
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Hata ayıklama modu
$debug = true; // Geliştirme aşamasında hata ayıklama modunu aktif et

// Yanıt formatı
header('Content-Type: application/json');

// Şehir ID veya Şehir Adı kontrolü
$city_id = isset($_GET['city_id']) ? $_GET['city_id'] : null;
$city_name = isset($_GET['city_name']) ? $_GET['city_name'] : null;

// İkisi de boşsa hata ver
if (empty($city_id) && empty($city_name)) {
    echo json_encode(['error' => true, 'message' => 'Şehir ID veya adı belirtilmedi', 'data' => []]);
    exit;
}

try {
    // Önce şehir adından city_id'yi bulmamız gerekiyorsa
    if (empty($city_id) && !empty($city_name)) {
        $cities_result = getData('cities', [
            'name' => 'eq.' . $city_name,
            'select' => 'id,name'
        ]);
        
        if ($debug) {
            error_log('Şehir arama sorgusu: ' . json_encode($cities_result));
        }
        
        if (!empty($cities_result['data']) && isset($cities_result['data'][0]['id'])) {
            $city_id = $cities_result['data'][0]['id'];
            if ($debug) {
                error_log('Şehir adından ID bulundu: ' . $city_id);
            }
        } else {
            echo json_encode(['error' => true, 'message' => 'Şehir bulunamadı: ' . $city_name, 'data' => []]);
            exit;
        }
    }
    
    // Şimdi city_id ile ilçeleri alalım
    $districts_result = getData('districts', [
        'city_id' => 'eq.' . $city_id,
        'order' => 'name.asc',
        'select' => '*'
    ]);
    
    if ($debug) {
        error_log('İlçe arama sorgusu: ' . json_encode($districts_result));
    }
    
    // API yanıt kontrolü
    if (isset($districts_result['error']) && $districts_result['error']) {
        throw new Exception('API hatası: ' . ($districts_result['message'] ?? 'Bilinmeyen hata'));
    }
    
    // İlçe verisi array olmalı
    $districts_data = isset($districts_result['data']) ? $districts_result['data'] : [];
    
    if (!is_array($districts_data)) {
        $districts_data = [];
        if ($debug) {
            error_log('Warning: Expected data array but got: ' . gettype($districts_data));
        }
    }
    
    // Başarılı yanıt
    echo json_encode([
        'error' => false,
        'message' => 'İlçeler başarıyla alındı',
        'data' => $districts_data
    ]);
    
} catch (Exception $e) {
    if ($debug) {
        echo json_encode([
            'error' => true,
            'message' => 'İlçeler yüklenirken bir hata oluştu: ' . $e->getMessage(),
            'data' => []
        ]);
    } else {
        echo json_encode([
            'error' => true,
            'message' => 'İlçeler yüklenirken bir hata oluştu',
            'data' => []
        ]);
    }
}
?>