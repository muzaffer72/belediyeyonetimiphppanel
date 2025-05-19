<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// SQL dosyasını oku
$sql_file_path = __DIR__ . '/../sql/simple_party_score_trigger.sql';
if (!file_exists($sql_file_path)) {
    $_SESSION['message'] = 'SQL dosyası bulunamadı!';
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=dashboard');
}

$sql_content = file_get_contents($sql_file_path);

// SQL sorgularını çalıştır
$sql_result = executeRawSql($sql_content);

// Sonucu kontrol et ve mesaj göster
if (!$sql_result['error']) {
    $_SESSION['message'] = 'Puanlama sistemi başarıyla güncellendi! Artık tüm parti puanları 100\'lük sistemde hesaplanacak. A partisi (%50) ve B partisi (%50) gibi eşit dağılımlar yapılacak.';
    $_SESSION['message_type'] = 'success';
} else {
    $_SESSION['message'] = 'Puanlama sistemi güncellenirken bir hata oluştu: ' . ($sql_result['error_message'] ?? 'Bilinmeyen hata');
    $_SESSION['message_type'] = 'danger';
}

// Manuel olarak puanları hemen hesapla
$manual_update = "SELECT update_party_scores()";
$manual_result = executeRawSql($manual_update);

// Kullanıcıyı dashboard sayfasına yönlendir
redirect('index.php?page=dashboard');
?>

<div class="d-flex justify-content-center align-items-center" style="height: 70vh;">
    <div class="spinner-border text-primary" role="status" style="width: 3rem; height: 3rem;">
        <span class="visually-hidden">Yükleniyor...</span>
    </div>
    <h3 class="ms-3">Puanlama sistemi güncelleniyor, lütfen bekleyin...</h3>
</div>

<script>
    // Sayfa yüklendiğinde otomatik olarak formu gönder
    document.addEventListener('DOMContentLoaded', function() {
        // 2 saniye bekleyip yönlendirme
        setTimeout(function() {
            window.location.href = 'index.php?page=dashboard';
        }, 2000);
    });
</script>