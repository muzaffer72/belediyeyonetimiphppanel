<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Sadece belediye görevlisi erişimi kontrolü
if (!isLoggedIn() || !isset($_SESSION['is_official']) || !$_SESSION['is_official']) {
    redirect('index.php?page=official_login');
}

// Görevli bilgilerini al
$city_id = $_SESSION['city_id'] ?? null;
$district_id = $_SESSION['district_id'] ?? null;
$city_name = $_SESSION['city_name'] ?? 'Bilinmiyor';
$district_name = $_SESSION['district_name'] ?? 'Bilinmiyor';

$success_message = '';
$error_message = '';

// Oturum değişkenlerinden şehir veya ilçe bilgilerini al
if ($district_id) {
    // İlçe bilgilerini session'dan al (test verileri)
    $district = isset($_SESSION['district_info']) ? $_SESSION['district_info'] : [
        'id' => $district_id,
        'city_id' => $city_id,
        'name' => $district_name,
        'population' => 482713,
        'mayor' => 'Örnek İlçe Belediye Başkanı',
        'website' => 'https://www.kadikoy.bel.tr',
        'description' => 'Kadıköy, İstanbul\'un en eski yerleşim yerlerinden biridir.',
        'logo_url' => 'https://upload.wikimedia.org/wikipedia/tr/4/4e/Kad%C4%B1k%C3%B6y_Belediyesi_logosu.png',
        'founded_at' => '1984-01-01',
        'contact_email' => 'info@kadikoy.bel.tr',
        'contact_phone' => '444 55 22'
    ];
} elseif ($city_id) {
    // Şehir bilgilerini session'dan al (test verileri)
    $city = isset($_SESSION['city_info']) ? $_SESSION['city_info'] : [
        'id' => $city_id,
        'name' => $city_name,
        'population' => 15840900,
        'website' => 'https://www.istanbul.bel.tr',
        'mayor' => 'Örnek İsim',
        'description' => 'İstanbul, Türkiye\'nin en büyük şehridir.',
        'logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/5/52/Istanbul_Metropolitan_Municipality_logo.png',
        'founded_at' => '1984-01-01',
        'contact_email' => 'info@ibb.gov.tr',
        'contact_phone' => '153'
    ];
}

// Formu işle
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['update_district']) && $district_id) {
        // İlçe bilgilerini güncelle
        $description = $_POST['description'] ?? '';
        $website = $_POST['website'] ?? '';
        $phone = $_POST['phone'] ?? '';
        $email = $_POST['email'] ?? '';
        $address = $_POST['address'] ?? '';
        $mayor_name = $_POST['mayor_name'] ?? '';
        $social_media = [
            'facebook' => $_POST['facebook'] ?? '',
            'twitter' => $_POST['twitter'] ?? '',
            'instagram' => $_POST['instagram'] ?? ''
        ];
        
        $update_data = [
            'description' => $description,
            'website' => $website,
            'phone' => $phone,
            'email' => $email,
            'address' => $address,
            'mayor_name' => $mayor_name,
            'social_media' => $social_media,
            'updated_at' => date('c')
        ];
        
        $update_result = updateData('districts', $district_id, $update_data);
        
        if (!$update_result['error']) {
            $success_message = "İlçe bilgileri başarıyla güncellendi!";
        } else {
            $error_message = "İlçe bilgileri güncellenirken hata oluştu: " . ($update_result['message'] ?? 'Bilinmeyen hata');
        }
    } elseif (isset($_POST['update_city']) && $city_id) {
        // Şehir bilgilerini güncelle
        $description = $_POST['description'] ?? '';
        $website = $_POST['website'] ?? '';
        $phone = $_POST['phone'] ?? '';
        $email = $_POST['email'] ?? '';
        $address = $_POST['address'] ?? '';
        $mayor_name = $_POST['mayor_name'] ?? '';
        $social_media = [
            'facebook' => $_POST['facebook'] ?? '',
            'twitter' => $_POST['twitter'] ?? '',
            'instagram' => $_POST['instagram'] ?? ''
        ];
        
        $update_data = [
            'description' => $description,
            'website' => $website,
            'phone' => $phone,
            'email' => $email,
            'address' => $address,
            'mayor_name' => $mayor_name,
            'social_media' => $social_media,
            'updated_at' => date('c')
        ];
        
        $update_result = updateData('cities', $city_id, $update_data);
        
        if (!$update_result['error']) {
            $success_message = "Şehir bilgileri başarıyla güncellendi!";
        } else {
            $error_message = "Şehir bilgileri güncellenirken hata oluştu: " . ($update_result['message'] ?? 'Bilinmeyen hata');
        }
    }
    
    // Resim yükleme işlemi
    if (isset($_FILES['logo']) && $_FILES['logo']['error'] == 0) {
        $allowed_types = ['image/jpeg', 'image/png', 'image/gif'];
        $max_size = 5 * 1024 * 1024; // 5MB
        
        if (in_array($_FILES['logo']['type'], $allowed_types) && $_FILES['logo']['size'] <= $max_size) {
            // Resmi kaydet
            $upload_dir = __DIR__ . '/../../uploads/municipalities/';
            
            // Klasör yoksa oluştur
            if (!file_exists($upload_dir)) {
                mkdir($upload_dir, 0777, true);
            }
            
            $file_extension = pathinfo($_FILES['logo']['name'], PATHINFO_EXTENSION);
            $file_name = ($district_id ? 'district_' . $district_id : 'city_' . $city_id) . '_' . time() . '.' . $file_extension;
            $upload_path = $upload_dir . $file_name;
            
            if (move_uploaded_file($_FILES['logo']['tmp_name'], $upload_path)) {
                // Veritabanında logo URL'sini güncelle
                $logo_url = '/uploads/municipalities/' . $file_name;
                
                if ($district_id) {
                    updateData('districts', $district_id, ['logo_url' => $logo_url]);
                } elseif ($city_id) {
                    updateData('cities', $city_id, ['logo_url' => $logo_url]);
                }
                
                $success_message .= " Logo başarıyla güncellendi.";
            } else {
                $error_message .= " Logo yüklenirken bir hata oluştu.";
            }
        } else {
            $error_message .= " Lütfen geçerli bir resim dosyası yükleyin (JPEG, PNG, GIF, max 5MB).";
        }
    }
    
    // Güncel verileri yeniden al
    if ($district_id) {
        $district_result = getData('districts', [
            'select' => '*',
            'filters' => ['id' => 'eq.' . $district_id]
        ]);
        
        $district = !$district_result['error'] && !empty($district_result['data']) 
                  ? $district_result['data'][0] 
                  : null;
    } elseif ($city_id) {
        $city_result = getData('cities', [
            'select' => '*',
            'filters' => ['id' => 'eq.' . $city_id]
        ]);
        
        $city = !$city_result['error'] && !empty($city_result['data']) 
              ? $city_result['data'][0] 
              : null;
    }
}

// Düzenlenecek veri
$edit_data = $district ?? $city ?? null;
?>

<!-- Başlık ve Butonlar -->
<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3 mb-0">
        <i class="fas fa-building me-2"></i> 
        <?php echo $district_id ? 'İlçe' : 'Şehir'; ?> Bilgilerini Düzenle
    </h1>
    
    <div>
        <a href="index.php?page=official_dashboard" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Panele Dön
        </a>
    </div>
</div>

<!-- Uyarı ve Bilgilendirme Mesajları -->
<?php if (!empty($success_message)): ?>
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        <?php echo $success_message; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
    </div>
<?php endif; ?>

<?php if (!empty($error_message)): ?>
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        <?php echo $error_message; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
    </div>
<?php endif; ?>

<!-- Belediye Bilgi Formu -->
<?php if ($edit_data): ?>
    <div class="card mb-4">
        <div class="card-header">
            <i class="fas fa-edit me-1"></i>
            <?php echo $district_id ? htmlspecialchars($district_name) : htmlspecialchars($city_name); ?> Bilgileri
        </div>
        <div class="card-body">
            <form method="post" action="" enctype="multipart/form-data">
                <input type="hidden" name="<?php echo $district_id ? 'update_district' : 'update_city'; ?>" value="1">
                
                <div class="row">
                    <div class="col-md-6">
                        <div class="mb-3">
                            <label for="name" class="form-label">Adı</label>
                            <input type="text" class="form-control" id="name" value="<?php echo htmlspecialchars($district_id ? $district_name : $city_name); ?>" readonly>
                            <div class="form-text">Belediye adı sistem tarafından belirlenir ve değiştirilemez.</div>
                        </div>
                        
                        <div class="mb-3">
                            <label for="description" class="form-label">Açıklama</label>
                            <textarea class="form-control" id="description" name="description" rows="3"><?php echo htmlspecialchars($edit_data['description'] ?? ''); ?></textarea>
                            <div class="form-text">Belediye hakkında kısa bir açıklama yazın.</div>
                        </div>
                        
                        <div class="mb-3">
                            <label for="website" class="form-label">Web Sitesi</label>
                            <input type="url" class="form-control" id="website" name="website" value="<?php echo htmlspecialchars($edit_data['website'] ?? ''); ?>">
                        </div>
                        
                        <div class="mb-3">
                            <label for="phone" class="form-label">Telefon</label>
                            <input type="tel" class="form-control" id="phone" name="phone" value="<?php echo htmlspecialchars($edit_data['phone'] ?? ''); ?>">
                        </div>
                        
                        <div class="mb-3">
                            <label for="email" class="form-label">E-posta</label>
                            <input type="email" class="form-control" id="email" name="email" value="<?php echo htmlspecialchars($edit_data['email'] ?? ''); ?>">
                        </div>
                    </div>
                    
                    <div class="col-md-6">
                        <div class="mb-3">
                            <label for="address" class="form-label">Adres</label>
                            <textarea class="form-control" id="address" name="address" rows="3"><?php echo htmlspecialchars($edit_data['address'] ?? ''); ?></textarea>
                        </div>
                        
                        <div class="mb-3">
                            <label for="mayor_name" class="form-label">Belediye Başkanı</label>
                            <input type="text" class="form-control" id="mayor_name" name="mayor_name" value="<?php echo htmlspecialchars($edit_data['mayor_name'] ?? ''); ?>">
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">Sosyal Medya</label>
                            
                            <div class="input-group mb-2">
                                <span class="input-group-text"><i class="fab fa-facebook"></i></span>
                                <input type="text" class="form-control" id="facebook" name="facebook" placeholder="Facebook URL" value="<?php echo htmlspecialchars($edit_data['social_media']['facebook'] ?? ''); ?>">
                            </div>
                            
                            <div class="input-group mb-2">
                                <span class="input-group-text"><i class="fab fa-twitter"></i></span>
                                <input type="text" class="form-control" id="twitter" name="twitter" placeholder="Twitter URL" value="<?php echo htmlspecialchars($edit_data['social_media']['twitter'] ?? ''); ?>">
                            </div>
                            
                            <div class="input-group mb-2">
                                <span class="input-group-text"><i class="fab fa-instagram"></i></span>
                                <input type="text" class="form-control" id="instagram" name="instagram" placeholder="Instagram URL" value="<?php echo htmlspecialchars($edit_data['social_media']['instagram'] ?? ''); ?>">
                            </div>
                        </div>
                        
                        <div class="mb-3">
                            <label for="logo" class="form-label">Logo</label>
                            <?php if (!empty($edit_data['logo_url'])): ?>
                                <div class="mb-2">
                                    <img src="<?php echo htmlspecialchars($edit_data['logo_url']); ?>" alt="Logo" class="img-thumbnail" style="max-height: 100px;">
                                </div>
                            <?php endif; ?>
                            <input type="file" class="form-control" id="logo" name="logo">
                            <div class="form-text">Yeni bir logo yüklemek için dosya seçin. (JPEG, PNG, GIF, max 5MB)</div>
                        </div>
                    </div>
                </div>
                
                <div class="d-grid gap-2 d-md-flex justify-content-md-end">
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i> Değişiklikleri Kaydet
                    </button>
                </div>
            </form>
        </div>
    </div>
<?php else: ?>
    <div class="alert alert-warning">
        <i class="fas fa-exclamation-triangle me-2"></i> Düzenlenecek belediye bilgisi bulunamadı. Bir şehir veya ilçe ataması yapılması gerekiyor.
    </div>
<?php endif; ?>

<script>
    document.addEventListener('DOMContentLoaded', function() {
        // Form değişikliklerini izle
        const form = document.querySelector('form');
        if (form) {
            const originalFormData = new FormData(form);
            
            // Sayfadan ayrılma kontrolü
            window.addEventListener('beforeunload', function(e) {
                const currentFormData = new FormData(form);
                let formChanged = false;
                
                // Form verilerini karşılaştır
                for (const [key, value] of currentFormData.entries()) {
                    if (originalFormData.get(key) !== value) {
                        formChanged = true;
                        break;
                    }
                }
                
                if (formChanged) {
                    // Kullanıcıya uyarı göster
                    e.preventDefault();
                    e.returnValue = 'Kaydedilmemiş değişiklikler var. Sayfadan ayrılmak istediğinize emin misiniz?';
                }
            });
        }
    });
</script>