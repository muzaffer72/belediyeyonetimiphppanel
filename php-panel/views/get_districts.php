<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Şehir ID'sini al - string olarak tutuluyor olabilir (UUID formatında)
$city_id = isset($_GET['city_id']) ? $_GET['city_id'] : '';

// Debug için bilgiyi yazdır
error_log('İlçeler talep ediliyor - Şehir ID: ' . $city_id);

// Hata kontrolü - boş olmaması yeterli
if (empty($city_id)) {
    echo json_encode(['error' => true, 'message' => 'Geçersiz şehir ID (boş)']);
    exit;
}

// İlçeleri al - En güvenilir yöntem
try {
    error_log('Tüm ilçeleri getirmeyi deniyorum...');
    
    // Tüm ilçeleri getir
    $all_districts = getData('districts', [
        'select' => 'id,name,city_id',
        'order' => 'name'
    ]);
    
    // Başarılı mı?
    if (!isset($all_districts['error']) || !$all_districts['error']) {
        // İlçeleri manuel olarak filtrele
        $filtered_districts = [];
        
        foreach ($all_districts['data'] as $district) {
            if (isset($district['city_id']) && $district['city_id'] == $city_id) {
                $filtered_districts[] = [
                    'id' => $district['id'],
                    'name' => $district['name']
                ];
            }
        }
        
        // Hemen başarılı sonuç döndür
        echo json_encode([
            'error' => false,
            'message' => 'İlçeler manuel filtrelemeyle alındı (' . count($filtered_districts) . ' ilçe)',
            'data' => $filtered_districts
        ]);
        exit;
    }
    
    // İlk yöntem başarısız oldu, standart yöntemi dene
    error_log('Manuel filtreleme başarısız oldu, standart sorguyu deniyorum...');
    
    $districts_result = getData('districts', [
        'select' => 'id,name',
        'city_id' => 'eq.' . $city_id,
        'order' => 'name'
    ]);
} catch (Exception $e) {
    error_log('İlçe getirme işleminde exception: ' . $e->getMessage());
    
    // Hatayı yakaladık, standart sonuç döndür
    echo json_encode([
        'error' => false,
        'message' => 'İlçe verisi alınamadı (hata nedeniyle)',
        'data' => []
    ]);
    exit;
}

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