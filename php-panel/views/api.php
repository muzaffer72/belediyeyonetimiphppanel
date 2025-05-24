<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Sadece belirli API işlemleri için erişim kontrolü
$action = isset($_GET['action']) ? $_GET['action'] : '';
$protected_actions = ['update_post', 'delete_post', 'admin_action'];

if (in_array($action, $protected_actions) && !isLoggedIn()) {
    header('Content-Type: application/json');
    echo json_encode(['error' => true, 'message' => 'Bu işlem için giriş yapmanız gerekiyor']);
    exit;
}

// API işlemleri
switch ($action) {
    case 'get_post_detail':
        getPostDetail();
        break;
        
    case 'get_districts':
        getDistrictsByCityId();
        break;
        
    case 'update_post':
        updatePost();
        break;
    
    case 'update_auto_approve':
        updateUserAutoApprove();
        break;
        
    default:
        header('Content-Type: application/json');
        echo json_encode(['error' => true, 'message' => 'Geçersiz API işlemi']);
        break;
}

/**
 * Gönderi detaylarını getirir
 */
function getPostDetail() {
    $post_id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
    
    if ($post_id <= 0) {
        responseJson(true, 'Geçersiz gönderi ID');
        return;
    }
    
    // Gönderi bilgilerini al
    $post_result = getData('posts', [
        'select' => '*',
        'filters' => ['id' => 'eq.' . $post_id]
    ]);
    
    if ($post_result['error'] || empty($post_result['data'])) {
        responseJson(true, 'Gönderi bulunamadı');
        return;
    }
    
    $post = $post_result['data'][0];
    
    // Şehir ve ilçe adlarını al
    $city_result = getData('cities', [
        'select' => 'name',
        'filters' => ['id' => 'eq.' . $post['city_id']]
    ]);
    
    $district_result = getData('districts', [
        'select' => 'name',
        'filters' => ['id' => 'eq.' . $post['district_id']]
    ]);
    
    // Gönderi verilerini hazırla
    $post['city_name'] = (!$city_result['error'] && !empty($city_result['data'])) ? $city_result['data'][0]['name'] : 'Bilinmiyor';
    $post['district_name'] = (!$district_result['error'] && !empty($district_result['data'])) ? $district_result['data'][0]['name'] : 'Bilinmiyor';
    
    responseJson(false, 'Gönderi detayları başarıyla alındı', $post);
}

/**
 * Şehir ID'sine göre ilçeleri getirir
 */
function getDistrictsByCityId() {
    $city_id = isset($_GET['city_id']) ? (int)$_GET['city_id'] : 0;
    
    // Debug için bilgi logla
    error_log('İlçeler getiriliyor - Şehir ID: ' . $city_id);
    
    if ($city_id <= 0) {
        responseJson(true, 'Geçersiz şehir ID');
        return;
    }
    
    // İlk olarak districts tablosunun yapısını kontrol et
    $table_info = getData('districts', [
        'limit' => 1
    ]);
    
    // Debug bilgisi
    error_log('Districts tablosu bilgisi: ' . json_encode($table_info));
    
    // İlçeleri doğrudan city_id ile filtrele
    $districts_result = getData('districts', [
        'select' => 'id,name',
        'city_id' => 'eq.' . $city_id,
        'order' => 'name'
    ]);
    
    // Alternatif sorgu denemesi (Hata durumunda)
    if (isset($districts_result['error']) && $districts_result['error']) {
        error_log('İlk sorgu başarısız oldu, alternatif sorgu deneniyor...');
        
        // Tüm ilçeleri getir ve PHP tarafında filtreleme yap
        $all_districts = getData('districts', [
            'select' => '*',
            'order' => 'name'
        ]);
        
        if (!isset($all_districts['error']) || !$all_districts['error']) {
            // PHP tarafında filtreleme
            $filtered_districts = [];
            foreach ($all_districts['data'] as $district) {
                if (isset($district['city_id']) && (int)$district['city_id'] === $city_id) {
                    $filtered_districts[] = $district;
                }
            }
            
            responseJson(false, 'İlçeler alternatif yöntemle alındı (' . count($filtered_districts) . ' ilçe)', $filtered_districts);
            return;
        }
    }
    
    if (isset($districts_result['error']) && $districts_result['error']) {
        responseJson(true, 'İlçeler alınamadı: ' . ($districts_result['message'] ?? 'Bilinmeyen hata'));
        return;
    }
    
    // Sonuç bilgisi
    $districts_count = isset($districts_result['data']) ? count($districts_result['data']) : 0;
    error_log('Bulunan ilçe sayısı: ' . $districts_count);
    
    responseJson(false, 'İlçeler başarıyla alındı (' . $districts_count . ' ilçe)', $districts_result['data']);
}

/**
 * Gönderiyi günceller
 */
function updatePost() {
    // Sadece POST isteği kabul et
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        responseJson(true, 'Geçersiz istek metodu');
        return;
    }
    
    $post_id = isset($_POST['id']) ? (int)$_POST['id'] : 0;
    
    if ($post_id <= 0) {
        responseJson(true, 'Geçersiz gönderi ID');
        return;
    }
    
    // Güncellenecek alanları al
    $update_data = [];
    $allowed_fields = ['title', 'content', 'status', 'category', 'solution_note', 'evidence_url'];
    
    foreach ($allowed_fields as $field) {
        if (isset($_POST[$field])) {
            $update_data[$field] = $_POST[$field];
        }
    }
    
    if (empty($update_data)) {
        responseJson(true, 'Güncellenecek veri bulunamadı');
        return;
    }
    
    // Güncelleme zamanını ekle
    $update_data['updated_at'] = date('c');
    
    // Gönderiyi güncelle
    $update_result = updateData('posts', $post_id, $update_data);
    
    if ($update_result['error']) {
        responseJson(true, 'Gönderi güncellenemedi: ' . $update_result['message']);
        return;
    }
    
    responseJson(false, 'Gönderi başarıyla güncellendi');
}

/**
 * JSON yanıtı döndürür
 */
function responseJson($error, $message, $data = null) {
    header('Content-Type: application/json');
    echo json_encode([
        'error' => $error,
        'message' => $message,
        'data' => $data
    ]);
    exit;
}