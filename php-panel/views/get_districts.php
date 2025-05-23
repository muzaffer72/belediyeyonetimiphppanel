<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Şehir ID'sini al
$city_id = isset($_GET['city_id']) ? (int)$_GET['city_id'] : 0;

// Hata kontrolü
if ($city_id <= 0) {
    echo json_encode(['error' => true, 'message' => 'Geçersiz şehir ID']);
    exit;
}

// İlçeleri al
$districts_result = getData('districts', [
    'select' => 'id,name',
    'city_id' => 'eq.' . $city_id,
    'order' => 'name'
]);

// Sonucu kontrol et
if (isset($districts_result['error']) && $districts_result['error']) {
    // Hata varsa boş bir sonuç döndür
    echo json_encode([
        'error' => false, 
        'message' => 'Veri bulunamadı',
        'data' => []
    ]);
} else {
    // Başarılı sonuç
    echo json_encode([
        'error' => false,
        'message' => 'İlçeler başarıyla alındı',
        'data' => $districts_result['data'] ?? []
    ]);
}
?>