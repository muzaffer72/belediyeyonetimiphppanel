<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// Tabloları kontrol et
$tables = ['cities', 'districts', 'political_parties', 'posts'];
$schemas = [];

foreach ($tables as $table) {
    // Tablonun ilk kaydını al - sadece sütun isimlerini görmek için
    $result = getData($table, ['limit' => 1]);
    
    if (!$result['error'] && !empty($result['data'])) {
        $schemas[$table] = [
            'columns' => array_keys($result['data'][0]),
            'sample' => $result['data'][0]
        ];
    } else {
        $schemas[$table] = [
            'error' => true,
            'message' => 'Tabloya erişilemedi veya tablo boş'
        ];
    }
}

// SQL şablonları
$sql_templates = [
    'disable_triggers' => "-- Mevcut tüm triggerları devre dışı bırak
DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;

-- Trigger fonksiyonlarını da kaldır
DROP FUNCTION IF EXISTS calculate_solution_rate_percentage();
DROP FUNCTION IF EXISTS update_solution_rates_and_scores();
DROP FUNCTION IF EXISTS recalculate_all_party_scores();
DROP FUNCTION IF EXISTS update_party_scores();",
    
    'party_scoring' => "-- Tüm partilerin puanlarını sıfırla
UPDATE political_parties SET score = 0;

-- Şehirlerin çözüm oranlarını hesapla - FORMÜL: (Çözülmüş Şikayet + Teşekkür) / (Toplam Şikayet + Teşekkür) * 100
UPDATE cities c
SET solution_rate = (
    CASE 
        WHEN (COALESCE(c.total_complaints, 0) + COALESCE(c.thanks_count, 0)) = 0 THEN 0
        ELSE ((COALESCE(c.solved_complaints, 0) + COALESCE(c.thanks_count, 0)) * 100.0 / 
              (COALESCE(c.total_complaints, 0) + COALESCE(c.thanks_count, 0)))
    END
);

-- İlçelerin çözüm oranlarını hesapla - aynı formülle
UPDATE districts d
SET solution_rate = (
    CASE 
        WHEN (COALESCE(d.total_complaints, 0) + COALESCE(d.thanks_count, 0)) = 0 THEN 0
        ELSE ((COALESCE(d.solved_complaints, 0) + COALESCE(d.thanks_count, 0)) * 100.0 / 
              (COALESCE(d.total_complaints, 0) + COALESCE(d.thanks_count, 0)))
    END
);

-- Partilerin şehirlerdeki ortalama çözüm oranını hesapla
WITH city_party_rates AS (
    SELECT 
        pp.id AS party_id,
        pp.name AS party_name,
        COALESCE(AVG(c.solution_rate), 0) AS avg_solution_rate,
        SUM(COALESCE(c.solved_complaints, 0)) AS total_solved_complaints,
        SUM(COALESCE(c.total_complaints, 0)) AS total_total_complaints,
        SUM(COALESCE(c.thanks_count, 0)) AS total_thanks_count
    FROM 
        political_parties pp
    LEFT JOIN 
        cities c ON c.political_party_id = pp.id
    GROUP BY 
        pp.id, pp.name
),
-- Partileri çözüm oranına göre sırala ve 0 çözüm oranı olanları filtrele
ranked_parties AS (
    SELECT 
        party_id,
        party_name,
        avg_solution_rate,
        -- Şikayet çözmemiş belediyelere 0 puan vermek için kontrol
        CASE 
            WHEN total_solved_complaints = 0 AND total_thanks_count = 0 THEN 0
            ELSE avg_solution_rate 
        END AS effective_solution_rate,
        RANK() OVER (ORDER BY 
            CASE 
                WHEN total_solved_complaints = 0 AND total_thanks_count = 0 THEN 0
                ELSE avg_solution_rate 
            END DESC
        ) AS rank
    FROM 
        city_party_rates
),
-- Çözüm yapmamış partileri filtrele - sadece puanı hak eden partiler
scoring_parties AS (
    SELECT * FROM ranked_parties
    WHERE effective_solution_rate > 0
),
-- Puanlamayı sadece skor hak eden partiler üzerinden yap
party_scores AS (
    SELECT 
        party_id,
        party_name,
        effective_solution_rate,
        rank,
        -- Toplam parti sayısını bul
        COUNT(*) OVER () AS valid_party_count,
        -- Aynı rank'teki parti sayısını bul
        COUNT(*) OVER (PARTITION BY rank) AS same_rank_count,
        -- Toplam puanı 100 olarak belirle
        100.0 AS total_points
    FROM 
        scoring_parties
),
-- Her partinin puanını belirli bir formüle göre hesapla
final_scores AS (
    SELECT 
        party_id,
        party_name,
        effective_solution_rate,
        rank,
        -- Sıralama bazlı puanlama yöntemi (1. sıra 100 puan, 2. sıra 90 puan vb.)
        CASE
            -- Eğer skor hak eden parti yoksa, kimseye puan verme
            WHEN valid_party_count = 0 THEN 0
            -- Her sıra için belirli bir puan (her sıra düşüşünde 10 puan azalt)
            ELSE (100 - ((rank - 1) * (100 / GREATEST(valid_party_count, 1)))) / same_rank_count
        END AS final_score
    FROM 
        party_scores
)
-- Puanları political_parties tablosuna güncelle
UPDATE political_parties pp
SET score = (
    SELECT fs.final_score
    FROM final_scores fs
    WHERE fs.party_id = pp.id
);"
];

// Mevcut sütunlar için SQL'i uyarla
foreach ($tables as $table) {
    if (!isset($schemas[$table]['error'])) {
        $columns = $schemas[$table]['columns'];
        
        // 'cities' tablosu için çözüm oranını hesaplama
        if ($table === 'cities') {
            $has_total_complaints = in_array('total_complaints', $columns);
            $has_solved_complaints = in_array('solved_complaints', $columns);
            $has_thanks_count = in_array('thanks_count', $columns);
            $has_solution_rate = in_array('solution_rate', $columns);
            
            if (!$has_total_complaints || !$has_solved_complaints || !$has_thanks_count || !$has_solution_rate) {
                // Sütunlar eksikse, SQL şablonunu güncelle
                $sql_templates['party_scoring'] = str_replace(
                    "-- Şehirlerin çözüm oranlarını hesapla (total_complaints, solved_complaints, thanks_count değerlerine göre)",
                    "-- NOT: 'cities' tablosunda gerekli sütunlar bulunamadı. Bu kısım atlanabilir.",
                    $sql_templates['party_scoring']
                );
            }
        }
        
        // 'districts' tablosu için çözüm oranını hesaplama
        if ($table === 'districts') {
            $has_total_complaints = in_array('total_complaints', $columns);
            $has_solved_complaints = in_array('solved_complaints', $columns);
            $has_thanks_count = in_array('thanks_count', $columns);
            $has_solution_rate = in_array('solution_rate', $columns);
            
            if (!$has_total_complaints || !$has_solved_complaints || !$has_thanks_count || !$has_solution_rate) {
                // Sütunlar eksikse, SQL şablonunu güncelle
                $sql_templates['party_scoring'] = str_replace(
                    "-- İlçelerin çözüm oranlarını hesapla (otomatik olarak ilçe bazında çözüm oranı hesaplanması gerekiyorsa)",
                    "-- NOT: 'districts' tablosunda gerekli sütunlar bulunamadı. Bu kısım atlanabilir.",
                    $sql_templates['party_scoring']
                );
            }
        }
        
        // 'political_parties' tablosu için skor sütunu kontrolü
        if ($table === 'political_parties') {
            $has_score = in_array('score', $columns);
            
            if (!$has_score) {
                // Sütunlar eksikse, SQL şablonunu güncelle
                $sql_templates['party_scoring'] = str_replace(
                    "-- Tüm partilerin puanlarını sıfırla",
                    "-- NOT: 'political_parties' tablosunda 'score' sütunu bulunamadı. Bu kısım atlanabilir.",
                    $sql_templates['party_scoring']
                );
            }
        }
    }
}

// Seçilen SQL'i al
$selected_sql = isset($_GET['sql']) ? $_GET['sql'] : 'disable_triggers';
$sql_content = isset($sql_templates[$selected_sql]) ? $sql_templates[$selected_sql] : '';
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">SQL Sorguları</h5>
    </div>
    <div class="card-body">
        <div class="alert alert-info">
            <p><strong>Bilgi:</strong> Bu sayfa, veritabanı işlemleri için özelleştirilmiş SQL sorgularını gösterir.</p>
            <p>İhtiyacınıza göre bir SQL şablonu seçin ve Supabase SQL Editörü'nde çalıştırın.</p>
        </div>
        
        <div class="mb-4">
            <h6>SQL Şablonu Seçin:</h6>
            <div class="btn-group" role="group">
                <a href="?page=custom_sql&sql=disable_triggers" class="btn btn-<?php echo $selected_sql === 'disable_triggers' ? 'primary' : 'outline-primary'; ?>">
                    Triggerları Kaldır
                </a>
                <a href="?page=custom_sql&sql=party_scoring" class="btn btn-<?php echo $selected_sql === 'party_scoring' ? 'primary' : 'outline-primary'; ?>">
                    Parti Puanlama
                </a>
            </div>
        </div>
        
        <div class="card">
            <div class="card-header">
                <?php if ($selected_sql === 'disable_triggers'): ?>
                    Triggerları Kaldırma SQL'i
                <?php elseif ($selected_sql === 'party_scoring'): ?>
                    Parti Puanlama SQL'i (total_complaints, solved_complaints, thanks_count değerlerine göre)
                <?php else: ?>
                    SQL Kodu
                <?php endif; ?>
            </div>
            <div class="card-body">
                <pre class="p-3 bg-light"><code><?php echo htmlspecialchars($sql_content); ?></code></pre>
                <button class="btn btn-sm btn-primary copyBtn" id="copySqlBtn">
                    <i class="fas fa-copy me-1"></i> Kopyala
                </button>
            </div>
        </div>
        
        <div class="mt-4">
            <h6>Tablo Sütunları:</h6>
            <div class="accordion" id="schemaAccordion">
                <?php foreach ($tables as $table): ?>
                <div class="accordion-item">
                    <h2 class="accordion-header" id="heading<?php echo ucfirst($table); ?>">
                        <button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapse<?php echo ucfirst($table); ?>" aria-expanded="false" aria-controls="collapse<?php echo ucfirst($table); ?>">
                            <?php echo $table; ?> Tablosu
                        </button>
                    </h2>
                    <div id="collapse<?php echo ucfirst($table); ?>" class="accordion-collapse collapse" aria-labelledby="heading<?php echo ucfirst($table); ?>" data-bs-parent="#schemaAccordion">
                        <div class="accordion-body">
                            <?php if (isset($schemas[$table]['error'])): ?>
                                <div class="alert alert-warning">
                                    <?php echo $schemas[$table]['message']; ?>
                                </div>
                            <?php else: ?>
                                <h6>Sütunlar:</h6>
                                <ul>
                                    <?php foreach ($schemas[$table]['columns'] as $column): ?>
                                        <li><?php echo $column; ?></li>
                                    <?php endforeach; ?>
                                </ul>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
                <?php endforeach; ?>
            </div>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Kopyalama düğmesini ayarla
    const copyBtn = document.getElementById('copySqlBtn');
    const sqlContent = `<?php echo str_replace("`", "\\`", str_replace("\\", "\\\\", $sql_content)); ?>`;
    
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