<?php
// Belediye yönetim sistemi giriş sayfası - Yeni entegre sistem
require_once(__DIR__ . '/../config/config.php');

// Zaten giriş yapmışsa dashboard'a yönlendir
if (isLoggedIn()) {
    redirect('index.php?page=dashboard');
}

$error = '';
$success = '';

// Giriş formu işleme
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $email = trim($_POST['email'] ?? '');
    $password = $_POST['password'] ?? '';
    $login_type = $_POST['login_type'] ?? 'admin';
    
    if (empty($email) || empty($password)) {
        $error = 'E-posta ve şifre gereklidir.';
    } else {
        if ($login_type === 'admin') {
            // Admin giriş kontrolleri
            $admin_emails = [
                'mail@muzaffersanli.com' => '005434677197',
                'admin@belediye.gov.tr' => 'admin123',
                'yonetici@belediye.gov.tr' => 'yonetici2024'
            ];
            
            if (isset($admin_emails[$email]) && $admin_emails[$email] === $password) {
                // Admin girişi başarılı
                $_SESSION['admin_logged_in'] = true;
                $_SESSION['user_id'] = 'admin-' . md5($email);
                $_SESSION['user_email'] = $email;
                $_SESSION['user_type'] = 'admin';
                $_SESSION['login_time'] = time();
                
                redirect('index.php?page=dashboard');
            } else {
                $error = 'Geçersiz admin bilgileri.';
            }
        } else {
            // Belediye personeli/moderatör girişi
            $users_result = getData('users', [
                'email' => 'eq.' . $email,
                'limit' => 1
            ]);
            
            if (!$users_result['error'] && !empty($users_result['data'])) {
                $user = $users_result['data'][0];
                $user_role = $user['role'] ?? 'user';
                
                // Test için herhangi bir şifreyi kabul et
                if (!empty($password)) {
                    // Sadece admin, moderator, official rolündeki kullanıcılar giriş yapabilir
                    if (in_array($user_role, ['admin', 'moderator', 'official'])) {
                        // Officials tablosundan personel bilgilerini kontrol et
                        $officials_result = getData('officials', [
                            'user_id' => 'eq.' . $user['id'],
                            'limit' => 1
                        ]);
                        
                        $is_official = !$officials_result['error'] && !empty($officials_result['data']);
                        $official_data = $is_official ? $officials_result['data'][0] : null;
                        
                        // Session bilgilerini ayarla
                        $_SESSION['admin_logged_in'] = true;
                        $_SESSION['user_id'] = $user['id'];
                        $_SESSION['user_email'] = $user['email'];
                        $_SESSION['user_name'] = $user['full_name'] ?? $user['username'] ?? $user['email'];
                        $_SESSION['user_type'] = $user_role;
                        $_SESSION['login_time'] = time();
                        
                        // Atanmış şehir/ilçe bilgilerini ayarla
                        if ($is_official && $official_data) {
                            $_SESSION['official_id'] = $official_data['id'];
                            $_SESSION['assigned_city_id'] = $official_data['city_id'];
                            $_SESSION['assigned_district_id'] = $official_data['district_id'];
                            $_SESSION['official_title'] = $official_data['title'] ?? 'Belediye Personeli';
                            
                            // Şehir adını getir
                            if ($official_data['city_id']) {
                                $city_result = getDataById('cities', $official_data['city_id']);
                                if (!$city_result['error'] && $city_result['data']) {
                                    $_SESSION['assigned_city_name'] = $city_result['data']['name'];
                                }
                            }
                            
                            // İlçe adını getir
                            if ($official_data['district_id']) {
                                $district_result = getDataById('districts', $official_data['district_id']);
                                if (!$district_result['error'] && $district_result['data']) {
                                    $_SESSION['assigned_district_name'] = $district_result['data']['name'];
                                }
                            }
                        }
                        
                        redirect('index.php?page=dashboard');
                    } else {
                        $error = 'Bu hesap belediye paneline erişim yetkisine sahip değil.';
                    }
                } else {
                    $error = 'Geçersiz şifre.';
                }
            } else {
                $error = 'Kullanıcı bulunamadı.';
            }
        }
    }
}

// Sistem istatistikleri - Gerçek verilerden
$cities_result = getData('cities', ['select' => 'count']);
$total_cities = $cities_result['error'] ? 0 : ($cities_result['data'][0]['count'] ?? 0);

$districts_result = getData('districts', ['select' => 'count']);
$total_districts = $districts_result['error'] ? 0 : ($districts_result['data'][0]['count'] ?? 0);

$posts_result = getData('posts', ['select' => 'count']);
$total_posts = $posts_result['error'] ? 0 : ($posts_result['data'][0]['count'] ?? 0);

$users_result = getData('users', ['select' => 'count']);
$total_users = $users_result['error'] ? 0 : ($users_result['data'][0]['count'] ?? 0);
?>

<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Giriş - <?= SITE_TITLE ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
        }
        .login-container {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        .stats-card {
            background: linear-gradient(45deg, #4facfe 0%, #00f2fe 100%);
            color: white;
            border-radius: 15px;
            padding: 1.5rem;
            margin-bottom: 1rem;
            box-shadow: 0 8px 25px rgba(79, 172, 254, 0.3);
        }
        .login-form {
            padding: 3rem;
        }
        .form-control {
            border-radius: 10px;
            border: 2px solid #e9ecef;
            padding: 12px 15px;
        }
        .form-control:focus {
            border-color: #4facfe;
            box-shadow: 0 0 0 0.2rem rgba(79, 172, 254, 0.25);
        }
        .btn-login {
            background: linear-gradient(45deg, #4facfe 0%, #00f2fe 100%);
            border: none;
            border-radius: 10px;
            padding: 12px 30px;
            font-weight: 600;
            color: white;
            transition: all 0.3s ease;
        }
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(79, 172, 254, 0.3);
            color: white;
        }
        .login-tabs {
            border-bottom: 2px solid #e9ecef;
            margin-bottom: 2rem;
        }
        .nav-pills .nav-link {
            border-radius: 10px;
            margin-right: 10px;
            color: #6c757d;
            font-weight: 500;
        }
        .nav-pills .nav-link.active {
            background: linear-gradient(45deg, #4facfe 0%, #00f2fe 100%);
            color: white;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="row justify-content-center">
            <div class="col-xl-10 col-lg-12">
                <div class="login-container">
                    <div class="row g-0">
                        <!-- Sol taraf - İstatistikler -->
                        <div class="col-lg-6 p-4 d-flex flex-column justify-content-center">
                            <h2 class="text-center mb-4">
                                <i class="fas fa-city text-primary"></i>
                                Belediye Yönetim Sistemi
                            </h2>
                            
                            <div class="row">
                                <div class="col-6">
                                    <div class="stats-card text-center">
                                        <i class="fas fa-city fa-2x mb-2"></i>
                                        <h3><?= number_format($total_cities) ?></h3>
                                        <p class="mb-0">Şehir</p>
                                    </div>
                                </div>
                                <div class="col-6">
                                    <div class="stats-card text-center">
                                        <i class="fas fa-map-marker-alt fa-2x mb-2"></i>
                                        <h3><?= number_format($total_districts) ?></h3>
                                        <p class="mb-0">İlçe</p>
                                    </div>
                                </div>
                                <div class="col-6">
                                    <div class="stats-card text-center">
                                        <i class="fas fa-clipboard-list fa-2x mb-2"></i>
                                        <h3><?= number_format($total_posts) ?></h3>
                                        <p class="mb-0">Gönderi</p>
                                    </div>
                                </div>
                                <div class="col-6">
                                    <div class="stats-card text-center">
                                        <i class="fas fa-users fa-2x mb-2"></i>
                                        <h3><?= number_format($total_users) ?></h3>
                                        <p class="mb-0">Kullanıcı</p>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- Sağ taraf - Giriş formu -->
                        <div class="col-lg-6">
                            <div class="login-form">
                                <h3 class="text-center mb-4">Giriş Yap</h3>
                                
                                <?php if ($error): ?>
                                    <div class="alert alert-danger alert-dismissible fade show" role="alert">
                                        <i class="fas fa-exclamation-triangle me-2"></i>
                                        <?= escape($error) ?>
                                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                                    </div>
                                <?php endif; ?>
                                
                                <?php if ($success): ?>
                                    <div class="alert alert-success alert-dismissible fade show" role="alert">
                                        <i class="fas fa-check-circle me-2"></i>
                                        <?= escape($success) ?>
                                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                                    </div>
                                <?php endif; ?>
                                
                                <!-- Giriş tipi seçimi -->
                                <ul class="nav nav-pills justify-content-center login-tabs" id="login-tabs" role="tablist">
                                    <li class="nav-item" role="presentation">
                                        <button class="nav-link active" id="admin-tab" data-bs-toggle="pill" data-bs-target="#admin-login" type="button" role="tab">
                                            <i class="fas fa-user-shield me-2"></i>Yönetici
                                        </button>
                                    </li>
                                    <li class="nav-item" role="presentation">
                                        <button class="nav-link" id="official-tab" data-bs-toggle="pill" data-bs-target="#official-login" type="button" role="tab">
                                            <i class="fas fa-user-tie me-2"></i>Personel
                                        </button>
                                    </li>
                                </ul>
                                
                                <div class="tab-content" id="login-content">
                                    <!-- Admin Girişi -->
                                    <div class="tab-pane fade show active" id="admin-login" role="tabpanel">
                                        <form method="POST" action="">
                                            <input type="hidden" name="login_type" value="admin">
                                            <div class="mb-3">
                                                <label for="admin_email" class="form-label">
                                                    <i class="fas fa-envelope me-2"></i>E-posta
                                                </label>
                                                <input type="email" class="form-control" id="admin_email" name="email" 
                                                       placeholder="admin@belediye.gov.tr" value="mail@muzaffersanli.com" required>
                                            </div>
                                            <div class="mb-4">
                                                <label for="admin_password" class="form-label">
                                                    <i class="fas fa-lock me-2"></i>Şifre
                                                </label>
                                                <input type="password" class="form-control" id="admin_password" name="password" 
                                                       placeholder="Şifrenizi girin" value="005434677197" required>
                                            </div>
                                            <button type="submit" class="btn btn-login w-100">
                                                <i class="fas fa-sign-in-alt me-2"></i>Yönetici Girişi
                                            </button>
                                        </form>
                                    </div>
                                    
                                    <!-- Personel Girişi -->
                                    <div class="tab-pane fade" id="official-login" role="tabpanel">
                                        <form method="POST" action="">
                                            <input type="hidden" name="login_type" value="official">
                                            <div class="mb-3">
                                                <label for="official_email" class="form-label">
                                                    <i class="fas fa-envelope me-2"></i>E-posta
                                                </label>
                                                <input type="email" class="form-control" id="official_email" name="email" 
                                                       placeholder="personel@belediye.gov.tr" required>
                                            </div>
                                            <div class="mb-4">
                                                <label for="official_password" class="form-label">
                                                    <i class="fas fa-lock me-2"></i>Şifre
                                                </label>
                                                <input type="password" class="form-control" id="official_password" name="password" 
                                                       placeholder="Şifrenizi girin" required>
                                            </div>
                                            <button type="submit" class="btn btn-login w-100">
                                                <i class="fas fa-sign-in-alt me-2"></i>Personel Girişi
                                            </button>
                                        </form>
                                    </div>
                                </div>
                                
                                <div class="text-center mt-4">
                                    <small class="text-muted">
                                        <i class="fas fa-shield-alt me-1"></i>
                                        Güvenli bağlantı ile korunmaktadır
                                    </small>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>