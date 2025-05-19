<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// Varsayılan değerler
$message = '';
$error = '';
$success = false;

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $title = isset($_POST['title']) ? trim($_POST['title']) : '';
    $content = isset($_POST['content']) ? trim($_POST['content']) : '';
    $city_id = isset($_POST['city_id']) ? (int)$_POST['city_id'] : 0;
    $district_id = isset($_POST['district_id']) ? (int)$_POST['district_id'] : 0;
    
    // Temel doğrulama
    if (empty($title) || empty($content) || $city_id <= 0 || $district_id <= 0) {
        $error = "Lütfen tüm alanları doldurun.";
    } else {
        // Post verisi oluştur
        $post_data = [
            'title' => $title,
            'content' => $content,
            'city_id' => $city_id,
            'district_id' => $district_id,
            'status' => 'active',
            'created_at' => date('c'),
            'updated_at' => date('c'),
            'is_resolved' => false,
            'is_hidden' => false,
            'likes' => 0,
            'user_id' => 1 // Varsayılan kullanıcı
        ];
        
        // POST isteği göndererek veri ekle
        $result = addData('posts', $post_data);
        
        if (!$result['error']) {
            $success = true;
            $message = "Test gönderisi başarıyla eklendi! Trigger sorununu test ettiniz.";
        } else {
            $error = "Gönderi eklenirken bir hata oluştu: " . ($result['message'] ?? 'Bilinmeyen hata');
        }
    }
}

// Şehir ve ilçeleri yükle
$cities_result = getData('cities', ['select' => 'id,name', 'order' => 'name.asc']);
$cities = $cities_result['error'] ? [] : $cities_result['data'];

$districts_result = getData('districts', ['select' => 'id,name,city_id', 'order' => 'name.asc']);
$districts = $districts_result['error'] ? [] : $districts_result['data'];
?>

<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Trigger Test - Gönderi Paylaşımı</h5>
    </div>
    <div class="card-body">
        <?php if ($error): ?>
            <div class="alert alert-danger"><?php echo $error; ?></div>
        <?php endif; ?>
        
        <?php if ($success): ?>
            <div class="alert alert-success"><?php echo $message; ?></div>
        <?php endif; ?>
        
        <div class="alert alert-info">
            <p><strong>Bilgi:</strong> Bu sayfayı kullanarak test gönderisi paylaşabilirsiniz. Eğer trigger sorunu varsa, gönderi eklenmeyecektir.</p>
            <p>Eğer gönderi başarıyla eklenirse, trigger sorunu çözülmüş demektir. Eğer eklenmezse, Supabase yönetim panelindeki SQL Editörü kullanarak trigger'ları manuel olarak kaldırmanız gerekecektir.</p>
            <p>Aşağıdaki SQL kodunu Supabase SQL Editörü'nde çalıştırarak tüm trigger'ları kaldırabilirsiniz:</p>
            <pre class="p-3 bg-light"><code>-- Mevcut tüm triggerları devre dışı bırak
DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;

-- Trigger fonksiyonlarını da kaldır
DROP FUNCTION IF EXISTS calculate_solution_rate_percentage();
DROP FUNCTION IF EXISTS update_solution_rates_and_scores();
DROP FUNCTION IF EXISTS recalculate_all_party_scores();
DROP FUNCTION IF EXISTS update_party_scores();</code></pre>
        </div>
        
        <form method="post" action="">
            <div class="row">
                <div class="col-md-6">
                    <div class="mb-3">
                        <label for="title" class="form-label">Başlık</label>
                        <input type="text" class="form-control" id="title" name="title" required>
                    </div>
                </div>
                <div class="col-md-6">
                    <div class="row">
                        <div class="col-md-6">
                            <div class="mb-3">
                                <label for="city_id" class="form-label">Şehir</label>
                                <select class="form-select" id="city_id" name="city_id" required>
                                    <option value="">Şehir Seçin</option>
                                    <?php foreach ($cities as $city): ?>
                                        <option value="<?php echo $city['id']; ?>"><?php echo escape($city['name']); ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="mb-3">
                                <label for="district_id" class="form-label">İlçe</label>
                                <select class="form-select" id="district_id" name="district_id" required>
                                    <option value="">Önce Şehir Seçin</option>
                                </select>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="mb-3">
                <label for="content" class="form-label">İçerik</label>
                <textarea class="form-control" id="content" name="content" rows="5" required></textarea>
            </div>
            
            <button type="submit" class="btn btn-primary">Test Gönderisi Ekle</button>
        </form>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // İlçe verileri
    const districts = <?php echo json_encode($districts); ?>;
    
    // Şehir değişikliğini dinle
    const citySelect = document.getElementById('city_id');
    const districtSelect = document.getElementById('district_id');
    
    citySelect.addEventListener('change', function() {
        const cityId = parseInt(this.value);
        
        // İlçe seçimini sıfırla
        districtSelect.innerHTML = '<option value="">İlçe Seçin</option>';
        
        if (cityId) {
            // Seçilen şehre ait ilçeleri filtrele
            const filteredDistricts = districts.filter(d => d.city_id === cityId);
            
            // İlçe seçeneklerini ekle
            filteredDistricts.forEach(district => {
                const option = document.createElement('option');
                option.value = district.id;
                option.textContent = district.name;
                districtSelect.appendChild(option);
            });
        }
    });
});
</script>