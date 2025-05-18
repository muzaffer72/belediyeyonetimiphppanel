<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// Şehir verilerini al (dropdown için)
$cities_result = getData('cities');
$cities = $cities_result['data'];

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz gönderi ID\'si';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=posts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=posts";</script>';
        exit;
    }
}

$post_id = $_GET['id'];
$post = getDataById('posts', $post_id);

if (!$post) {
    $_SESSION['message'] = 'Gönderi bulunamadı';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=posts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=posts";</script>';
        exit;
    }
}

// Kullanıcı verilerini al (dropdown için)
$users_result = getData('users');
$users = $users_result['data'];

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_post'])) {
    // Form verilerini al
    $title = trim($_POST['title'] ?? '');
    $description = trim($_POST['description'] ?? '');
    $type = $_POST['type'] ?? '';
    $city = $_POST['city'] ?? '';
    $district = $_POST['district'] ?? '';
    $user_id = $_POST['user_id'] ?? $post['user_id'] ?? '';
    $media_url = trim($_POST['media_url'] ?? '');
    $is_video = isset($_POST['is_video']) ? 'true' : 'false';
    $is_resolved = isset($_POST['is_resolved']) ? 'true' : 'false';
    $is_hidden = isset($_POST['is_hidden']) ? 'true' : 'false';
    $is_featured = isset($_POST['is_featured']) ? 'true' : 'false';
    $category = $_POST['category'] ?? '';
    
    // Basit doğrulama
    $errors = [];
    if (empty($title)) {
        $errors[] = 'Başlık gereklidir';
    }
    
    // Hata yoksa gönderiyi güncelle
    if (empty($errors)) {
        $update_data = [
            'title' => $title,
            'description' => $description,
            'type' => $type,
            'city' => $city,
            'district' => $district,
            'user_id' => $user_id,
            'media_url' => $media_url,
            'is_video' => $is_video,
            'is_resolved' => $is_resolved,
            'is_hidden' => $is_hidden,
            'is_featured' => $is_featured,
            'category' => $category,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        $response = updateData('posts', $post_id, $update_data);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Gönderi başarıyla güncellendi';
            $_SESSION['message_type'] = 'success';
            
            // Gönderi detay sayfasına yönlendir
            if (!headers_sent()) {
                header('Location: index.php?page=post_detail&id=' . $post_id);
                exit;
            } else {
                echo '<script>window.location.href = "index.php?page=post_detail&id=' . $post_id . '";</script>';
                exit;
            }
        } else {
            $error_message = 'Gönderi güncellenirken bir hata oluştu: ' . $response['message'];
        }
    } else {
        $error_message = 'Form hataları: ' . implode(', ', $errors);
    }
}

// Gönderi kategori tipleri
$post_types = [
    'complaint' => 'Şikayet',
    'suggestion' => 'Öneri',
    'question' => 'Soru',
    'thanks' => 'Teşekkür'
];

// Kategori seçenekleri
$categories = [
    'infrastructure' => 'Altyapı',
    'transportation' => 'Ulaşım',
    'environment' => 'Çevre',
    'education' => 'Eğitim',
    'health' => 'Sağlık',
    'security' => 'Güvenlik',
    'social' => 'Sosyal Hizmetler',
    'parks' => 'Park ve Bahçeler',
    'cleaning' => 'Temizlik',
    'other' => 'Diğer'
];

// İlçe listesini al
$post_city = isset($post['city']) ? $post['city'] : '';
$districts = [];

if (!empty($post_city)) {
    // Şehre ait ilçeleri bul
    $city_id = null;
    foreach ($cities as $city) {
        if ($city['name'] === $post_city) {
            $city_id = $city['id'];
            break;
        }
    }
    
    if ($city_id) {
        $districts_result = getData('districts', ['city_id' => 'eq.' . $city_id]);
        $districts = $districts_result['data'];
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Gönderi Düzenle</h1>
    
    <div>
        <a href="index.php?page=post_detail&id=<?php echo $post_id; ?>" class="btn btn-info me-2">
            <i class="fas fa-eye me-1"></i> Görüntüle
        </a>
        <a href="index.php?page=posts" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Gönderilere Dön
        </a>
    </div>
</div>

<!-- Hata Mesajı -->
<?php if (isset($error_message)): ?>
<div class="alert alert-danger alert-dismissible fade show" role="alert">
    <?php echo $error_message; ?>
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>
<?php endif; ?>

<!-- Gönderi Düzenleme Formu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-edit me-1"></i>
        Gönderi Bilgileri
    </div>
    <div class="card-body">
        <form method="post" action="index.php?page=post_edit&id=<?php echo $post_id; ?>">
            <div class="row mb-3">
                <div class="col-md-8">
                    <label for="title" class="form-label">Başlık <span class="text-danger">*</span></label>
                    <input type="text" class="form-control" id="title" name="title" value="<?php echo escape($post['title'] ?? ''); ?>" required>
                </div>
                <div class="col-md-4">
                    <label for="type" class="form-label">Gönderi Tipi</label>
                    <select class="form-select" id="type" name="type">
                        <option value="">Seçiniz</option>
                        <?php foreach($post_types as $key => $name): ?>
                            <option value="<?php echo $key; ?>" <?php echo (isset($post['type']) && $post['type'] === $key) ? 'selected' : ''; ?>>
                                <?php echo $name; ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            
            <div class="mb-3">
                <label for="description" class="form-label">Açıklama</label>
                <textarea class="form-control" id="description" name="description" rows="4"><?php echo escape($post['description'] ?? ''); ?></textarea>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="city" class="form-label">Şehir</label>
                    <select class="form-select" id="city" name="city">
                        <option value="">Seçiniz</option>
                        <?php foreach($cities as $city): ?>
                            <option value="<?php echo escape($city['name']); ?>" <?php echo (isset($post['city']) && $post['city'] === $city['name']) ? 'selected' : ''; ?>>
                                <?php echo escape($city['name']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="col-md-6">
                    <label for="district" class="form-label">İlçe</label>
                    <select class="form-select" id="district" name="district">
                        <option value="">Seçiniz</option>
                        <?php foreach($districts as $district): ?>
                            <option value="<?php echo escape($district['name']); ?>" <?php echo (isset($post['district']) && $post['district'] === $district['name']) ? 'selected' : ''; ?>>
                                <?php echo escape($district['name']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="user_id" class="form-label">Kullanıcı</label>
                    <select class="form-select" id="user_id" name="user_id">
                        <option value="">Seçiniz</option>
                        <?php foreach($users as $user): ?>
                            <option value="<?php echo escape($user['id']); ?>" <?php echo (isset($post['user_id']) && $post['user_id'] === $user['id']) ? 'selected' : ''; ?>>
                                <?php echo escape($user['username'] ?? $user['email'] ?? $user['id']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="col-md-6">
                    <label for="category" class="form-label">Kategori</label>
                    <select class="form-select" id="category" name="category">
                        <option value="">Seçiniz</option>
                        <?php foreach($categories as $key => $name): ?>
                            <option value="<?php echo $key; ?>" <?php echo (isset($post['category']) && $post['category'] === $key) ? 'selected' : ''; ?>>
                                <?php echo $name; ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            
            <div class="mb-3">
                <label for="media_url" class="form-label">Medya URL</label>
                <input type="url" class="form-control" id="media_url" name="media_url" value="<?php echo escape($post['media_url'] ?? ''); ?>">
            </div>
            
            <div class="row mb-4">
                <div class="col-md-3">
                    <div class="form-check form-switch">
                        <input class="form-check-input" type="checkbox" id="is_video" name="is_video" <?php echo (isset($post['is_video']) && $post['is_video'] === 'true') ? 'checked' : ''; ?>>
                        <label class="form-check-label" for="is_video">Video</label>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="form-check form-switch">
                        <input class="form-check-input" type="checkbox" id="is_resolved" name="is_resolved" <?php echo (isset($post['is_resolved']) && $post['is_resolved'] === 'true') ? 'checked' : ''; ?>>
                        <label class="form-check-label" for="is_resolved">Çözüldü</label>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="form-check form-switch">
                        <input class="form-check-input" type="checkbox" id="is_hidden" name="is_hidden" <?php echo (isset($post['is_hidden']) && $post['is_hidden'] === 'true') ? 'checked' : ''; ?>>
                        <label class="form-check-label" for="is_hidden">Gizli</label>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="form-check form-switch">
                        <input class="form-check-input" type="checkbox" id="is_featured" name="is_featured" <?php echo (isset($post['is_featured']) && $post['is_featured'] === 'true') ? 'checked' : ''; ?>>
                        <label class="form-check-label" for="is_featured">Öne Çıkarıldı</label>
                    </div>
                </div>
            </div>
            
            <?php if (isset($post['media_url']) && !empty($post['media_url'])): ?>
            <div class="mb-4">
                <label class="form-label">Mevcut Medya</label>
                <div class="border p-2 rounded">
                    <?php if (isset($post['is_video']) && $post['is_video'] === 'true'): ?>
                        <div class="ratio ratio-16x9">
                            <video src="<?php echo escape($post['media_url']); ?>" controls class="rounded"></video>
                        </div>
                    <?php else: ?>
                        <img src="<?php echo escape($post['media_url']); ?>" alt="Gönderi Görseli" class="img-fluid rounded" style="max-height: 200px;">
                    <?php endif; ?>
                </div>
            </div>
            <?php endif; ?>
            
            <?php if (isset($post['media_urls']) && !empty($post['media_urls'])): 
                $media_urls = is_array($post['media_urls']) ? $post['media_urls'] : json_decode($post['media_urls'], true);
                if (!empty($media_urls)):
            ?>
            <div class="mb-4">
                <label class="form-label">Ek Görseller</label>
                <div class="row">
                    <?php foreach ($media_urls as $url): ?>
                        <div class="col-md-3 col-sm-6 mb-2">
                            <img src="<?php echo escape($url); ?>" alt="Ek Görsel" class="img-fluid rounded border">
                        </div>
                    <?php endforeach; ?>
                </div>
            </div>
            <?php 
                endif;
            endif; 
            ?>
            
            <div class="row mt-4">
                <div class="col-12">
                    <button type="submit" name="update_post" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i> Değişiklikleri Kaydet
                    </button>
                    <a href="index.php?page=posts" class="btn btn-secondary ms-2">
                        <i class="fas fa-times me-1"></i> İptal
                    </a>
                </div>
            </div>
        </form>
    </div>
</div>

<script>
// Şehir değiştiğinde ilçeleri güncelle
document.addEventListener('DOMContentLoaded', function() {
    const citySelect = document.getElementById('city');
    const districtSelect = document.getElementById('district');
    
    citySelect.addEventListener('change', function() {
        const selectedCity = this.value;
        
        // İlçe seçeneğini sıfırla
        districtSelect.innerHTML = '<option value="">Seçiniz</option>';
        
        if (selectedCity) {
            // AJAX ile seçilen şehre ait ilçeleri getir
            fetch(`index.php?page=get_districts&city=${encodeURIComponent(selectedCity)}`)
                .then(response => response.json())
                .then(data => {
                    if (data && data.length > 0) {
                        data.forEach(district => {
                            const option = document.createElement('option');
                            option.value = district.name;
                            option.textContent = district.name;
                            districtSelect.appendChild(option);
                        });
                    }
                })
                .catch(error => {
                    console.error('İlçeler alınırken hata oluştu:', error);
                });
        }
    });
});
</script>