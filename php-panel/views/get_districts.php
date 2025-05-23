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
    // Supabase'e bağlan
    $supabase = new Supabase($supabase_url, $supabase_key);
    
    // İlçeleri şehir ID'sine göre filtrele
    $query = [
        'select' => '*',
        'city_id' => 'eq.' . $city_id,
        'order' => 'name.asc'
    ];
    
    $districts_response = $supabase->from('districts')->select('*')->eq('city_id', $city_id)->order('name', 'asc')->execute();
    
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