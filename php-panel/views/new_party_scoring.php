<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// Basitleştirilmiş, doğrudan çalışan puanlama SQL'i
$sql_party_scoring = "-- Basit ve doğrudan çalışan parti puanlama sorgusu
-- 1) Önce tüm partilerin puanlarını sıfırla
UPDATE political_parties SET score = 0;

-- 2) Şehirlerin çözüm oranlarını hesapla
UPDATE cities c
SET solution_rate = (
    CASE 
        WHEN (COALESCE(c.total_complaints, 0) + COALESCE(c.thanks_count, 0)) = 0 THEN 0
        ELSE ((COALESCE(c.solved_complaints, 0) + COALESCE(c.thanks_count, 0)) * 100.0 / 
              (COALESCE(c.total_complaints, 0) + COALESCE(c.thanks_count, 0)))
    END
);

-- 3) Şimdi partilerin ortalama çözüm oranlarını hesapla
WITH party_solution_rates AS (
    SELECT 
        pp.id AS party_id,
        pp.name AS party_name,
        COALESCE(AVG(c.solution_rate), 0) AS avg_solution_rate,
        COUNT(c.id) AS city_count
    FROM 
        political_parties pp
    LEFT JOIN 
        cities c ON c.political_party_id = pp.id
    GROUP BY 
        pp.id, pp.name
)
-- 4) Puanları partilere dağıt - en yüksek oranlı parti 100 puan alır, diğerleri orantılı olarak azalır
UPDATE political_parties pp
SET score = (
    SELECT
        CASE
            -- Eğer hesaplanmış çözüm oranı varsa ve sıfırdan büyükse
            WHEN psr.avg_solution_rate > 0 THEN
                -- Puanı, maksimum çözüm oranına göre orantılı olarak hesapla
                (psr.avg_solution_rate * 100.0) / 
                (SELECT MAX(avg_solution_rate) FROM party_solution_rates WHERE avg_solution_rate > 0)
            ELSE 0
        END
    FROM
        party_solution_rates psr
    WHERE
        psr.party_id = pp.id
);";
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Basitleştirilmiş Parti Puanlama Sistemi</h5>
    </div>
    <div class="card-body">
        <div class="alert alert-info">
            <p><strong>Bilgi:</strong> Bu sayfa, parti puanlama sistemi için basitleştirilmiş bir SQL sorgusu sunar.</p>
            <p>Bu sorgu, partilerin çözüm oranlarını hesaplar ve en yüksek çözüm oranlı partiye 100 puan verir. Diğer partiler orantılı olarak daha düşük puan alır.</p>
            <p>Örnek: A partisi %80 çözüm oranına, B partisi %40 çözüm oranına sahipse, A partisi 100 puan alırken B partisi 50 puan alır.</p>
        </div>
        
        <div class="card">
            <div class="card-header">
                Parti Puanlama SQL'i (Basit ve Direkt Çalışan)
            </div>
            <div class="card-body">
                <pre class="p-3 bg-light"><code><?php echo htmlspecialchars($sql_party_scoring); ?></code></pre>
                <button class="btn btn-sm btn-primary copyBtn" id="copySqlBtn">
                    <i class="fas fa-copy me-1"></i> Kopyala
                </button>
            </div>
        </div>
        
        <div class="mt-4">
            <p>Talimatlar:</p>
            <ol>
                <li>Yukarıdaki SQL kodunu kopyalayın</li>
                <li>Supabase SQL Editörü'nde yapıştırın ve çalıştırın</li>
                <li>Bu sorgu, çözüm oranına göre partilere puan verecektir</li>
                <li>Hiç şikayet çözmemiş veya çözüm oranı 0 olan partiler 0 puan alacaktır</li>
                <li>En yüksek çözüm oranlı parti 100 puan alacak, diğerleri orantılı olarak daha düşük puan alacaktır</li>
            </ol>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Kopyalama düğmesini ayarla
    const copyBtn = document.getElementById('copySqlBtn');
    const sqlContent = `<?php echo str_replace("`", "\\`", str_replace("\\", "\\\\", $sql_party_scoring)); ?>`;
    
    copyBtn.addEventListener('click', function() {
        // Panoya kopyala
        const textArea = document.createElement('textarea');
        textArea.value = sqlContent;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
        
        // Düğme metnini geçici olarak değiştir
        const originalHTML = this.innerHTML;
        this.innerHTML = '<i class="fas fa-check me-1"></i> Kopyalandı!';
        
        // Düğmeyi eski haline getir
        setTimeout(() => {
            this.innerHTML = originalHTML;
        }, 2000);
    });
});
</script>