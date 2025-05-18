<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// ID parametresi kontrolü
if (!isset($_GET['id'])) {
    $_SESSION['message'] = 'Kullanıcı ID\'si belirtilmedi!';
    $_SESSION['message_type'] = 'danger';
    
    // Kullanıcılar sayfasına yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
}

$user_id = $_GET['id'];

// Kullanıcı verisini doğrudan al (filter kullanarak)
$users_result = getData('users', [
    'id' => 'eq.' . $user_id
]);

// Kullanıcı bulunamadıysa hata ver
if ($users_result['error'] || empty($users_result['data'])) {
    $_SESSION['message'] = 'Kullanıcı bulunamadı!';
    $_SESSION['message_type'] = 'danger';
    
    // Kullanıcılar sayfasına yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
}

$user = $users_result['data'][0];

// Rol listesi
$roles = [
    'user' => 'Normal Kullanıcı',
    'moderator' => 'Moderatör',
    'admin' => 'Yönetici'
];

// Şehir listesi
$cities_result = getData('cities');
$cities = $cities_result['data'] ?? [];

// İlçe listesi
$districts_result = getData('districts');
$all_districts = $districts_result['data'] ?? [];

// Seçili şehrin ilçeleri
$selected_city_districts = [];
if (isset($user['city']) && !empty($user['city'])) {
    foreach ($all_districts as $district) {
        $district_city_name = '';
        
        // İlçenin şehir adını bul
        if (isset($district['city_id'])) {
            foreach ($cities as $city) {
                if (isset($city['id']) && $city['id'] === $district['city_id']) {
                    $district_city_name = $city['name'];
                    break;
                }
            }
        }
        
        // Bu ilçe, kullanıcının şehrine aitse ekle
        if ($district_city_name === $user['city']) {
            $selected_city_districts[] = $district;
        }
    }
}

// Form gönderildi mi kontrolü
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_user'])) {
    // Form verilerini al
    $username = isset($_POST['username']) ? trim($_POST['username']) : '';
    $email = isset($_POST['email']) ? trim($_POST['email']) : '';
    $city = isset($_POST['city']) ? trim($_POST['city']) : '';
    $district = isset($_POST['district']) ? trim($_POST['district']) : '';
    $role = isset($_POST['role']) ? trim($_POST['role']) : 'user';
    $phone_number = isset($_POST['phone_number']) ? trim($_POST['phone_number']) : null;

    // Profil resmi değiştirildi mi?
    $profile_image_url = $user['profile_image_url'] ?? null;
    
    if (isset($_FILES['profile_image']) && $_FILES['profile_image']['error'] === UPLOAD_ERR_OK) {
        $upload_dir = __DIR__ . '/../uploads/profiles/';
        
        // Upload klasörünün mevcut olup olmadığını kontrol et
        if (!is_dir($upload_dir)) {
            mkdir($upload_dir, 0777, true);
        }
        
        $file_extension = pathinfo($_FILES['profile_image']['name'], PATHINFO_EXTENSION);
        $file_name = $user_id . '-' . uniqid() . '.' . $file_extension;
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
    
    // Kullanıcı verilerini güncelle
    $update_data = [
        'username' => $username,
        'email' => $email,
        'city' => $city,
        'district' => $district,
        'role' => $role,
        'updated_at' => date('Y-m-d H:i:s')
    ];
    
    // Null olmayan alanları ekle
    if ($profile_image_url !== null) {
        $update_data['profile_image_url'] = $profile_image_url;
    }
    
    if ($phone_number !== null) {
        $update_data['phone_number'] = $phone_number;
    }
    
    // Veritabanını güncelle
    $update_result = updateData('users', $user_id, $update_data);
    
    if (!$update_result['error']) {
        $_SESSION['message'] = 'Kullanıcı bilgileri başarıyla güncellendi.';
        $_SESSION['message_type'] = 'success';
        
        // Kullanıcı sayfasına yönlendir
        if (!headers_sent()) {
            header('Location: index.php?page=users');
            exit;
        } else {
            echo '<script>window.location.href = "index.php?page=users";</script>';
            exit;
        }
    } else {
        $_SESSION['message'] = 'Kullanıcı bilgileri güncellenirken bir hata oluştu: ' . $update_result['message'];
        $_SESSION['message_type'] = 'danger';
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Kullanıcı Düzenle</h1>
    
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
    <div class="col-md-8">
        <!-- Kullanıcı Bilgileri Formu -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-user-edit me-1"></i> Kullanıcı Bilgileri
            </div>
            <div class="card-body">
                <form action="" method="post" enctype="multipart/form-data">
                    <input type="hidden" name="update_user" value="1">
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="username" class="form-label">Kullanıcı Adı <span class="text-danger">*</span></label>
                            <input type="text" class="form-control" id="username" name="username" value="<?php echo escape($user['username'] ?? ''); ?>" required>
                        </div>
                        
                        <div class="col-md-6">
                            <label for="email" class="form-label">E-posta Adresi <span class="text-danger">*</span></label>
                            <input type="email" class="form-control" id="email" name="email" value="<?php echo escape($user['email'] ?? ''); ?>" required>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="city" class="form-label">Şehir</label>
                            <select class="form-select" id="city" name="city">
                                <option value="">Şehir Seçin...</option>
                                <?php foreach ($cities as $city): ?>
                                    <option value="<?php echo escape($city['name']); ?>" <?php echo (isset($user['city']) && $user['city'] === $city['name']) ? 'selected' : ''; ?>>
                                        <?php echo escape($city['name']); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        
                        <div class="col-md-6">
                            <label for="district" class="form-label">İlçe</label>
                            <select class="form-select" id="district" name="district">
                                <option value="">İlçe Seçin...</option>
                                <?php foreach ($selected_city_districts as $district): ?>
                                    <option value="<?php echo escape($district['name']); ?>" <?php echo (isset($user['district']) && $user['district'] === $district['name']) ? 'selected' : ''; ?>>
                                        <?php echo escape($district['name']); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="role" class="form-label">Kullanıcı Rolü <span class="text-danger">*</span></label>
                            <select class="form-select" id="role" name="role" required>
                                <?php foreach ($roles as $role_key => $role_name): ?>
                                    <option value="<?php echo $role_key; ?>" <?php echo (isset($user['role']) && $user['role'] === $role_key) ? 'selected' : ''; ?>>
                                        <?php echo $role_name; ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        
                        <div class="col-md-6">
                            <label for="phone_number" class="form-label">Telefon Numarası</label>
                            <input type="tel" class="form-control" id="phone_number" name="phone_number" value="<?php echo escape($user['phone_number'] ?? ''); ?>">
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="profile_image" class="form-label">Profil Resmi</label>
                            <input type="file" class="form-control" id="profile_image" name="profile_image" accept="image/*">
                            <div class="form-text">Yeni bir resim yüklemek için seçin veya mevcut resmi korumak için boş bırakın.</div>
                        </div>
                        
                        <div class="col-md-6">
                            <label class="form-label">Mevcut Profil Resmi</label>
                            <div>
                                <?php if (isset($user['profile_image_url']) && !empty($user['profile_image_url'])): ?>
                                    <img src="<?php echo escape($user['profile_image_url']); ?>" alt="Profil Resmi" class="img-thumbnail" style="max-height: 100px;">
                                <?php else: ?>
                                    <div class="alert alert-light">Profil resmi yok</div>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                    
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i> Değişiklikleri Kaydet
                    </button>
                </form>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <!-- Kullanıcı Bilgileri Kartı -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-info-circle me-1"></i> Kullanıcı Detayları
            </div>
            <div class="card-body">
                <div class="text-center mb-3">
                    <?php if (isset($user['profile_image_url']) && !empty($user['profile_image_url'])): ?>
                        <img src="<?php echo escape($user['profile_image_url']); ?>" alt="<?php echo escape($user['username']); ?>" class="img-fluid rounded-circle" style="max-width: 150px; max-height: 150px;">
                    <?php else: ?>
                        <div class="avatar bg-secondary text-white rounded-circle d-flex align-items-center justify-content-center" style="width: 150px; height: 150px; margin: 0 auto;">
                            <i class="fas fa-user fa-5x"></i>
                        </div>
                    <?php endif; ?>
                </div>
                
                <h5 class="text-center mb-3"><?php echo escape($user['username'] ?? 'Belirsiz'); ?></h5>
                
                <ul class="list-group list-group-flush">
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        <span><i class="fas fa-user me-2"></i> Kullanıcı ID:</span>
                        <span class="badge bg-secondary"><?php echo substr($user['id'], 0, 8) . '...'; ?></span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        <span><i class="fas fa-calendar-alt me-2"></i> Kayıt Tarihi:</span>
                        <span><?php echo isset($user['created_at']) ? date('d.m.Y', strtotime($user['created_at'])) : '-'; ?></span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        <span><i class="fas fa-clock me-2"></i> Son Güncelleme:</span>
                        <span><?php echo isset($user['updated_at']) ? date('d.m.Y H:i', strtotime($user['updated_at'])) : '-'; ?></span>
                    </li>
                </ul>
            </div>
        </div>
        
        <!-- İstatistik Kartı -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-chart-pie me-1"></i> Kullanıcı İstatistikleri
            </div>
            <div class="card-body">
                <?php
                // Kullanıcının gönderilerini say
                $posts_count_result = getData('posts', [
                    'user_id' => 'eq.' . $user_id,
                    'select' => 'count'
                ]);
                $posts_count = $posts_count_result['data'] ?? 0;
                
                // Kullanıcının yorumlarını say
                $comments_count_result = getData('comments', [
                    'user_id' => 'eq.' . $user_id,
                    'select' => 'count'
                ]);
                $comments_count = $comments_count_result['data'] ?? 0;
                
                // Kullanıcının beğenilerini say
                $likes_count_result = getData('likes', [
                    'user_id' => 'eq.' . $user_id,
                    'select' => 'count'
                ]);
                $likes_count = $likes_count_result['data'] ?? 0;
                ?>
                
                <div class="d-flex justify-content-between">
                    <div class="text-center">
                        <h5><?php echo $posts_count; ?></h5>
                        <p class="mb-0 text-muted">Gönderi</p>
                    </div>
                    <div class="text-center">
                        <h5><?php echo $comments_count; ?></h5>
                        <p class="mb-0 text-muted">Yorum</p>
                    </div>
                    <div class="text-center">
                        <h5><?php echo $likes_count; ?></h5>
                        <p class="mb-0 text-muted">Beğeni</p>
                    </div>
                </div>
                
                <div class="mt-3">
                    <a href="index.php?page=posts&user_id=<?php echo $user_id; ?>" class="btn btn-sm btn-outline-secondary w-100 mb-2">
                        <i class="fas fa-clipboard-list me-1"></i> Kullanıcı Gönderilerini Görüntüle
                    </a>
                    <a href="index.php?page=comments&user_id=<?php echo $user_id; ?>" class="btn btn-sm btn-outline-secondary w-100">
                        <i class="fas fa-comments me-1"></i> Kullanıcı Yorumlarını Görüntüle
                    </a>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
// Şehir değiştiğinde ilçeleri güncelle
document.getElementById('city').addEventListener('change', function() {
    const cityName = this.value;
    const districtSelect = document.getElementById('district');
    
    // İlçe dropdown'ını temizle
    districtSelect.innerHTML = '<option value="">İlçe Seçin...</option>';
    
    if (cityName) {
        // İlgili şehrin ilçelerini al
        fetch('index.php?page=api&action=get_districts_by_city&city=' + encodeURIComponent(cityName))
            .then(response => response.json())
            .then(data => {
                if (data && data.length > 0) {
                    // İlçeleri dropdown'a ekle
                    data.forEach(district => {
                        const option = document.createElement('option');
                        option.value = district.name;
                        option.textContent = district.name;
                        districtSelect.appendChild(option);
                    });
                }
            })
            .catch(error => {
                console.error('İlçeler alınırken bir hata oluştu:', error);
                // Manuel olarak da devam edebiliriz - sayfayı yenilemekle:
                if (cityName) {
                    window.location.href = 'index.php?page=user_edit&id=<?php echo $user_id; ?>&city=' + encodeURIComponent(cityName);
                }
            });
    }
});
</script>