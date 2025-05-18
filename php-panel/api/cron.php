<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// Cron işlerinin çalıştırılması için API endpoint
// Bu dosyaya dışarıdan HTTP isteği yapılarak cron işleri tetiklenebilir

// API anahtarı kontrolü (Basit güvenlik için)
$api_key = isset($_GET['api_key']) ? $_GET['api_key'] : '';
$valid_api_key = 'MY_SECURE_CRON_API_KEY'; // Gerçek uygulamada bu değer config dosyasında saklanmalı

if ($api_key !== $valid_api_key) {
    header('HTTP/1.1 401 Unauthorized');
    echo json_encode(['error' => 'Geçersiz API anahtarı']);
    exit;
}

// Hangi cron işinin çalıştırılacağını belirle
$job = isset($_GET['job']) ? $_GET['job'] : '';

// Cron işini çalıştır
$result = [
    'success' => false,
    'message' => '',
    'start_time' => date('Y-m-d H:i:s'),
    'execution_time' => 0
];

$start_time = microtime(true);

try {
    switch ($job) {
        case 'update_solution_rates':
            // Çözüm oranlarını güncelle
            require_once(__DIR__ . '/../cron/update_solution_rates.php');
            $result['success'] = true;
            $result['message'] = 'Çözüm oranları güncellendi';
            break;
            
        case 'create_table':
            // cozumorani tablosunu oluştur
            require_once(__DIR__ . '/../cron/create_cozumorani_table.php');
            $result['success'] = true;
            $result['message'] = 'Çözüm oranları tablosu oluşturuldu';
            break;
            
        default:
            $result['message'] = 'Geçersiz cron işi';
            break;
    }
} catch (Exception $e) {
    $result['message'] = 'Hata: ' . $e->getMessage();
}

// Çalışma süresini hesapla
$result['execution_time'] = microtime(true) - $start_time;

// Sonucu JSON olarak döndür
header('Content-Type: application/json');
echo json_encode($result);
?>