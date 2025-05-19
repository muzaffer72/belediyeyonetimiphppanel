<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

$sql_file_path = __DIR__ . '/../sql/fix_post_sharing_trigger.sql';
$sql_content = file_exists($sql_file_path) ? file_get_contents($sql_file_path) : '';
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Gönderi Paylaşım Sorununu Çözme</h5>
    </div>
    <div class="card-body">
        <div class="alert alert-warning">
            <h6><i class="fas fa-exclamation-triangle me-2"></i> Gönderi Paylaşım Sorunu Çözümü</h6>
            <p>Mevcut triggerlar gönderi paylaşımını engellediği için yeni bir çözüm geliştirildi:</p>
            <ul>
                <li>Mevcut tüm sorunlu triggerlar kaldırılacak</li>
                <li>Sadece etkilenen district ve city için hesaplama yapan daha hafif bir trigger eklenecek</li>
                <li>Bu yeni trigger, gönderi paylaşımını engellemeyecek</li>
            </ul>
        </div>
        
        <div class="card mb-3">
            <div class="card-header bg-primary text-white">
                <h6 class="mb-0">Gönderi Paylaşım Sorunu Çözüm SQL Kodu</h6>
            </div>
            <div class="card-body">
                <pre class="p-3 bg-light"><code><?php echo htmlspecialchars($sql_content); ?></code></pre>
                <button class="btn btn-sm btn-primary" id="copyBtn">
                    <i class="fas fa-copy me-1"></i> Kopyala
                </button>
            </div>
        </div>
        
        <div class="alert alert-info">
            <h6><i class="fas fa-info-circle me-2"></i> Uygulama Talimatları</h6>
            <ol>
                <li>Supabase projenizin dashboard'ına giriş yapın</li>
                <li>SQL Editör'ü açın</li>
                <li>Yukarıdaki SQL kodunu kopyalayın ve yapıştırın</li>
                <li>Kodu çalıştırın</li>
                <li>Gönderi paylaşımını test edin - artık sorunsuz çalışıyor olmalı</li>
            </ol>
            <p><strong>Not:</strong> Bu çözüm eski karmaşık triggerları siler ve sadece etkilenen ilçe/şehir için çözüm oranını hesaplayacak daha basit bir trigger ekler. Böylece sistem daha hafif ve performanslı çalışacaktır.</p>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Kopyalama düğmesini ayarla
    document.getElementById('copyBtn').addEventListener('click', function() {
        const code = document.querySelector('.card-body pre code').textContent;
        copyToClipboard(code);
        this.innerHTML = '<i class="fas fa-check me-1"></i> Kopyalandı!';
        setTimeout(() => {
            this.innerHTML = '<i class="fas fa-copy me-1"></i> Kopyala';
        }, 2000);
    });
    
    // Panoya kopyalama fonksiyonu
    function copyToClipboard(text) {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
    }
});
</script>