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
WITH city_groups AS (
    -- Şehirleri büyükşehir olma durumuna göre grupla
    SELECT 
        id,
        political_party_id,
        total_complaints,
        solved_complaints,
        thanks_count,
        is_metropolitan
    FROM 
        cities
    WHERE 
        political_party_id IS NOT NULL
),
city_party_stats AS (
    -- Sadece büyükşehir olan şehirlerden toplanan istatistikler
    SELECT 
        c.political_party_id,
        SUM(COALESCE(c.total_complaints, 0)) AS total_city_complaints,
        SUM(COALESCE(c.solved_complaints, 0)) AS total_city_solved_complaints,
        SUM(COALESCE(c.thanks_count, 0)) AS total_city_thanks
    FROM 
        city_groups c
    WHERE 
        c.is_metropolitan = true
    GROUP BY 
        c.political_party_id
),
normal_city_party_stats AS (
    -- Büyükşehir olmayan şehirlerin istatistikleri - bunlar olduğu gibi kalır
    SELECT 
        c.political_party_id,
        SUM(COALESCE(c.total_complaints, 0)) AS total_normal_city_complaints,
        SUM(COALESCE(c.solved_complaints, 0)) AS total_normal_city_solved_complaints,
        SUM(COALESCE(c.thanks_count, 0)) AS total_normal_city_thanks
    FROM 
        city_groups c
    WHERE 
        c.is_metropolitan = false
    GROUP BY 
        c.political_party_id
),
district_party_stats AS (
    -- İlçelerden toplanan istatistikler - sadece büyükşehirlerdeki ilçeler
    SELECT 
        d.political_party_id,
        SUM(COALESCE(d.total_complaints, 0)) AS total_district_complaints,
        SUM(COALESCE(d.solved_complaints, 0)) AS total_district_solved_complaints,
        SUM(COALESCE(d.thanks_count, 0)) AS total_district_thanks
    FROM 
        districts d
    JOIN 
        cities c ON d.city_id = c.id
    WHERE 
        d.political_party_id IS NOT NULL AND c.is_metropolitan = true
    GROUP BY 
        d.political_party_id
),
normal_district_party_stats AS (
    -- Büyükşehir olmayan ilçelerin istatistikleri
    SELECT 
        d.political_party_id,
        SUM(COALESCE(d.total_complaints, 0)) AS total_normal_district_complaints,
        SUM(COALESCE(d.solved_complaints, 0)) AS total_normal_district_solved_complaints,
        SUM(COALESCE(d.thanks_count, 0)) AS total_normal_district_thanks
    FROM 
        districts d
    JOIN 
        cities c ON d.city_id = c.id
    WHERE 
        d.political_party_id IS NOT NULL AND c.is_metropolitan = false
    GROUP BY 
        d.political_party_id
),
combined_stats AS (
    -- Tüm istatistikleri birleştir
    SELECT 
        p.id AS party_id,
        -- Büyükşehir istatistikleri (50% paylaşım)
        COALESCE(cps.total_city_complaints * 0.5, 0) AS metro_city_complaints,
        COALESCE(cps.total_city_solved_complaints * 0.5, 0) AS metro_city_solved_complaints,
        COALESCE(cps.total_city_thanks * 0.5, 0) AS metro_city_thanks,
        -- Büyükşehirlerdeki ilçe istatistikleri (50% paylaşım)
        COALESCE(dps.total_district_complaints * 0.5, 0) AS metro_district_complaints,
        COALESCE(dps.total_district_solved_complaints * 0.5, 0) AS metro_district_solved_complaints,
        COALESCE(dps.total_district_thanks * 0.5, 0) AS metro_district_thanks,
        -- Normal şehir istatistikleri (tam)
        COALESCE(ncps.total_normal_city_complaints, 0) AS normal_city_complaints,
        COALESCE(ncps.total_normal_city_solved_complaints, 0) AS normal_city_solved_complaints,
        COALESCE(ncps.total_normal_city_thanks, 0) AS normal_city_thanks,
        -- Normal ilçe istatistikleri (tam)
        COALESCE(ndps.total_normal_district_complaints, 0) AS normal_district_complaints,
        COALESCE(ndps.total_normal_district_solved_complaints, 0) AS normal_district_solved_complaints,
        COALESCE(ndps.total_normal_district_thanks, 0) AS normal_district_thanks
    FROM 
        political_parties p
    LEFT JOIN 
        city_party_stats cps ON p.id = cps.political_party_id
    LEFT JOIN 
        district_party_stats dps ON p.id = dps.political_party_id
    LEFT JOIN 
        normal_city_party_stats ncps ON p.id = ncps.political_party_id
    LEFT JOIN 
        normal_district_party_stats ndps ON p.id = ndps.political_party_id
)
-- 4. Adım: Parti istatistiklerini güncelle
UPDATE political_parties pp
SET 
    parti_sikayet_sayisi = CAST(ROUND(
        cs.metro_city_complaints + cs.metro_district_complaints +
        cs.normal_city_complaints + cs.normal_district_complaints
    ) AS INTEGER),
    parti_cozulmus_sikayet_sayisi = CAST(ROUND(
        cs.metro_city_solved_complaints + cs.metro_district_solved_complaints +
        cs.normal_city_solved_complaints + cs.normal_district_solved_complaints
    ) AS INTEGER),
    parti_tesekkur_sayisi = CAST(ROUND(
        cs.metro_city_thanks + cs.metro_district_thanks +
        cs.normal_city_thanks + cs.normal_district_thanks
    ) AS INTEGER)
FROM 
    combined_stats cs
WHERE 
    pp.id = cs.party_id;

-- 5. Adım: Partilerin puanlarını toplam sayılara göre hesapla (100 puana oranlayarak)
WITH party_counts AS (
    -- Her bir partinin sayılarını al
    SELECT 
        id,
        name,
        parti_cozulmus_sikayet_sayisi,
        parti_tesekkur_sayisi,
        -- Parti başarı puanı (çözülmüş şikayetler + teşekkürler)
        (COALESCE(parti_cozulmus_sikayet_sayisi, 0) + COALESCE(parti_tesekkur_sayisi, 0)) AS success_count
    FROM 
        political_parties
),
total_counts AS (
    -- Tüm partilerin toplam başarı sayısını hesapla
    SELECT 
        SUM(success_count) AS total_success_count
    FROM 
        party_counts
    WHERE 
        success_count > 0
),
party_scores AS (
    -- 100 puanı tüm partilerin başarı sayılarına göre orantılı dağıt
    SELECT 
        id,
        name,
        success_count,
        CASE
            -- Eğer toplam başarı sayısı sıfırsa kimseye puan verme
            WHEN (SELECT total_success_count FROM total_counts) = 0 THEN 0
            -- Değilse puanı başarı sayısına göre dağıt (toplam 100 puan)
            ELSE (success_count * 100.0) / (SELECT total_success_count FROM total_counts)
        END AS final_score
    FROM 
        party_counts
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