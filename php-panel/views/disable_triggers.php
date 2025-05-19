<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// SQL dosyasını oku
$sql_file_path = __DIR__ . '/../sql/disable_triggers.sql';
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
    $_SESSION['message'] = 'Tüm triggerlar başarıyla kaldırıldı! Artık gönderileri paylaşabilirsiniz.';
    $_SESSION['message_type'] = 'success';
} else {
    $_SESSION['message'] = 'Triggerlar kaldırılırken bir hata oluştu: ' . ($sql_result['error_message'] ?? 'Bilinmeyen hata');
    $_SESSION['message_type'] = 'danger';
}

// Kullanıcıyı dashboard sayfasına yönlendir
redirect('index.php?page=dashboard');
?>

<div class="d-flex justify-content-center align-items-center" style="height: 70vh;">
    <div class="spinner-border text-primary" role="status" style="width: 3rem; height: 3rem;">
        <span class="visually-hidden">Yükleniyor...</span>
    </div>
    <h3 class="ms-3">Triggerlar kaldırılıyor, lütfen bekleyin...</h3>
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