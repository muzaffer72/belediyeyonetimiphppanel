<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// SQL dosyasını oku
$sql_file_path = __DIR__ . '/../sql/party_score_recalculation.sql';
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
    $_SESSION['message'] = 'Puanlama sistemi başarıyla güncellendi! Artık tüm parti puanları dengeli bir şekilde 100\'lük sistemde hesaplanacak.';
    $_SESSION['message_type'] = 'success';
} else {
    $_SESSION['message'] = 'Puanlama sistemi güncellenirken bir hata oluştu: ' . $sql_result['error_message'];
    $_SESSION['message_type'] = 'danger';
}

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