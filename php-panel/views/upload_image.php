<?php
// Fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Yalnızca POST isteklerine izin ver
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['error' => true, 'message' => 'Sadece POST istekleri kabul edilir']);
    exit;
}

// Yüklenen dosyayı kontrol et
if (!isset($_FILES['image']) || empty($_FILES['image']['name'])) {
    echo json_encode(['error' => true, 'message' => 'Dosya yüklenmedi']);
    exit;
}

// Yükleme klasörü
$upload_dir = __DIR__ . '/../uploads/ads/';

// Klasör yoksa oluştur
if (!is_dir($upload_dir)) {
    mkdir($upload_dir, 0775, true);
}

// Dosya bilgileri
$file = $_FILES['image'];
$file_name = $file['name'];
$file_tmp = $file['tmp_name'];
$file_error = $file['error'];

// Dosya uzantısı
$file_ext = strtolower(pathinfo($file_name, PATHINFO_EXTENSION));

// İzin verilen uzantılar
$allowed_extensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];

// Hata kontrolü
if ($file_error !== 0) {
    $error_message = 'Dosya yükleme hatası: ';
    switch ($file_error) {
        case UPLOAD_ERR_INI_SIZE:
            $error_message .= 'Dosya boyutu PHP yapılandırma limitini aşıyor.';
            break;
        case UPLOAD_ERR_FORM_SIZE:
            $error_message .= 'Dosya boyutu form limitini aşıyor.';
            break;
        case UPLOAD_ERR_PARTIAL:
            $error_message .= 'Dosya yalnızca kısmen yüklendi.';
            break;
        case UPLOAD_ERR_NO_FILE:
            $error_message .= 'Dosya yüklenmedi.';
            break;
        case UPLOAD_ERR_NO_TMP_DIR:
            $error_message .= 'Geçici klasör bulunamadı.';
            break;
        case UPLOAD_ERR_CANT_WRITE:
            $error_message .= 'Disk yazma hatası.';
            break;
        case UPLOAD_ERR_EXTENSION:
            $error_message .= 'Dosya yükleme PHP uzantısı tarafından durduruldu.';
            break;
        default:
            $error_message .= 'Bilinmeyen hata.';
    }
    
    echo json_encode(['error' => true, 'message' => $error_message]);
    exit;
}

// Uzantı kontrolü
if (!in_array($file_ext, $allowed_extensions)) {
    echo json_encode(['error' => true, 'message' => 'Geçersiz dosya uzantısı. İzin verilen uzantılar: ' . implode(', ', $allowed_extensions)]);
    exit;
}

// Benzersiz dosya adı oluştur
$new_file_name = uniqid('ad_') . '_' . date('Ymd') . '.' . $file_ext;
$upload_path = $upload_dir . $new_file_name;

// Dosyayı taşı
if (move_uploaded_file($file_tmp, $upload_path)) {
    // Dosyaya web üzerinden erişim URL'si
    $base_url = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https://" : "http://";
    $base_url .= $_SERVER['HTTP_HOST'];
    // Doğrudan ads dizini içindeki dosyaya URL oluştur
    $image_url = $base_url . '/php-panel/uploads/ads/' . $new_file_name;
    
    echo json_encode([
        'error' => false, 
        'message' => 'Dosya başarıyla yüklendi',
        'fileName' => $new_file_name,
        'url' => $image_url
    ]);
} else {
    echo json_encode(['error' => true, 'message' => 'Dosya yüklenemedi']);
}