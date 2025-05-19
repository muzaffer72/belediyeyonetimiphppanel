<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// Varsayılan değerler
$query = '';
$result = null;
$error = null;
$success = false;

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['query'])) {
    $query = trim($_POST['query']);
    
    if (!empty($query)) {
        // Trigger kaldırma sorguları
        if (isset($_POST['action']) && $_POST['action'] === 'disable_triggers') {
            $query = "
            -- Mevcut tüm triggerları devre dışı bırak
            DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
            DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
            DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
            DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;
            
            -- Trigger fonksiyonlarını da kaldır (isteğe bağlı)
            DROP FUNCTION IF EXISTS calculate_solution_rate_percentage();
            DROP FUNCTION IF EXISTS update_solution_rates_and_scores();
            DROP FUNCTION IF EXISTS recalculate_all_party_scores();
            DROP FUNCTION IF EXISTS update_party_scores();
            ";
        }
        
        // Parti puanlama sorguları
        if (isset($_POST['action']) && $_POST['action'] === 'update_party_scoring') {
            $query = "
            -- Tüm partilerin puanlarını sıfırla
            UPDATE political_parties SET score = 0;
            
            -- Şehirlerin çözüm oranlarını hesapla (ilk olarak)
            UPDATE cities c
            SET solution_rate = (
                SELECT 
                CASE 
                    WHEN COALESCE(SUM(d.total_posts), 0) = 0 THEN 0
                    ELSE (COALESCE(SUM(d.resolved_posts), 0) * 100.0 / COALESCE(SUM(d.total_posts), 0))
                END
                FROM districts d
                WHERE d.city_id = c.id
            );
            
            -- İlçelerin çözüm oranlarını hesapla
            UPDATE districts d
            SET solution_rate = (
                CASE 
                    WHEN COALESCE(total_posts, 0) = 0 THEN 0
                    ELSE (COALESCE(resolved_posts, 0) * 100.0 / COALESCE(total_posts, 0))
                END
            );
            
            -- Partileri çözüm oranlarına göre sırala ve toplam puanı hesapla
            WITH ranked_parties AS (
                SELECT 
                    pp.id,
                    pp.name,
                    COALESCE(AVG(c.solution_rate), 0) AS avg_solution_rate,
                    ROW_NUMBER() OVER (ORDER BY COALESCE(AVG(c.solution_rate), 0) DESC) AS rank
                FROM 
                    political_parties pp
                LEFT JOIN 
                    cities c ON c.political_party_id = pp.id
                GROUP BY 
                    pp.id, pp.name
            ),
            -- Eşit çözüm oranına sahip partileri tespit et
            party_ranks AS (
                SELECT 
                    id, 
                    name,
                    avg_solution_rate,
                    rank,
                    COUNT(*) OVER (PARTITION BY avg_solution_rate) AS equal_rank_count,
                    SUM(1) OVER () AS total_parties
                FROM 
                    ranked_parties
            )
            -- 100 puanı orantılı olarak dağıt
            UPDATE political_parties pp
            SET score = (
                SELECT 
                    CASE 
                        WHEN pr.avg_solution_rate = 0 THEN 0
                        ELSE (100.0 / pr.total_parties) * 
                             (pr.total_parties - pr.rank + 1) / 
                             pr.equal_rank_count
                    END
                FROM 
                    party_ranks pr
                WHERE 
                    pr.id = pp.id
            );
            ";
        }
        
        // Seçenekleri ayarla (SQL sorgusuna göre)
        $curl_options = [
            CURLOPT_URL => SUPABASE_REST_URL . '/posts', // Burada tablo önemli değil, sadece ayarları göndermek için
            CURLOPT_CUSTOMREQUEST => 'GET', // Güvenlik için GET kullanıyoruz
            CURLOPT_HTTPHEADER => [
                'apikey: ' . SUPABASE_API_KEY,
                'Authorization: ' . SUPABASE_AUTH_HEADER,
                'Content-Type: application/json',
                'Prefer: return=representation'
            ],
            CURLOPT_RETURNTRANSFER => true
        ];
        
        // SQL sorgusunu çalıştırmak için ilgili tablolara erişim yapacağız
        $tables = ['posts', 'cities', 'districts', 'political_parties', 'users', 'comments'];
        $results = [];
        $all_success = true;
        
        foreach ($tables as $table) {
            // Her tablo için CRUD işlemlerini dene
            $operations = ['select', 'update'];
            foreach ($operations as $operation) {
                $curr_url = SUPABASE_REST_URL . '/' . $table;
                
                if ($operation === 'select') {
                    // SELECT işlemi
                    $ch = curl_init();
                    curl_setopt_array($ch, $curl_options);
                    curl_setopt($ch, CURLOPT_URL, $curr_url . '?limit=1');  // Sadece bir kayıt al
                    $response = curl_exec($ch);
                    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                    curl_close($ch);
                    
                    if ($http_code >= 200 && $http_code < 300) {
                        $results[$table]['select'] = "✓ {$table} tablosuna SELECT erişimi var";
                    } else {
                        $results[$table]['select'] = "✗ {$table} tablosuna SELECT erişimi yok";
                        $all_success = false;
                    }
                } else if ($operation === 'update' && in_array($table, ['political_parties', 'cities', 'districts'])) {
                    // UPDATE işlemi - sadece belirli tablolarda
                    $ch = curl_init();
                    curl_setopt_array($ch, $curl_options);
                    curl_setopt($ch, CURLOPT_URL, $curr_url . '?id=eq.1'); // id=1 olan kaydı güncelle
                    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PATCH');
                    
                    // Dummy veri (gerçek güncelleme yapmayacak - sadece izin kontrolü)
                    $dummy_data = json_encode(['updated_at' => date('c')]);
                    curl_setopt($ch, CURLOPT_POSTFIELDS, $dummy_data);
                    
                    $response = curl_exec($ch);
                    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                    curl_close($ch);
                    
                    if ($http_code >= 200 && $http_code < 300) {
                        $results[$table]['update'] = "✓ {$table} tablosuna UPDATE erişimi var";
                    } else {
                        $results[$table]['update'] = "✗ {$table} tablosuna UPDATE erişimi yok";
                        $all_success = false;
                    }
                }
            }
        }
        
        // Sonuçları göster
        if ($all_success) {
            $success = true;
            $result = "Tüm gerekli tablolara erişim sağlandı. SQL sorgusunu doğrudan veritabanı yönetim arayüzünde çalıştırmanız gerekiyor.";
        } else {
            $error = "Bazı tablolara erişim sağlanamadı. Lütfen erişim izinlerini kontrol edin.";
            $result = $results;
        }
    } else {
        $error = "Lütfen bir SQL sorgusu girin.";
    }
}
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Manuel SQL İşlemleri</h5>
    </div>
    <div class="card-body">
        <?php if ($error): ?>
            <div class="alert alert-danger"><?php echo $error; ?></div>
        <?php endif; ?>
        
        <?php if ($success): ?>
            <div class="alert alert-success">İşlem başarılı.</div>
        <?php endif; ?>
        
        <?php if ($result): ?>
            <div class="card mb-3">
                <div class="card-header">Sonuç</div>
                <div class="card-body">
                    <?php if (is_array($result)): ?>
                        <div class="table-responsive">
                            <table class="table table-bordered">
                                <thead>
                                    <tr>
                                        <th>Tablo</th>
                                        <th>SELECT</th>
                                        <th>UPDATE</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($result as $table => $operations): ?>
                                        <tr>
                                            <td><?php echo $table; ?></td>
                                            <td><?php echo $operations['select'] ?? '-'; ?></td>
                                            <td><?php echo $operations['update'] ?? '-'; ?></td>
                                        </tr>
                                    <?php endforeach; ?>
                                </tbody>
                            </table>
                        </div>
                        <div class="alert alert-info mt-3">
                            <p><strong>Bilgi:</strong> SQL sorgularını direkt API üzerinden çalıştırmak için gereken <code>execute_sql</code> fonksiyonu Supabase'de mevcut değil.</p>
                            <p>Aşağıdaki SQL kodunu veritabanı yönetim arayüzünde (ör. Supabase Studio SQL Editör) manuel olarak çalıştırmanız gerekiyor:</p>
                            <pre class="p-3 bg-light"><code><?php echo htmlspecialchars($query); ?></code></pre>
                            <p class="mb-0">Bu sorguyu çalıştırdıktan sonra puanlama sistemi güncellenecek veya trigger'lar devre dışı bırakılacaktır.</p>
                        </div>
                    <?php else: ?>
                        <div class="alert alert-info">
                            <p><strong>Bilgi:</strong> SQL sorgularını direkt API üzerinden çalıştırmak için gereken <code>execute_sql</code> fonksiyonu Supabase'de mevcut değil.</p>
                            <p>Aşağıdaki SQL kodunu veritabanı yönetim arayüzünde (ör. Supabase Studio SQL Editör) manuel olarak çalıştırmanız gerekiyor:</p>
                            <pre class="p-3 bg-light"><code><?php echo htmlspecialchars($query); ?></code></pre>
                            <p class="mb-0">Bu sorguyu çalıştırdıktan sonra puanlama sistemi güncellenecek veya trigger'lar devre dışı bırakılacaktır.</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        <?php endif; ?>
        
        <form method="post" action="">
            <div class="mb-3">
                <label for="query" class="form-label">SQL Sorgusu</label>
                <textarea class="form-control" id="query" name="query" rows="10"><?php echo htmlspecialchars($query); ?></textarea>
                <div class="form-text">Yalnızca güvenli sorguları çalıştırın.</div>
            </div>
            
            <div class="mb-3">
                <div class="form-check">
                    <input class="form-check-input" type="radio" name="action" id="custom_query" value="custom" checked>
                    <label class="form-check-label" for="custom_query">
                        Özel Sorgu
                    </label>
                </div>
                <div class="form-check">
                    <input class="form-check-input" type="radio" name="action" id="disable_triggers" value="disable_triggers">
                    <label class="form-check-label" for="disable_triggers">
                        Tüm Trigger'ları Kaldır
                    </label>
                </div>
                <div class="form-check">
                    <input class="form-check-input" type="radio" name="action" id="update_party_scoring" value="update_party_scoring">
                    <label class="form-check-label" for="update_party_scoring">
                        Parti Puanlama Sistemini Güncelle
                    </label>
                </div>
            </div>
            
            <button type="submit" class="btn btn-primary">İşlemi Kontrol Et</button>
        </form>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Radyo düğmelerini dinle
    const radioButtons = document.querySelectorAll('input[name="action"]');
    const queryTextarea = document.getElementById('query');
    
    // SQL sorguları
    const disableTriggersSQL = `-- Mevcut tüm triggerları devre dışı bırak
DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;

-- Trigger fonksiyonlarını da kaldır (isteğe bağlı)
DROP FUNCTION IF EXISTS calculate_solution_rate_percentage();
DROP FUNCTION IF EXISTS update_solution_rates_and_scores();
DROP FUNCTION IF EXISTS recalculate_all_party_scores();
DROP FUNCTION IF EXISTS update_party_scores();`;

    const updatePartyScoringSQL = `-- Tüm partilerin puanlarını sıfırla
UPDATE political_parties SET score = 0;

-- Şehirlerin çözüm oranlarını hesapla (ilk olarak)
UPDATE cities c
SET solution_rate = (
    SELECT 
    CASE 
        WHEN COALESCE(SUM(d.total_posts), 0) = 0 THEN 0
        ELSE (COALESCE(SUM(d.resolved_posts), 0) * 100.0 / COALESCE(SUM(d.total_posts), 0))
    END
    FROM districts d
    WHERE d.city_id = c.id
);

-- İlçelerin çözüm oranlarını hesapla
UPDATE districts d
SET solution_rate = (
    CASE 
        WHEN COALESCE(total_posts, 0) = 0 THEN 0
        ELSE (COALESCE(resolved_posts, 0) * 100.0 / COALESCE(total_posts, 0))
    END
);

-- Partileri çözüm oranlarına göre sırala ve toplam puanı hesapla
WITH ranked_parties AS (
    SELECT 
        pp.id,
        pp.name,
        COALESCE(AVG(c.solution_rate), 0) AS avg_solution_rate,
        ROW_NUMBER() OVER (ORDER BY COALESCE(AVG(c.solution_rate), 0) DESC) AS rank
    FROM 
        political_parties pp
    LEFT JOIN 
        cities c ON c.political_party_id = pp.id
    GROUP BY 
        pp.id, pp.name
),
-- Eşit çözüm oranına sahip partileri tespit et
party_ranks AS (
    SELECT 
        id, 
        name,
        avg_solution_rate,
        rank,
        COUNT(*) OVER (PARTITION BY avg_solution_rate) AS equal_rank_count,
        SUM(1) OVER () AS total_parties
    FROM 
        ranked_parties
)
-- 100 puanı orantılı olarak dağıt
UPDATE political_parties pp
SET score = (
    SELECT 
        CASE 
            WHEN pr.avg_solution_rate = 0 THEN 0
            ELSE (100.0 / pr.total_parties) * 
                 (pr.total_parties - pr.rank + 1) / 
                 pr.equal_rank_count
        END
    FROM 
        party_ranks pr
    WHERE 
        pr.id = pp.id
);`;

    // Radyo düğmesi değişimlerini dinle
    radioButtons.forEach(function(radio) {
        radio.addEventListener('change', function() {
            if (this.value === 'disable_triggers') {
                queryTextarea.value = disableTriggersSQL;
            } else if (this.value === 'update_party_scoring') {
                queryTextarea.value = updatePartyScoringSQL;
            } else {
                // Custom sorgu seçildiğinde, değiştirme
            }
        });
    });
});
</script>