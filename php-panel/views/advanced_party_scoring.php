<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// SQL sorgusunu hazırla - advanced party scoring
$sql_advanced_party_scoring = "-- 1. Adım: political_parties tablosuna yeni sütunları ekle (eğer yoksa)
DO $$ 
BEGIN
    -- Parti toplam şikayet sayısı sütunu
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'political_parties' AND column_name = 'parti_sikayet_sayisi') THEN
        ALTER TABLE political_parties ADD COLUMN parti_sikayet_sayisi INTEGER DEFAULT 0;
    END IF;
    
    -- Parti çözülmüş şikayet sayısı sütunu
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'political_parties' AND column_name = 'parti_cozulmus_sikayet_sayisi') THEN
        ALTER TABLE political_parties ADD COLUMN parti_cozulmus_sikayet_sayisi INTEGER DEFAULT 0;
    END IF;
    
    -- Parti teşekkür sayısı sütunu
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'political_parties' AND column_name = 'parti_tesekkur_sayisi') THEN
        ALTER TABLE political_parties ADD COLUMN parti_tesekkur_sayisi INTEGER DEFAULT 0;
    END IF;
END $$;

-- 2. Adım: Tüm partilerin istatistiklerini sıfırla
UPDATE political_parties
SET 
    parti_sikayet_sayisi = 0,
    parti_cozulmus_sikayet_sayisi = 0,
    parti_tesekkur_sayisi = 0,
    score = 0;

-- 3. Adım: Şehir ve ilçelerden toplamları hesaplayarak partilere dağıt
WITH city_party_stats AS (
    -- Şehirlerden toplanan istatistikler
    SELECT 
        c.political_party_id,
        SUM(COALESCE(c.total_complaints, 0)) AS total_city_complaints,
        SUM(COALESCE(c.solved_complaints, 0)) AS total_city_solved_complaints,
        SUM(COALESCE(c.thanks_count, 0)) AS total_city_thanks,
        -- Büyükşehir belediyeleri için ilçelerle paylaşım faktörü
        CASE 
            WHEN COUNT(CASE WHEN c.is_metropolitan = true THEN 1 END) > 0 THEN 0.5
            ELSE 1.0
        END AS city_share_factor
    FROM 
        cities c
    WHERE 
        c.political_party_id IS NOT NULL
    GROUP BY 
        c.political_party_id
),
district_party_stats AS (
    -- İlçelerden toplanan istatistikler
    SELECT 
        d.political_party_id,
        SUM(COALESCE(d.total_complaints, 0)) AS total_district_complaints,
        SUM(COALESCE(d.solved_complaints, 0)) AS total_district_solved_complaints,
        SUM(COALESCE(d.thanks_count, 0)) AS total_district_thanks,
        -- İlçelerin büyükşehirlerde paylaşım faktörü
        0.5 AS district_share_factor
    FROM 
        districts d
    JOIN 
        cities c ON d.city_id = c.id
    WHERE 
        d.political_party_id IS NOT NULL AND c.is_metropolitan = true
    GROUP BY 
        d.political_party_id
),
combined_stats AS (
    -- Şehir ve ilçe istatistiklerini birleştir
    SELECT 
        COALESCE(cps.political_party_id, dps.political_party_id) AS party_id,
        -- Şehir istatistikleri (büyükşehir faktörü ile)
        COALESCE(cps.total_city_complaints * cps.city_share_factor, 0) AS city_complaints,
        COALESCE(cps.total_city_solved_complaints * cps.city_share_factor, 0) AS city_solved_complaints,
        COALESCE(cps.total_city_thanks * cps.city_share_factor, 0) AS city_thanks,
        -- İlçe istatistikleri (büyükşehirde)
        COALESCE(dps.total_district_complaints * dps.district_share_factor, 0) AS district_complaints,
        COALESCE(dps.total_district_solved_complaints * dps.district_share_factor, 0) AS district_solved_complaints,
        COALESCE(dps.total_district_thanks * dps.district_share_factor, 0) AS district_thanks
    FROM 
        city_party_stats cps
    FULL OUTER JOIN 
        district_party_stats dps ON cps.political_party_id = dps.political_party_id
)
-- 4. Adım: Parti istatistiklerini güncelle
UPDATE political_parties pp
SET 
    parti_sikayet_sayisi = CAST(ROUND(cs.city_complaints + cs.district_complaints) AS INTEGER),
    parti_cozulmus_sikayet_sayisi = CAST(ROUND(cs.city_solved_complaints + cs.district_solved_complaints) AS INTEGER),
    parti_tesekkur_sayisi = CAST(ROUND(cs.city_thanks + cs.district_thanks) AS INTEGER)
FROM 
    combined_stats cs
WHERE 
    pp.id = cs.party_id;

-- 5. Adım: Partilerin çözüm oranlarını hesapla
WITH party_solution_rates AS (
    SELECT 
        id,
        name,
        parti_sikayet_sayisi,
        parti_cozulmus_sikayet_sayisi,
        parti_tesekkur_sayisi,
        -- Çözüm oranı: (Çözülmüş Şikayet + Teşekkür) / (Toplam Şikayet + Teşekkür) * 100
        CASE 
            WHEN (COALESCE(parti_sikayet_sayisi, 0) + COALESCE(parti_tesekkur_sayisi, 0)) = 0 THEN 0
            ELSE ((COALESCE(parti_cozulmus_sikayet_sayisi, 0) + COALESCE(parti_tesekkur_sayisi, 0)) * 100.0 / 
                  (COALESCE(parti_sikayet_sayisi, 0) + COALESCE(parti_tesekkur_sayisi, 0)))
        END AS solution_rate
    FROM 
        political_parties
),
ranked_parties AS (
    -- Partileri çözüm oranına göre sırala
    SELECT 
        id,
        name,
        solution_rate,
        -- Performansı sıfırdan yüksek olan partilerin toplam sayısı
        SUM(CASE WHEN solution_rate > 0 THEN 1 ELSE 0 END) OVER() AS valid_party_count
    FROM 
        party_solution_rates
),
party_scores AS (
    -- 100 puanı performansa göre dağıt
    SELECT 
        id,
        name,
        solution_rate,
        CASE
            -- Performansı olan partiler içinde puanı dağıt
            WHEN solution_rate > 0 AND valid_party_count > 0 THEN
                (solution_rate * 100.0) / (SELECT MAX(solution_rate) FROM ranked_parties WHERE solution_rate > 0)
            ELSE 0
        END AS final_score
    FROM 
        ranked_parties
)
-- 6. Adım: Puanları güncelle
UPDATE political_parties pp
SET score = ps.final_score
FROM party_scores ps
WHERE pp.id = ps.id;";
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Gelişmiş Parti Puanlama Sistemi</h5>
    </div>
    <div class="card-body">
        <div class="alert alert-info">
            <p><strong>Gelişmiş Puanlama Sistemi:</strong> Bu yöntem, partilerin tüm şehir ve ilçelerinden toplanan şikayet ve teşekkür verilerini hesaba katar.</p>
            <p><strong>Büyükşehir Özelliği:</strong> Büyükşehir belediyelerinde, puanlar büyükşehir ve ilçe belediyeleri arasında %50-%50 olarak paylaştırılır.</p>
            <p><strong>Hesaplama:</strong> Her parti için (Çözülmüş Şikayet + Teşekkür) / (Toplam Şikayet + Teşekkür) * 100 formülü kullanılır. En yüksek çözüm oranlı parti 100 puan alır, diğerleri orantılı olarak puan alır.</p>
            <p><strong>Eşitlik Durumu:</strong> Aynı çözüm oranına sahip partiler aynı puanı alır.</p>
        </div>
        
        <div class="card">
            <div class="card-header">
                Gelişmiş Parti Puanlama SQL'i
            </div>
            <div class="card-body">
                <pre class="p-3 bg-light"><code><?php echo htmlspecialchars($sql_advanced_party_scoring); ?></code></pre>
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
                <li>Bu sorgu, political_parties tablosuna yeni sütunlar ekleyecek ve parti puanlarını güncelleyecektir</li>
                <li>Büyükşehir belediyeleri için istatistikler %50-%50 paylaştırılacaktır</li>
                <li>En yüksek çözüm oranlı parti 100 puan alacak, diğerleri orantılı olarak daha düşük puan alacaktır</li>
                <li>Hiç şikayet çözmemiş veya çözüm oranı sıfır olan partiler 0 puan alacaktır</li>
            </ol>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Kopyalama düğmesini ayarla
    const copyBtn = document.getElementById('copySqlBtn');
    const sqlContent = `<?php echo str_replace("`", "\\`", str_replace("\\", "\\\\", $sql_advanced_party_scoring)); ?>`;
    
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