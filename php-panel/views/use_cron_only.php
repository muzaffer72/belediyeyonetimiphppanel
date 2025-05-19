<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

$sql_file_path = __DIR__ . '/../sql/disable_all_triggers.sql';
$sql_content = file_exists($sql_file_path) ? file_get_contents($sql_file_path) : '';
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Triggerlarsız Sadece Cron Yaklaşımı</h5>
    </div>
    <div class="card-body">
        <div class="alert alert-success">
            <h6><i class="fas fa-check-circle me-2"></i> En Güvenilir Çözüm: Sadece Cron</h6>
            <p>Triggerlar bazen sorunlara neden olabilir. En güvenilir yaklaşım, tüm triggerları kaldırıp puanlamayı sadece cron ile yapmaktır:</p>
            <ul>
                <li><strong>Tüm triggerları kaldırır:</strong> Gönderi paylaşımında yaşanan sorunları tamamen ortadan kaldırır</li>
                <li><strong>Günlük cron ayarlar:</strong> Parti puanları her gün otomatik olarak güncellenecektir</li>
                <li><strong>Aynı formülü kullanır:</strong> Büyükşehir ve normal şehirlerin doğru hesaplanması, 100 puanın orantılı dağıtılması</li>
            </ul>
        </div>
        
        <div class="card mb-3">
            <div class="card-header bg-primary text-white">
                <h6 class="mb-0">Triggerları Kaldır, Cron Kur SQL Kodu</h6>
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
                <li>Artık gönderi paylaşımı sorunsuz çalışacak ve parti puanları her gün güncellenecektir</li>
            </ol>
            <p><strong>Not:</strong> Bu çözüm tüm sorunlu triggerları kaldırır ve sadece günlük cron işlemiyle puanlamayı yapar. Böylece sistem daha kararlı çalışır.</p>
        </div>
        
        <div class="alert alert-secondary mt-3">
            <h6><i class="fas fa-wrench me-2"></i> Manuel Güncelleme</h6>
            <p>Parti puanlarını manuel olarak güncellemek isterseniz, aşağıdaki SQL komutunu çalıştırabilirsiniz:</p>
            <pre class="p-3 bg-light"><code>SELECT cron_update_party_scores();</code></pre>
            <button class="btn btn-sm btn-secondary" id="copyManualBtn">
                <i class="fas fa-copy me-1"></i> Kopyala
            </button>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Kopyalama düğmelerini ayarla
    document.getElementById('copyBtn').addEventListener('click', function() {
        const code = document.querySelector('.card-body pre code').textContent;
        copyToClipboard(code);
        this.innerHTML = '<i class="fas fa-check me-1"></i> Kopyalandı!';
        setTimeout(() => {
            this.innerHTML = '<i class="fas fa-copy me-1"></i> Kopyala';
        }, 2000);
    });
    
    document.getElementById('copyManualBtn').addEventListener('click', function() {
        const code = document.querySelectorAll('.card-body pre code')[1].textContent;
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