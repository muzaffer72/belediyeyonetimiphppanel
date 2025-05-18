<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// Şehir verilerini al (ilçenin bağlı olduğu şehri seçmek için)
$cities_result = getData('cities');
$cities = $cities_result['data'];

// Parti verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'];

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz ilçe ID\'si';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=districts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=districts";</script>';
        exit;
    }
}

$district_id = $_GET['id'];
$district = getDataById('districts', $district_id);

if (!$district) {
    $_SESSION['message'] = 'İlçe bulunamadı';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=districts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=districts";</script>';
        exit;
    }
}

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_district'])) {
    // Form verilerini al
    $name = trim($_POST['name'] ?? '');
    $city_id = trim($_POST['city_id'] ?? '');
    $email = trim($_POST['email'] ?? '');
    $mayor_name = trim($_POST['mayor_name'] ?? '');
    $mayor_party = trim($_POST['mayor_party'] ?? '');
    $population = trim($_POST['population'] ?? '');
    $logo_url = trim($_POST['logo_url'] ?? '');
    $website = trim($_POST['website'] ?? '');
    $phone = trim($_POST['phone'] ?? '');
    $address = trim($_POST['address'] ?? '');
    $cover_image_url = trim($_POST['cover_image_url'] ?? '');
    
    // Basit doğrulama
    $errors = [];
    if (empty($name)) {
        $errors[] = 'İlçe adı gereklidir';
    }
    if (empty($city_id)) {
        $errors[] = 'Bağlı olduğu şehir gereklidir';
    }
    
    // Logo resmi yüklendiyse işle
    if (isset($_FILES['logo_image']) && !empty($_FILES['logo_image']['name'])) {
        $target_dir = __DIR__ . '/../uploads/districts';
        $upload_result = uploadImage($_FILES['logo_image'], $target_dir);
        
        if ($upload_result['success']) {
            $logo_url = $upload_result['file_url'];
        } else {
            $errors[] = 'Logo yüklenirken bir hata oluştu: ' . $upload_result['message'];
        }
    }
    
    // Kapak resmi yüklendiyse işle
    if (isset($_FILES['cover_image']) && !empty($_FILES['cover_image']['name'])) {
        $target_dir = __DIR__ . '/../uploads/districts';
        $upload_result = uploadImage($_FILES['cover_image'], $target_dir);
        
        if ($upload_result['success']) {
            $cover_image_url = $upload_result['file_url'];
        } else {
            $errors[] = 'Kapak görseli yüklenirken bir hata oluştu: ' . $upload_result['message'];
        }
    }
    
    // Hata yoksa ilçeyi güncelle
    if (empty($errors)) {
        $update_data = [
            'name' => $name,
            'city_id' => $city_id,
            'email' => $email,
            'mayor_name' => $mayor_name,
            'mayor_party' => $mayor_party,
            'population' => $population,
            'logo_url' => $logo_url,
            'website' => $website,
            'phone' => $phone,
            'address' => $address,
            'cover_image_url' => $cover_image_url,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        $response = updateData('districts', $district_id, $update_data);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'İlçe başarıyla güncellendi';
            $_SESSION['message_type'] = 'success';
            
            // İlçeler sayfasına yönlendir
            if (!headers_sent()) {
                header('Location: index.php?page=districts');
                exit;
            } else {
                echo '<script>window.location.href = "index.php?page=districts";</script>';
                exit;
            }
        } else {
            $error_message = 'İlçe güncellenirken bir hata oluştu: ' . $response['message'];
        }
    } else {
        $error_message = 'Form hataları: ' . implode(', ', $errors);
    }
}

// İlçenin bağlı olduğu şehri bul
$city_name = '';
if (isset($district['city_id'])) {
    foreach ($cities as $city) {
        if ($city['id'] === $district['city_id']) {
            $city_name = $city['name'];
            break;
        }
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">İlçe Düzenle: <?php echo escape($district['name']); ?></h1>
    
    <a href="index.php?page=districts" class="btn btn-secondary">
        <i class="fas fa-arrow-left me-1"></i> İlçelere Dön
    </a>
</div>

<!-- Hata Mesajı -->
<?php if (isset($error_message)): ?>
<div class="alert alert-danger alert-dismissible fade show" role="alert">
    <?php echo $error_message; ?>
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>
<?php endif; ?>

<!-- İlçe Düzenleme Formu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-edit me-1"></i>
        İlçe Bilgileri
    </div>
    <div class="card-body">
        <form method="post" action="index.php?page=district_edit&id=<?php echo $district_id; ?>" enctype="multipart/form-data">
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="name" class="form-label">İlçe Adı <span class="text-danger">*</span></label>
                    <input type="text" class="form-control" id="name" name="name" value="<?php echo escape($district['name'] ?? ''); ?>" required>
                </div>
                <div class="col-md-6">
                    <label for="city_id" class="form-label">Bağlı Olduğu Şehir <span class="text-danger">*</span></label>
                    <select class="form-select" id="city_id" name="city_id" required>
                        <option value="">Seçiniz</option>
                        <?php foreach($cities as $city): ?>
                            <option value="<?php echo $city['id']; ?>" <?php echo (isset($district['city_id']) && $district['city_id'] === $city['id']) ? 'selected' : ''; ?>>
                                <?php echo $city['name']; ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="mayor_name" class="form-label">Belediye Başkanı</label>
                    <input type="text" class="form-control" id="mayor_name" name="mayor_name" value="<?php echo escape($district['mayor_name'] ?? ''); ?>">
                </div>
                <div class="col-md-6">
                    <label for="mayor_party" class="form-label">Parti</label>
                    <select class="form-select" id="mayor_party" name="mayor_party">
                        <option value="">Seçiniz</option>
                        <?php foreach($parties as $party): ?>
                            <option value="<?php echo $party['name']; ?>" <?php echo (isset($district['mayor_party']) && $district['mayor_party'] === $party['name']) ? 'selected' : ''; ?>>
                                <?php echo $party['name']; ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="population" class="form-label">Nüfus</label>
                    <input type="text" class="form-control" id="population" name="population" value="<?php echo escape($district['population'] ?? ''); ?>">
                </div>
                <div class="col-md-6">
                    <label for="phone" class="form-label">Telefon</label>
                    <input type="text" class="form-control" id="phone" name="phone" value="<?php echo escape($district['phone'] ?? ''); ?>">
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="website" class="form-label">Web Sitesi</label>
                    <input type="url" class="form-control" id="website" name="website" value="<?php echo escape($district['website'] ?? ''); ?>">
                </div>
                <div class="col-md-6">
                    <label for="email" class="form-label">Email</label>
                    <input type="email" class="form-control" id="email" name="email" value="<?php echo escape($district['email'] ?? ''); ?>">
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label class="form-label">Logo</label>
                    <div class="input-group">
                        <input type="url" class="form-control" id="logo_url" name="logo_url" value="<?php echo escape($district['logo_url'] ?? ''); ?>" placeholder="Logo URL">
                        <button class="btn btn-outline-secondary" type="button" id="toggleLogoUpload">Resim Yükle</button>
                    </div>
                    <div id="logoFileUpload" class="mt-2" style="display:none;">
                        <input type="file" class="form-control" id="logo_image" name="logo_image" accept="image/*">
                        <div class="form-text">PNG, JPG veya GIF. Maks 5MB.</div>
                    </div>
                    <?php if(isset($district['logo_url']) && !empty($district['logo_url'])): ?>
                    <div class="mt-2">
                        <img src="<?php echo escape($district['logo_url']); ?>" alt="Mevcut Logo" class="img-thumbnail" style="max-height: 100px;">
                    </div>
                    <?php endif; ?>
                </div>
                <div class="col-md-6">
                    <label class="form-label">Kapak Görseli</label>
                    <div class="input-group">
                        <input type="url" class="form-control" id="cover_image_url" name="cover_image_url" value="<?php echo escape($district['cover_image_url'] ?? ''); ?>" placeholder="Kapak Görseli URL">
                        <button class="btn btn-outline-secondary" type="button" id="toggleCoverUpload">Resim Yükle</button>
                    </div>
                    <div id="coverFileUpload" class="mt-2" style="display:none;">
                        <input type="file" class="form-control" id="cover_image" name="cover_image" accept="image/*">
                        <div class="form-text">PNG, JPG veya GIF. Maks 5MB.</div>
                    </div>
                    <?php if(isset($district['cover_image_url']) && !empty($district['cover_image_url'])): ?>
                    <div class="mt-2">
                        <img src="<?php echo escape($district['cover_image_url']); ?>" alt="Mevcut Kapak" class="img-thumbnail" style="max-height: 100px;">
                    </div>
                    <?php endif; ?>
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-12">
                    <label for="address" class="form-label">Adres</label>
                    <textarea class="form-control" id="address" name="address" rows="2"><?php echo escape($district['address'] ?? ''); ?></textarea>
                </div>
            </div>
            
            <div class="row mt-4">
                <div class="col-12">
                    <button type="submit" name="update_district" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i> Değişiklikleri Kaydet
                    </button>
                    <a href="index.php?page=districts" class="btn btn-secondary ms-2">
                        <i class="fas fa-times me-1"></i> İptal
                    </a>
                </div>
            </div>
        </form>
    </div>
</div>

<script>
// Resim yükleme alanlarını gösterme/gizleme
document.addEventListener('DOMContentLoaded', function() {
    // Logo resmi için
    document.getElementById('toggleLogoUpload').addEventListener('click', function() {
        const logoUpload = document.getElementById('logoFileUpload');
        if (logoUpload.style.display === 'none') {
            logoUpload.style.display = 'block';
            this.textContent = 'URL Kullan';
        } else {
            logoUpload.style.display = 'none';
            this.textContent = 'Resim Yükle';
        }
    });
    
    // Kapak resmi için
    document.getElementById('toggleCoverUpload').addEventListener('click', function() {
        const coverUpload = document.getElementById('coverFileUpload');
        if (coverUpload.style.display === 'none') {
            coverUpload.style.display = 'block';
            this.textContent = 'URL Kullan';
        } else {
            coverUpload.style.display = 'none';
            this.textContent = 'Resim Yükle';
        }
    });
});
</script>

<?php if (isset($district['logo_url']) && !empty($district['logo_url'])): ?>
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-image me-1"></i>
        İlçe Logosu
    </div>
    <div class="card-body text-center">
        <img src="<?php echo escape($district['logo_url']); ?>" alt="<?php echo escape($district['name']); ?> Logo" class="img-fluid" style="max-height: 200px;">
    </div>
</div>
<?php endif; ?>