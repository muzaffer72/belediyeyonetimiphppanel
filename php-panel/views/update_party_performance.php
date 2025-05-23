<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimine izin ver
if (!isAdmin()) {
    $_SESSION['message'] = 'Bu sayfaya erişim izniniz bulunmamaktadır.';
    $_SESSION['message_type'] = 'danger';
    safeRedirect('index.php?page=dashboard');
}

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Parti ID'si kontrolü
    if (!isset($_POST['party_id']) || empty($_POST['party_id'])) {
        $_SESSION['message'] = 'Geçersiz parti ID\'si';
        $_SESSION['message_type'] = 'danger';
        safeRedirect('index.php?page=parties');
    }
    
    $party_id = $_POST['party_id'];
    
    // Form verilerini al
    $party_score = isset($_POST['party_score']) ? floatval($_POST['party_score']) : 0;
    $parti_sikayet_sayisi = isset($_POST['parti_sikayet_sayisi']) ? intval($_POST['parti_sikayet_sayisi']) : 0;
    $parti_cozulmus_sikayet_sayisi = isset($_POST['parti_cozulmus_sikayet_sayisi']) ? intval($_POST['parti_cozulmus_sikayet_sayisi']) : 0;
    $parti_tesekkur_sayisi = isset($_POST['parti_tesekkur_sayisi']) ? intval($_POST['parti_tesekkur_sayisi']) : 0;
    
    // Temel doğrulama
    $errors = [];
    
    // Çözülen şikayet sayısı toplam şikayet sayısından fazla olamaz
    if ($parti_cozulmus_sikayet_sayisi > $parti_sikayet_sayisi) {
        $errors[] = 'Çözülen şikayet sayısı toplam şikayet sayısından fazla olamaz.';
    }
    
    // Performans puanı 0-100 arasında olmalı
    if ($party_score < 0 || $party_score > 100) {
        $errors[] = 'Performans puanı 0 ile 100 arasında olmalıdır.';
    }
    
    // Hata yoksa parti performans verilerini güncelle
    if (empty($errors)) {
        // Partiyi güncelle
        $updateData = [
            'score' => $party_score,
            'parti_sikayet_sayisi' => $parti_sikayet_sayisi,
            'parti_cozulmus_sikayet_sayisi' => $parti_cozulmus_sikayet_sayisi,
            'parti_tesekkur_sayisi' => $parti_tesekkur_sayisi,
            'last_updated' => date('Y-m-d H:i:s')
        ];
        
        $response = updateData('political_parties', $party_id, $updateData);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Parti performans verileri başarıyla güncellendi.';
            $_SESSION['message_type'] = 'success';
        } else {
            $_SESSION['message'] = 'Veriler güncellenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
    
    // Performans sayfasına geri dön
    safeRedirect('index.php?page=party_performance&id=' . $party_id);
}

// Refresh parametresi varsa, verileri veritabanından yenileme işlemi yap
if (isset($_GET['refresh']) && isset($_GET['id'])) {
    $party_id = $_GET['id'];
    
    try {
        // Parti skorunu ve istatistiklerini yeniden hesapla
        $stmt = $pdo->prepare("SELECT calculate_party_scores_integer()");
        $stmt->execute();
        
        $_SESSION['message'] = 'Parti performans verileri başarıyla yenilendi.';
        $_SESSION['message_type'] = 'success';
    } catch (Exception $e) {
        $_SESSION['message'] = 'Veriler güncellenirken bir hata oluştu: ' . $e->getMessage();
        $_SESSION['message_type'] = 'danger';
    }
    
    // Performans sayfasına geri dön
    safeRedirect('index.php?page=party_performance&id=' . $party_id);
}

// Direkt erişim için uyarı
$_SESSION['message'] = 'Direkt erişim yapılamaz. Lütfen parti performans sayfasındaki güncelleme formunu kullanın.';
$_SESSION['message_type'] = 'warning';
safeRedirect('index.php?page=parties');
?>