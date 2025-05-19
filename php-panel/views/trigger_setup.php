<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

$sql_file_path = __DIR__ . '/../sql/create_party_score_trigger.sql';
$sql_content = file_exists($sql_file_path) ? file_get_contents($sql_file_path) : '';
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Supabase Trigger Kurulumu</h5>
    </div>
    <div class="card-body">
        <div class="alert alert-info">
            <h6><i class="fas fa-info-circle me-2"></i> Otomatik Puanlama Sistemi</h6>
            <p>Bu trigger sistemi, şehir, ilçe veya postlardaki değişikliklerde otomatik olarak parti puanlarını hesaplayacaktır.</p>
            <p>Kurulum için aşağıdaki SQL kodunu Supabase SQL Editör'ünde çalıştırmanız yeterlidir:</p>
            <ol>
                <li>Supabase projenizin dashboard'ına giriş yapın</li>
                <li>SQL Editör'ü açın</li>
                <li>Aşağıdaki SQL kodunu kopyalayın ve yapıştırın</li>
                <li>Kodu çalıştırın</li>
            </ol>
        </div>
        
        <div class="card">
            <div class="card-header">
                <h6 class="mb-0">Trigger ve Cron Kurulum SQL Kodu</h6>
            </div>
            <div class="card-body">
                <pre class="p-3 bg-light"><code><?php echo htmlspecialchars($sql_content); ?></code></pre>
                <button class="btn btn-sm btn-primary" id="copyBtn">
                    <i class="fas fa-copy me-1"></i> Kopyala
                </button>
            </div>
        </div>
        
        <div class="mt-4">
            <h6>Kurulum Sonrası Nasıl Çalışır?</h6>
            <p>Bu kurulum sonrasında:</p>
            <ol>
                <li><strong>Otomatik Tetikleme:</strong> Şehir, ilçe veya post verilerindeki herhangi bir değişiklik otomatik olarak puanlamayı güncelleyecektir.</li>
                <li><strong>Cron Seçeneği:</strong> Ayrıca Supabase'in cron özelliğini kullanarak tüm puanları düzenli aralıklarla güncelleyebilirsiniz.</li>
            </ol>
            
            <h6>Supabase Cron Ayarı</h6>
            <p>Supabase'de cron ayarlamak için:</p>
            <ol>
                <li>Supabase projenizin dashboard'ına giriş yapın</li>
                <li>SQL Editör'ü açın</li>
                <li>Aşağıdaki SQL kodunu çalıştırın:</li>
            </ol>
            <pre class="p-3 bg-light"><code>-- Günde bir kez (her gece yarısı) puanları güncelle
SELECT cron.schedule(
  'update-party-scores-daily',
  '0 0 * * *',
  $$SELECT cron_update_party_scores()$$
);</code></pre>
            <button class="btn btn-sm btn-primary" id="copyCronBtn">
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
    
    document.getElementById('copyCronBtn').addEventListener('click', function() {
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