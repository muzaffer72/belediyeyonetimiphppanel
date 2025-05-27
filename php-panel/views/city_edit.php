<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// Kullanıcı yetki kontrolü
$user_type = $_SESSION['user_type'] ?? '';
$is_admin = $user_type === 'admin';
$is_moderator = $user_type === 'moderator';
$assigned_city_id = $_SESSION['assigned_city_id'] ?? null;

// Parti verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'] ?? [];

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz şehir ID\'si';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=cities');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cities";</script>';
        exit;
    }
}

$city_id = $_GET['id'];

// Moderatör sadece kendi şehrini düzenleyebilir
if ($is_moderator && $assigned_city_id && $city_id !== $assigned_city_id) {
    $_SESSION['message'] = 'Sadece kendi şehrinizin profilini düzenleyebilirsiniz.';
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=cities');
}

$city_result = getDataById('cities', $city_id);
$city = $city_result['error'] ? null : $city_result['data'];

if (!$city) {
    $_SESSION['message'] = 'Şehir bulunamadı';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=cities');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cities";</script>';
        exit;
    }
}

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_city'])) {
    if ($is_moderator) {
        // Moderatör sadece belirli alanları güncelleyebilir
        $update_data = [
            'email' => trim($_POST['email'] ?? ''),
            'logo_url' => trim($_POST['logo_url'] ?? ''),
            'website' => trim($_POST['website'] ?? ''),
            'phone' => trim($_POST['phone'] ?? ''),
            'address' => trim($_POST['address'] ?? ''),
            'cover_image_url' => trim($_POST['cover_image_url'] ?? ''),
            'updated_at' => date('Y-m-d H:i:s')
        ];
    } else {
        // Admin tüm alanları güncelleyebilir
        $name = trim($_POST['name'] ?? '');
        $email = trim($_POST['email'] ?? '');
        $mayor_name = trim($_POST['mayor_name'] ?? '');
        $political_party_id = trim($_POST['political_party_id'] ?? '');
        $population = trim($_POST['population'] ?? '');
        $logo_url = trim($_POST['logo_url'] ?? '');
        $website = trim($_POST['website'] ?? '');
        $phone = trim($_POST['phone'] ?? '');
        $address = trim($_POST['address'] ?? '');
        $cover_image_url = trim($_POST['cover_image_url'] ?? '');
    }
    
    // Doğrulama
    $errors = [];
    if (!$is_moderator && empty($name)) {
        $errors[] = 'Şehir adı gereklidir';
    }
    
    // Logo resmi yüklendiyse işle
    if (isset($_FILES['logo_image']) && !empty($_FILES['logo_image']['name'])) {
        $target_dir = __DIR__ . '/../uploads/cities';
        $upload_result = uploadImage($_FILES['logo_image'], $target_dir);
        
        if ($upload_result['success']) {
            $logo_url = $upload_result['file_url'];
        } else {
            $errors[] = 'Logo yüklenirken bir hata oluştu: ' . $upload_result['message'];
        }
    }
    
    // Kapak resmi yüklendiyse işle
    if (isset($_FILES['cover_image']) && !empty($_FILES['cover_image']['name'])) {
        $target_dir = __DIR__ . '/../uploads/cities';
        $upload_result = uploadImage($_FILES['cover_image'], $target_dir);
        
        if ($upload_result['success']) {
            $cover_image_url = $upload_result['file_url'];
        } else {
            $errors[] = 'Kapak görseli yüklenirken bir hata oluştu: ' . $upload_result['message'];
        }
    }
    
    // Hata yoksa şehri güncelle
    if (empty($errors)) {
        if ($is_moderator) {
            // Moderatör sadece belirli alanları güncelleyebilir
            $response = updateData('cities', $city_id, $update_data);
        } else {
            // Admin tüm alanları güncelleyebilir
            $party_info = getPartyInfoById($political_party_id);
            $mayor_party = '';
            $party_logo_url = '';
            
            if ($party_info) {
                $mayor_party = $party_info['name'];
                $party_logo_url = $party_info['logo_url'] ?? '';
            }
            
            $admin_update_data = [
                'name' => $name,
                'email' => $email,
                'mayor_name' => $mayor_name,
                'political_party_id' => $political_party_id,
                'mayor_party' => $mayor_party,
                'party_logo_url' => $party_logo_url,
                'population' => $population,
                'logo_url' => $logo_url,
                'website' => $website,
                'phone' => $phone,
                'address' => $address,
                'cover_image_url' => $cover_image_url,
                'updated_at' => date('Y-m-d H:i:s')
            ];
            
            $response = updateData('cities', $city_id, $admin_update_data);
        }
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Şehir başarıyla güncellendi';
            $_SESSION['message_type'] = 'success';
            
            // Şehirler sayfasına yönlendir
            if (!headers_sent()) {
                header('Location: index.php?page=cities');
                exit;
            } else {
                echo '<script>window.location.href = "index.php?page=cities";</script>';
                exit;
            }
        } else {
            $error_message = 'Şehir güncellenirken bir hata oluştu: ' . $response['message'];
        }
    } else {
        $error_message = 'Form hataları: ' . implode(', ', $errors);
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Şehir Düzenle: <?php echo isset($city['name']) ? escape($city['name']) : 'Şehir Bilgisi'; ?></h1>
    
    <a href="index.php?page=cities" class="btn btn-secondary">
        <i class="fas fa-arrow-left me-1"></i> Şehirlere Dön
    </a>
</div>

<!-- Hata Mesajı -->
<?php if (isset($error_message)): ?>
<div class="alert alert-danger alert-dismissible fade show" role="alert">
    <?php echo $error_message; ?>
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>
<?php endif; ?>

<!-- Şehir Düzenleme Formu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-edit me-1"></i>
        Şehir Bilgileri
    </div>
    <div class="card-body">
        <form method="post" action="index.php?page=city_edit&id=<?php echo $city_id; ?>" enctype="multipart/form-data">
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="name" class="form-label">Şehir Adı</label>
                    <?php if ($is_moderator): ?>
                        <input type="text" class="form-control bg-light" id="name" name="name" value="<?php echo escape($city['name'] ?? ''); ?>" readonly>
                        <small class="text-muted">Bu alan değiştirilemez</small>
                    <?php else: ?>
                        <input type="text" class="form-control" id="name" name="name" value="<?php echo escape($city['name'] ?? ''); ?>" required>
                    <?php endif; ?>
                </div>
                <div class="col-md-6">
                    <label for="email" class="form-label">Email</label>
                    <input type="email" class="form-control" id="email" name="email" value="<?php echo escape($city['email'] ?? ''); ?>">
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="mayor_name" class="form-label">Belediye Başkanı</label>
                    <?php if ($is_moderator): ?>
                        <input type="text" class="form-control bg-light" id="mayor_name" name="mayor_name" value="<?php echo escape($city['mayor_name'] ?? ''); ?>" readonly>
                        <small class="text-muted">Bu alan değiştirilemez</small>
                    <?php else: ?>
                        <input type="text" class="form-control" id="mayor_name" name="mayor_name" value="<?php echo escape($city['mayor_name'] ?? ''); ?>">
                    <?php endif; ?>
                </div>
                <div class="col-md-6">
                    <label for="political_party_id" class="form-label">Parti</label>
                    <?php if ($is_moderator): ?>
                        <input type="text" class="form-control bg-light" value="<?php echo escape($city['mayor_party'] ?? 'Belirtilmemiş'); ?>" readonly>
                        <small class="text-muted">Bu alan değiştirilemez</small>
                    <?php else: ?>
                        <select class="form-select" id="political_party_id" name="political_party_id">
                            <option value="">Seçiniz</option>
                            <?php foreach($parties as $party): ?>
                                <option value="<?php echo $party['id']; ?>" <?php echo (isset($city['political_party_id']) && $city['political_party_id'] === $party['id']) ? 'selected' : ''; ?>>
                                    <?php echo $party['name']; ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    <?php endif; ?>
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="population" class="form-label">Nüfus</label>
                    <input type="text" class="form-control" id="population" name="population" value="<?php echo escape($city['population'] ?? ''); ?>">
                </div>
                <div class="col-md-6">
                    <label for="phone" class="form-label">Telefon</label>
                    <input type="text" class="form-control" id="phone" name="phone" value="<?php echo escape($city['phone'] ?? ''); ?>">
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="website" class="form-label">Web Sitesi</label>
                    <input type="url" class="form-control" id="website" name="website" value="<?php echo escape($city['website'] ?? ''); ?>">
                </div>
                <div class="col-md-6">
                    <label class="form-label">Logo</label>
                    <div class="input-group">
                        <input type="url" class="form-control" id="logo_url" name="logo_url" value="<?php echo escape($city['logo_url'] ?? ''); ?>" placeholder="Logo URL">
                        <button class="btn btn-outline-secondary" type="button" id="toggleLogoUpload">Resim Yükle</button>
                    </div>
                    <div id="logoFileUpload" class="mt-2" style="display:none;">
                        <input type="file" class="form-control" id="logo_image" name="logo_image" accept="image/*">
                        <div class="form-text">PNG, JPG veya GIF. Maks 5MB.</div>
                    </div>
                    <?php if(isset($city['logo_url']) && !empty($city['logo_url'])): ?>
                    <div class="mt-2">
                        <img src="<?php echo escape($city['logo_url']); ?>" alt="Mevcut Logo" class="img-thumbnail" style="max-height: 100px;">
                    </div>
                    <?php endif; ?>
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-12">
                    <label for="address" class="form-label">Adres</label>
                    <textarea class="form-control" id="address" name="address" rows="2"><?php echo escape($city['address'] ?? ''); ?></textarea>
                </div>
            </div>
            
            <div class="row mb-3">
                <div class="col-md-12">
                    <label class="form-label">Kapak Görseli</label>
                    <div class="input-group">
                        <input type="url" class="form-control" id="cover_image_url" name="cover_image_url" value="<?php echo escape($city['cover_image_url'] ?? ''); ?>" placeholder="Kapak Görseli URL">
                        <button class="btn btn-outline-secondary" type="button" id="toggleCoverUpload">Resim Yükle</button>
                    </div>
                    <div id="coverFileUpload" class="mt-2" style="display:none;">
                        <input type="file" class="form-control" id="cover_image" name="cover_image" accept="image/*">
                        <div class="form-text">PNG, JPG veya GIF. Maks 5MB.</div>
                    </div>
                    <?php if(isset($city['cover_image_url']) && !empty($city['cover_image_url'])): ?>
                    <div class="mt-2">
                        <img src="<?php echo escape($city['cover_image_url']); ?>" alt="Mevcut Kapak" class="img-thumbnail" style="max-height: 100px;">
                    </div>
                    <?php endif; ?>
                </div>
            </div>
            
            <div class="row mt-4">
                <div class="col-12">
                    <button type="submit" name="update_city" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i> Değişiklikleri Kaydet
                    </button>
                    <a href="index.php?page=cities" class="btn btn-secondary ms-2">
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

<?php if (isset($city['logo_url']) && !empty($city['logo_url'])): ?>
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-image me-1"></i>
        Şehir Logosu
    </div>
    <div class="card-body text-center">
        <img src="<?php echo escape($city['logo_url']); ?>" alt="<?php echo escape($city['name']); ?> Logo" class="img-fluid" style="max-height: 200px;">
    </div>
</div>
<?php endif; ?>