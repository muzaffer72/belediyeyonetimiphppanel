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
    // İlçe ID'si kontrolü
    if (!isset($_POST['district_id']) || empty($_POST['district_id'])) {
        $_SESSION['message'] = 'Geçersiz ilçe ID\'si';
        $_SESSION['message_type'] = 'danger';
        safeRedirect('index.php?page=districts');
    }
    
    $district_id = $_POST['district_id'];
    
    // Form verilerini al
    $total_complaints = isset($_POST['total_complaints']) ? intval($_POST['total_complaints']) : 0;
    $solved_complaints = isset($_POST['solved_complaints']) ? intval($_POST['solved_complaints']) : 0;
    $thanks_count = isset($_POST['thanks_count']) ? intval($_POST['thanks_count']) : 0;
    $solution_rate = isset($_POST['solution_rate']) ? floatval($_POST['solution_rate']) : 0;
    
    // Temel doğrulama
    $errors = [];
    
    // Çözülen şikayet sayısı toplam şikayet sayısından fazla olamaz
    if ($solved_complaints > $total_complaints) {
        $errors[] = 'Çözülen şikayet sayısı toplam şikayet sayısından fazla olamaz.';
    }
    
    // Çözüm oranı 0-100 arasında olmalı
    if ($solution_rate < 0 || $solution_rate > 100) {
        $errors[] = 'Çözüm oranı 0 ile 100 arasında olmalıdır.';
    }
    
    // Hata yoksa ilçe performans verilerini güncelle
    if (empty($errors)) {
        // İlçeyi güncelle
        $updateData = [
            'total_complaints' => $total_complaints,
            'solved_complaints' => $solved_complaints,
            'thanks_count' => $thanks_count,
            'solution_rate' => $solution_rate,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        $response = updateData('districts', $district_id, $updateData);
        
        if (!$response['error']) {
            // İlgili şehir ve parti istatistiklerini de güncellemek için işlem başlat
            // Not: Bu kısım veritabanınızda trigger'lar varsa otomatik olarak çalışacaktır
            
            // 1. İlçenin bağlı olduğu şehri bul
            $district = getDataById('districts', $district_id);
            if ($district && isset($district['city_id'])) {
                // Şehir istatistiklerini güncelle (bu fonksiyon veritabanınızda varsa)
                $stmt = $pdo->prepare("SELECT party_stats_update_city(:city_id)");
                $stmt->execute(['city_id' => $district['city_id']]);
            }
            
            // 2. Parti istatistiklerini güncelle (bu fonksiyon veritabanınızda varsa)
            $stmt = $pdo->prepare("SELECT party_stats_calculate_scores()");
            $stmt->execute();
            
            $_SESSION['message'] = 'İlçe performans verileri başarıyla güncellendi.';
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
    safeRedirect('index.php?page=district_performance&id=' . $district_id);
}

// Refresh parametresi varsa, verileri veritabanından yenileme işlemi yap
if (isset($_GET['refresh']) && isset($_GET['id'])) {
    $district_id = $_GET['id'];
    
    // İlçenin şehir ID'sini al
    $district = getDataById('districts', $district_id);
    if ($district && isset($district['city_id'])) {
        // Şehir ve ilçe istatistiklerini yeniden hesapla
        try {
            // 1. İlçe çözüm oranını hesapla
            $stmt = $pdo->prepare("
                UPDATE districts d
                SET solution_rate = (
                    CASE 
                        WHEN (COALESCE(d.total_complaints, 0) + COALESCE(d.thanks_count, 0)) = 0 THEN 0
                        ELSE ((COALESCE(d.solved_complaints, 0) + COALESCE(d.thanks_count, 0)) * 100.0 / 
                              (COALESCE(d.total_complaints, 0) + COALESCE(d.thanks_count, 0)))
                    END
                )
                WHERE d.id = :district_id
            ");
            $stmt->execute(['district_id' => $district_id]);
            
            // 2. Şehir istatistiklerini güncelle
            $stmt = $pdo->prepare("SELECT party_stats_update_city(:city_id)");
            $stmt->execute(['city_id' => $district['city_id']]);
            
            // 3. Parti istatistiklerini güncelle
            $stmt = $pdo->prepare("SELECT party_stats_calculate_scores()");
            $stmt->execute();
            
            $_SESSION['message'] = 'İlçe performans verileri başarıyla yenilendi.';
            $_SESSION['message_type'] = 'success';
        } catch (Exception $e) {
            $_SESSION['message'] = 'Veriler güncellenirken bir hata oluştu: ' . $e->getMessage();
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'İlçe bilgileri bulunamadı.';
        $_SESSION['message_type'] = 'danger';
    }
    
    // Performans sayfasına geri dön
    safeRedirect('index.php?page=district_performance&id=' . $district_id);
}

// Direkt erişim için uyarı
$_SESSION['message'] = 'Direkt erişim yapılamaz. Lütfen ilçe performans sayfasındaki güncelleme formunu kullanın.';
$_SESSION['message_type'] = 'warning';
safeRedirect('index.php?page=districts');
?>