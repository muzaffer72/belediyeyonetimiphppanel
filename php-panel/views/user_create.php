<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// Admin kontrolü
if (!isset($_SESSION['user_id']) || !isset($_SESSION['role']) || $_SESSION['role'] !== 'admin') {
    $_SESSION['message'] = 'Bu sayfaya erişim yetkiniz bulunmamaktadır!';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php');
        exit;
    } else {
        echo '<script>window.location.href = "index.php";</script>';
        exit;
    }
}

// Rol listesi
$roles = [
    'user' => 'Normal Kullanıcı',
    'moderator' => 'Moderatör',
    'admin' => 'Yönetici'
];

// Şehir listesi
$cities_result = getData('cities', ['order' => 'name.asc']);
$cities = $cities_result['data'] ?? [];

// Form gönderildi mi kontrolü
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['create_user'])) {
    // Form verilerini al
    $username = isset($_POST['username']) ? trim($_POST['username']) : '';
    $email = isset($_POST['email']) ? trim($_POST['email']) : '';
    $password = isset($_POST['password']) ? trim($_POST['password']) : '';
    $password_confirm = isset($_POST['password_confirm']) ? trim($_POST['password_confirm']) : '';
    $city = isset($_POST['city']) ? trim($_POST['city']) : '';
    $district = isset($_POST['district']) ? trim($_POST['district']) : '';
    $role = isset($_POST['role']) ? trim($_POST['role']) : 'user';
    $phone_number = isset($_POST['phone_number']) && trim($_POST['phone_number']) !== '' ? 
        trim($_POST['phone_number']) : null;
    
    $error = false;
    $error_message = '';
    
    // Validasyon kontrolleri
    if (empty($username)) {
        $error = true;
        $error_message = 'Kullanıcı adı boş olamaz!';
    } elseif (empty($email)) {
        $error = true;
        $error_message = 'E-posta adresi boş olamaz!';
    } elseif (empty($password)) {
        $error = true;
        $error_message = 'Şifre boş olamaz!';
    } elseif ($password !== $password_confirm) {
        $error = true;
        $error_message = 'Şifreler eşleşmiyor!';
    } elseif (strlen($password) < 6) {
        $error = true;
        $error_message = 'Şifre en az 6 karakter olmalıdır!';
    }
    
    // E-posta ve kullanıcı adı mevcutsa kontrol et
    if (!$error) {
        $check_result = getData('users', [
            'or' => '(username.eq.' . $username . ',email.eq.' . $email . ')'
        ]);
        
        if (!$check_result['error'] && !empty($check_result['data'])) {
            $error = true;
            $error_message = 'Bu kullanıcı adı veya e-posta adresi zaten kullanılıyor!';
        }
    }
    
    // Hata yoksa kullanıcıyı ekle
    if (!$error) {
        // Şifreyi hashle
        $hashed_password = password_hash($password, PASSWORD_DEFAULT);
        
        // Profil resmi yükleme işlemi
        $profile_image_url = null;
        if (isset($_FILES['profile_image']) && $_FILES['profile_image']['error'] === UPLOAD_ERR_OK) {
            $upload_dir = __DIR__ . '/../uploads/profiles/';
            
            // Upload klasörünün mevcut olup olmadığını kontrol et
            if (!is_dir($upload_dir)) {
                mkdir($upload_dir, 0777, true);
            }
            
            $file_extension = pathinfo($_FILES['profile_image']['name'], PATHINFO_EXTENSION);
            $file_name = uniqid() . '.' . $file_extension;
            $target_file = $upload_dir . $file_name;
            
            // Dosyayı yükle
            if (move_uploaded_file($_FILES['profile_image']['tmp_name'], $target_file)) {
                // Yükleme başarılı, URL'i güncelle
                $profile_image_url = SITE_URL . '/uploads/profiles/' . $file_name;
            } else {
                $_SESSION['message'] = 'Profil resmi yüklenirken bir hata oluştu!';
                $_SESSION['message_type'] = 'danger';
            }
        }
        
        // Kullanıcı verilerini oluştur
        $user_data = [
            'username' => $username,
            'email' => $email,
            'password' => $hashed_password,
            'role' => $role,
            'created_at' => date('Y-m-d H:i:s'),
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        // Boş olabilecek alanları kontrol et ve ekle
        if (!empty($city)) {
            $user_data['city'] = $city;
        }
        
        if (!empty($district)) {
            $user_data['district'] = $district;
        }
        
        // Null olmayan alanları ekle
        if ($profile_image_url !== null) {
            $user_data['profile_image_url'] = $profile_image_url;
        }
        
        if ($phone_number !== null) {
            $user_data['phone_number'] = $phone_number;
        }
        
        // Veritabanına ekle
        $insert_result = addData('users', $user_data);
        
        if (!$insert_result['error']) {
            $_SESSION['message'] = 'Kullanıcı başarıyla oluşturuldu.';
            $_SESSION['message_type'] = 'success';
            
            // Kullanıcılar sayfasına yönlendir
            if (!headers_sent()) {
                header('Location: index.php?page=users');
                exit;
            } else {
                echo '<script>window.location.href = "index.php?page=users";</script>';
                exit;
            }
        } else {
            $error = true;
            $error_message = 'Kullanıcı oluşturulurken bir hata oluştu: ' . ($insert_result['message'] ?? 'Bilinmeyen hata');
        }
    }
    
    // Hata varsa mesaj göster
    if ($error) {
        $_SESSION['message'] = $error_message;
        $_SESSION['message_type'] = 'danger';
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Yeni Kullanıcı Ekle</h1>
    
    <div>
        <a href="index.php?page=users" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Kullanıcılara Dön
        </a>
    </div>
</div>

<!-- İşlem Mesajları -->
<?php if(isset($_SESSION['message'])): ?>
<div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
    <?php echo $_SESSION['message']; ?>
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>
<?php 
    unset($_SESSION['message']);
    unset($_SESSION['message_type']);
endif; 
?>

<div class="row">
    <div class="col-lg-8">
        <!-- Kullanıcı Bilgileri Formu -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-user-plus me-1"></i> Kullanıcı Bilgileri
            </div>
            <div class="card-body">
                <form action="" method="post" enctype="multipart/form-data">
                    <input type="hidden" name="create_user" value="1">
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="username" class="form-label">Kullanıcı Adı <span class="text-danger">*</span></label>
                            <input type="text" class="form-control" id="username" name="username" value="<?php echo isset($_POST['username']) ? escape($_POST['username']) : ''; ?>" required>
                        </div>
                        
                        <div class="col-md-6">
                            <label for="email" class="form-label">E-posta Adresi <span class="text-danger">*</span></label>
                            <input type="email" class="form-control" id="email" name="email" value="<?php echo isset($_POST['email']) ? escape($_POST['email']) : ''; ?>" required>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="password" class="form-label">Şifre <span class="text-danger">*</span></label>
                            <input type="password" class="form-control" id="password" name="password" required>
                            <div class="form-text">En az 6 karakter olmalıdır.</div>
                        </div>
                        
                        <div class="col-md-6">
                            <label for="password_confirm" class="form-label">Şifre Tekrar <span class="text-danger">*</span></label>
                            <input type="password" class="form-control" id="password_confirm" name="password_confirm" required>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="city" class="form-label">Şehir</label>
                            <select class="form-select" id="city" name="city" onchange="getDistricts(this.value, 'district')">
                                <option value="">Şehir Seçin...</option>
                                <?php foreach ($cities as $city): ?>
                                    <option value="<?php echo escape($city['name']); ?>" <?php echo (isset($_POST['city']) && $_POST['city'] === $city['name']) ? 'selected' : ''; ?>>
                                        <?php echo escape($city['name']); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        
                        <div class="col-md-6">
                            <label for="district" class="form-label">İlçe</label>
                            <select class="form-select" id="district" name="district">
                                <option value="">İlçe Seçin...</option>
                                <!-- İlçeler AJAX ile doldurulacak -->
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="role" class="form-label">Kullanıcı Rolü <span class="text-danger">*</span></label>
                            <select class="form-select" id="role" name="role" required>
                                <?php foreach ($roles as $role_key => $role_name): ?>
                                    <option value="<?php echo $role_key; ?>" <?php echo (isset($_POST['role']) && $_POST['role'] === $role_key) ? 'selected' : ($role_key === 'user' ? 'selected' : ''); ?>>
                                        <?php echo $role_name; ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        
                        <div class="col-md-6">
                            <label for="phone_number" class="form-label">Telefon Numarası</label>
                            <input type="tel" class="form-control" id="phone_number" name="phone_number" value="<?php echo isset($_POST['phone_number']) ? escape($_POST['phone_number']) : ''; ?>">
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label for="profile_image" class="form-label">Profil Resmi</label>
                        <input type="file" class="form-control" id="profile_image" name="profile_image" accept="image/*">
                    </div>
                    
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i> Kullanıcı Oluştur
                    </button>
                </form>
            </div>
        </div>
    </div>
    
    <div class="col-lg-4">
        <!-- Bilgi Kartı -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-info-circle me-1"></i> Kullanıcı Oluşturma Bilgileri
            </div>
            <div class="card-body">
                <p>Yeni bir kullanıcı oluşturmak için formu doldurun.</p>
                <hr>
                <h6><i class="fas fa-exclamation-triangle text-warning me-1"></i> Önemli Notlar:</h6>
                <ul class="small">
                    <li>Kullanıcı adı ve e-posta adresi benzersiz olmalıdır.</li>
                    <li>Şifre en az 6 karakter uzunluğunda olmalıdır.</li>
                    <li>Kullanıcı rolü, sistemdeki yetkilerini belirler:
                        <ul>
                            <li><strong>Normal Kullanıcı:</strong> Sınırlı erişim yetkileri</li>
                            <li><strong>Moderatör:</strong> İçerik yönetimi yetkileri</li>
                            <li><strong>Yönetici:</strong> Tam sistem yetkileri</li>
                        </ul>
                    </li>
                    <li>Şehir ve ilçe bilgileri opsiyoneldir.</li>
                    <li>Profil resmi opsiyoneldir.</li>
                </ul>
            </div>
        </div>
    </div>
</div>

<!-- İlçeleri getirmek için JavaScript -->
<script>
function getDistricts(cityName, targetElementId) {
    if (!cityName) {
        document.getElementById(targetElementId).innerHTML = '<option value="">İlçe Seçin...</option>';
        return;
    }
    
    // AJAX isteği
    const xhr = new XMLHttpRequest();
    xhr.open('GET', 'views/get_districts.php?city_name=' + encodeURIComponent(cityName), true);
    
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            const districtSelect = document.getElementById(targetElementId);
            districtSelect.innerHTML = '<option value="">İlçe Seçin...</option>';
            
            if (xhr.status === 200) {
                try {
                    const response = JSON.parse(xhr.responseText);
                    
                    if (!response.error && response.data && Array.isArray(response.data)) {
                        response.data.forEach(district => {
                            const option = document.createElement('option');
                            option.value = district.name;
                            option.textContent = district.name;
                            districtSelect.appendChild(option);
                        });
                    }
                } catch (e) {
                    console.error('JSON ayrıştırma hatası:', e);
                }
            }
        }
    };
    
    xhr.send();
}
</script>