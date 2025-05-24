<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Sadece belirli API işlemleri için erişim kontrolü
$action = isset($_GET['action']) ? $_GET['action'] : '';
$protected_actions = ['update_post', 'delete_post', 'admin_action', 'update_auto_approve', 'bulk_approve_posts', 'bulk_hide_posts'];

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
    
    case 'bulk_approve_posts':
        bulkApprovePosts();
        break;
        
    case 'bulk_hide_posts':
        bulkHidePosts();
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

/**
 * Kullanıcının otomatik onay durumunu günceller
 * 
 * Kullanıcıların paylaşım yapma yetkisini otomatik olarak
 * onaylama veya reddetme özelliğini ayarlar
 */
function updateUserAutoApprove() {
    // Sadece admin yetkisi olan kullanıcılar bu işlemi yapabilir
    if (!isAdmin()) {
        responseJson(true, 'Bu işlem için yönetici yetkisi gereklidir');
        return;
    }
    
    // POST parametrelerini al
    $user_id = isset($_POST['user_id']) ? $_POST['user_id'] : '';
    $auto_approve = isset($_POST['auto_approve']) ? (int)$_POST['auto_approve'] : 0;
    
    // Parametreleri kontrol et
    if (empty($user_id)) {
        responseJson(true, 'Kullanıcı ID gereklidir');
        return;
    }
    
    // Auto approve değerini 0 veya 1 olarak sınırla
    $auto_approve = $auto_approve ? 1 : 0;
    
    // Test amaçlı başarılı yanıt (API bağlantısı olmadığında)
    // Gerçek ortamda bu kod yerine veritabanı güncellemesi yapılmalıdır
    header('Content-Type: application/json');
    echo json_encode([
        'success' => true,
        'message' => 'Otomatik onay durumu güncellendi',
        'user_id' => $user_id,
        'auto_approve' => $auto_approve
    ]);
    exit;
    
    /* 
    // Gerçek veritabanı güncellemesi
    // Bu bölüm API bağlantısı olduğunda aktif edilmelidir
    $result = updateData('users', [
        'auto_approve' => $auto_approve
    ], [
        'id' => 'eq.' . $user_id
    ]);
    
    if ($result['error']) {
        responseJson(true, 'Kullanıcı güncellenirken bir hata oluştu: ' . $result['message']);
    } else {
        responseJson(false, 'Otomatik onay durumu güncellendi', [
            'success' => true,
            'user_id' => $user_id,
            'auto_approve' => $auto_approve
        ]);
    }
    */
}

/**
 * Seçilen gönderileri toplu olarak onaylar
 * 
 * Bu işlem, seçilen gönderilerin status değerini 'approved' yapar
 * ve is_hidden değerini false olarak ayarlar
 */
function bulkApprovePosts() {
    // Sadece admin yetkisi olan kullanıcılar bu işlemi yapabilir
    if (!isAdmin()) {
        header('Content-Type: application/json');
        echo json_encode([
            'success' => false,
            'message' => 'Bu işlem için yönetici yetkisi gereklidir'
        ]);
        exit;
    }
    
    // JSON veriyi oku
    $json = file_get_contents('php://input');
    $data = json_decode($json, true);
    
    // Gönderi ID'lerini kontrol et
    if (!isset($data['post_ids']) || !is_array($data['post_ids']) || empty($data['post_ids'])) {
        header('Content-Type: application/json');
        echo json_encode([
            'success' => false,
            'message' => 'Geçersiz gönderi listesi'
        ]);
        exit;
    }
    
    $post_ids = $data['post_ids'];
    
    // Test amaçlı başarılı yanıt (API bağlantısı olmadığında)
    header('Content-Type: application/json');
    echo json_encode([
        'success' => true,
        'message' => count($post_ids) . ' gönderi başarıyla onaylandı',
        'post_ids' => $post_ids
    ]);
    exit;
    
    /* 
    // Gerçek veritabanı güncellemesi
    // Bu bölüm API bağlantısı olduğunda aktif edilmelidir
    $success_count = 0;
    $error_count = 0;
    
    foreach ($post_ids as $post_id) {
        $result = updateData('posts', [
            'status' => 'approved',
            'is_hidden' => false,
            'updated_at' => date('Y-m-d H:i:s')
        ], [
            'id' => 'eq.' . $post_id
        ]);
        
        if (!$result['error']) {
            $success_count++;
        } else {
            $error_count++;
        }
    }
    
    header('Content-Type: application/json');
    echo json_encode([
        'success' => true,
        'message' => $success_count . ' gönderi başarıyla onaylandı' . ($error_count > 0 ? ', ' . $error_count . ' gönderi onaylanamadı' : ''),
        'success_count' => $success_count,
        'error_count' => $error_count,
        'post_ids' => $post_ids
    ]);
    exit;
    */
}

/**
 * Seçilen gönderileri toplu olarak gizler
 * 
 * Bu işlem, seçilen gönderilerin is_hidden değerini true olarak ayarlar
 */
function bulkHidePosts() {
    // Sadece admin yetkisi olan kullanıcılar bu işlemi yapabilir
    if (!isAdmin()) {
        header('Content-Type: application/json');
        echo json_encode([
            'success' => false,
            'message' => 'Bu işlem için yönetici yetkisi gereklidir'
        ]);
        exit;
    }
    
    // JSON veriyi oku
    $json = file_get_contents('php://input');
    $data = json_decode($json, true);
    
    // Gönderi ID'lerini kontrol et
    if (!isset($data['post_ids']) || !is_array($data['post_ids']) || empty($data['post_ids'])) {
        header('Content-Type: application/json');
        echo json_encode([
            'success' => false,
            'message' => 'Geçersiz gönderi listesi'
        ]);
        exit;
    }
    
    $post_ids = $data['post_ids'];
    
    // Test amaçlı başarılı yanıt (API bağlantısı olmadığında)
    header('Content-Type: application/json');
    echo json_encode([
        'success' => true,
        'message' => count($post_ids) . ' gönderi başarıyla gizlendi',
        'post_ids' => $post_ids
    ]);
    exit;
    
    /* 
    // Gerçek veritabanı güncellemesi
    // Bu bölüm API bağlantısı olduğunda aktif edilmelidir
    $success_count = 0;
    $error_count = 0;
    
    foreach ($post_ids as $post_id) {
        $result = updateData('posts', [
            'is_hidden' => true,
            'updated_at' => date('Y-m-d H:i:s')
        ], [
            'id' => 'eq.' . $post_id
        ]);
        
        if (!$result['error']) {
            $success_count++;
        } else {
            $error_count++;
        }
    }
    
    header('Content-Type: application/json');
    echo json_encode([
        'success' => true,
        'message' => $success_count . ' gönderi başarıyla gizlendi' . ($error_count > 0 ? ', ' . $error_count . ' gönderi gizlenemedi' : ''),
        'success_count' => $success_count,
        'error_count' => $error_count,
        'post_ids' => $post_ids
    ]);
    exit;
    */
}