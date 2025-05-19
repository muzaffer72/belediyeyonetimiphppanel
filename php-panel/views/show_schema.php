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

// Parti puanlama için özel SQL
$party_scoring_sql = '';
$disable_triggers_sql = '';

if (!empty($schemas['cities']) && !empty($schemas['districts']) && !empty($schemas['political_parties'])) {
    // Şema bilgilerini kullanarak SQL hazırla
    $city_cols = $schemas['cities']['columns'];
    $district_cols = $schemas['districts']['columns'];
    $party_cols = $schemas['political_parties']['columns'];
    
    // Sütunların var olup olmadığını kontrol et
    $has_solution_rate_city = in_array('solution_rate', $city_cols);
    $has_solution_rate_district = in_array('solution_rate', $district_cols);
    $has_score_party = in_array('score', $party_cols);
    
    // SQL sorgusunu oluştur - sadece mevcut sütunlara göre
    if ($has_score_party) {
        $party_scoring_sql .= "-- Tüm partilerin puanlarını sıfırla\n";
        $party_scoring_sql .= "UPDATE political_parties SET score = 0;\n\n";
    }
    
    // Şehir ve ilçelerin çözüm oranlarını hesapla
    // Posts tablosuna bakarak toplam ve çözülen post sayılarını hesapla
    $party_scoring_sql .= "-- Şehirlerin çözüm oranlarını hesapla\n";
    if ($has_solution_rate_city) {
        $party_scoring_sql .= "UPDATE cities c\n";
        $party_scoring_sql .= "SET solution_rate = (\n";
        $party_scoring_sql .= "    SELECT \n";
        $party_scoring_sql .= "    CASE \n";
        $party_scoring_sql .= "        WHEN COUNT(*) = 0 THEN 0\n";
        $party_scoring_sql .= "        ELSE (COUNT(CASE WHEN p.is_resolved = true THEN 1 END) * 100.0 / COUNT(*))\n";
        $party_scoring_sql .= "    END\n";
        $party_scoring_sql .= "    FROM posts p\n";
        $party_scoring_sql .= "    WHERE p.city_id = c.id\n";
        $party_scoring_sql .= ");\n\n";
    }
    
    // İlçelerin çözüm oranlarını hesapla
    if ($has_solution_rate_district) {
        $party_scoring_sql .= "-- İlçelerin çözüm oranlarını hesapla\n";
        $party_scoring_sql .= "UPDATE districts d\n";
        $party_scoring_sql .= "SET solution_rate = (\n";
        $party_scoring_sql .= "    SELECT \n";
        $party_scoring_sql .= "    CASE \n";
        $party_scoring_sql .= "        WHEN COUNT(*) = 0 THEN 0\n";
        $party_scoring_sql .= "        ELSE (COUNT(CASE WHEN p.is_resolved = true THEN 1 END) * 100.0 / COUNT(*))\n";
        $party_scoring_sql .= "    END\n";
        $party_scoring_sql .= "    FROM posts p\n";
        $party_scoring_sql .= "    WHERE p.district_id = d.id\n";
        $party_scoring_sql .= ");\n\n";
    }
    
    // Parti puanlaması - 100 üzerinden orantılı hesaplama
    if ($has_score_party && $has_solution_rate_city) {
        $party_scoring_sql .= "-- Partileri çözüm oranlarına göre sırala ve puanla\n";
        $party_scoring_sql .= "WITH ranked_parties AS (\n";
        $party_scoring_sql .= "    SELECT \n";
        $party_scoring_sql .= "        pp.id,\n";
        $party_scoring_sql .= "        pp.name,\n";
        $party_scoring_sql .= "        COALESCE(AVG(c.solution_rate), 0) AS avg_solution_rate,\n";
        $party_scoring_sql .= "        ROW_NUMBER() OVER (ORDER BY COALESCE(AVG(c.solution_rate), 0) DESC) AS rank\n";
        $party_scoring_sql .= "    FROM \n";
        $party_scoring_sql .= "        political_parties pp\n";
        $party_scoring_sql .= "    LEFT JOIN \n";
        $party_scoring_sql .= "        cities c ON c.political_party_id = pp.id\n";
        $party_scoring_sql .= "    GROUP BY \n";
        $party_scoring_sql .= "        pp.id, pp.name\n";
        $party_scoring_sql .= "),\n";
        $party_scoring_sql .= "party_ranks AS (\n";
        $party_scoring_sql .= "    SELECT \n";
        $party_scoring_sql .= "        id, \n";
        $party_scoring_sql .= "        name,\n";
        $party_scoring_sql .= "        avg_solution_rate,\n";
        $party_scoring_sql .= "        rank,\n";
        $party_scoring_sql .= "        COUNT(*) OVER (PARTITION BY avg_solution_rate) AS equal_rank_count,\n";
        $party_scoring_sql .= "        SUM(1) OVER () AS total_parties\n";
        $party_scoring_sql .= "    FROM \n";
        $party_scoring_sql .= "        ranked_parties\n";
        $party_scoring_sql .= ")\n";
        $party_scoring_sql .= "UPDATE political_parties pp\n";
        $party_scoring_sql .= "SET score = (\n";
        $party_scoring_sql .= "    SELECT \n";
        $party_scoring_sql .= "        CASE \n";
        $party_scoring_sql .= "            WHEN pr.avg_solution_rate = 0 THEN 0\n";
        $party_scoring_sql .= "            ELSE (100.0 / pr.total_parties) * \n";
        $party_scoring_sql .= "                 (pr.total_parties - pr.rank + 1) / \n";
        $party_scoring_sql .= "                 pr.equal_rank_count\n";
        $party_scoring_sql .= "        END\n";
        $party_scoring_sql .= "    FROM \n";
        $party_scoring_sql .= "        party_ranks pr\n";
        $party_scoring_sql .= "    WHERE \n";
        $party_scoring_sql .= "        pr.id = pp.id\n";
        $party_scoring_sql .= ");\n";
    }
    
    // Triggerları kaldırma SQL'i
    $disable_triggers_sql .= "-- Mevcut tüm triggerları devre dışı bırak\n";
    $disable_triggers_sql .= "DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;\n";
    $disable_triggers_sql .= "DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;\n";
    $disable_triggers_sql .= "DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;\n";
    $disable_triggers_sql .= "DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;\n\n";
    $disable_triggers_sql .= "-- Trigger fonksiyonlarını da kaldır\n";
    $disable_triggers_sql .= "DROP FUNCTION IF EXISTS calculate_solution_rate_percentage();\n";
    $disable_triggers_sql .= "DROP FUNCTION IF EXISTS update_solution_rates_and_scores();\n";
    $disable_triggers_sql .= "DROP FUNCTION IF EXISTS recalculate_all_party_scores();\n";
    $disable_triggers_sql .= "DROP FUNCTION IF EXISTS update_party_scores();\n";
}
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Veritabanı Şeması ve SQL Sorguları</h5>
    </div>
    <div class="card-body">
        <div class="alert alert-info">
            <p><strong>Bilgi:</strong> Bu sayfa, veritabanı şemanızı otomatik olarak analiz ederek uygun SQL sorgularını oluşturur.</p>
            <p>Aşağıdaki SQL sorgularını Supabase Studio SQL Editörü'nde çalıştırabilirsiniz.</p>
        </div>
        
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
                            
                            <h6>Örnek Veri:</h6>
                            <pre class="p-3 bg-light"><code><?php echo json_encode($schemas[$table]['sample'], JSON_PRETTY_PRINT); ?></code></pre>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
            <?php endforeach; ?>
        </div>
        
        <div class="mt-4">
            <h5>Özel SQL Sorguları</h5>
            
            <div class="card mb-3">
                <div class="card-header">Trigger'ları Kaldırma SQL'i</div>
                <div class="card-body">
                    <pre class="p-3 bg-light"><code><?php echo $disable_triggers_sql; ?></code></pre>
                    <button class="btn btn-sm btn-primary copyBtn" data-sql="<?php echo htmlspecialchars($disable_triggers_sql); ?>">
                        <i class="fas fa-copy me-1"></i> Kopyala
                    </button>
                </div>
            </div>
            
            <div class="card">
                <div class="card-header">Parti Puanlama SQL'i</div>
                <div class="card-body">
                    <?php if (empty($party_scoring_sql)): ?>
                        <div class="alert alert-warning">
                            Gerekli sütunlar bulunamadığı için SQL oluşturulamadı.
                        </div>
                    <?php else: ?>
                        <pre class="p-3 bg-light"><code><?php echo $party_scoring_sql; ?></code></pre>
                        <button class="btn btn-sm btn-primary copyBtn" data-sql="<?php echo htmlspecialchars($party_scoring_sql); ?>">
                            <i class="fas fa-copy me-1"></i> Kopyala
                        </button>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Kopyalama düğmelerini ayarla
    const copyButtons = document.querySelectorAll('.copyBtn');
    
    copyButtons.forEach(button => {
        button.addEventListener('click', function() {
            const sql = this.getAttribute('data-sql');
            
            // Panoya kopyala
            const textArea = document.createElement('textarea');
            textArea.value = sql;
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
});
</script>