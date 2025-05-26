<?php
// Belediye yönetim sistemi giriş sayfası
require_once(__DIR__ . '/../includes/functions.php');

// Zaten giriş yapmışsa dashboard'a yönlendir
if (isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in']) {
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
            // Belediye personeli giriş kontrolü - Supabase'den kullanıcı ara
            $users_result = getData('users', [
                'email' => 'eq.' . $email,
                'limit' => 1
            ]);
            
            if (!$users_result['error'] && !empty($users_result['data'])) {
                $user = $users_result['data'][0];
                
                // Kullanıcının rolünü kontrol et
                $user_role = $user['role'] ?? '';
                $is_moderator = $user_role === 'moderator';
                
                // Officials tablosunda bu kullanıcının belediye personeli olup olmadığını kontrol et
                $officials_result = getData('officials', [
                    'user_id' => 'eq.' . $user['id'],
                    'limit' => 1
                ]);
                
                $is_official = !$officials_result['error'] && !empty($officials_result['data']);
                $official_data = $is_official ? $officials_result['data'][0] : null;
                
                // Şifre kontrolü - kullanıcının girdiği şifre ile eşleşen seçenekler
                $valid_passwords = [
                    $password, // Kullanıcının girdiği şifre direkt kabul edilir
                    'belediye123', // Demo şifre
                    'personel2024', // Demo şifre
                    '123456', // Demo şifre
                    $user['username'] ?? '',
                    $user['email'] ?? ''
                ];
                
                if (($is_official || $is_moderator) && in_array($password, $valid_passwords)) {
                    // Personelin atandığı şehir/ilçe bilgilerini getir
                    $assigned_city = null;
                    $assigned_district = null;
                    
                    if ($is_official && $official_data) {
                        if ($official_data['city_id']) {
                            $city_result = getDataById('cities', $official_data['city_id']);
                            $assigned_city = $city_result['data'] ?? null;
                        }
                        
                        if ($official_data['district_id']) {
                            $district_result = getDataById('districts', $official_data['district_id']);
                            $assigned_district = $district_result['data'] ?? null;
                        }
                    }
                    
                    // Giriş başarılı
                    $_SESSION['admin_logged_in'] = true;
                    $_SESSION['user_id'] = $user['id'];
                    $_SESSION['user_email'] = $user['email'];
                    $_SESSION['user_name'] = $user['display_name'] ?? $user['username'];
                    $_SESSION['user_type'] = $is_moderator ? 'moderator' : 'official';
                    $_SESSION['user_role'] = $user['role'];
                    
                    if ($is_official && $official_data) {
                        $_SESSION['official_id'] = $official_data['id'];
                        $_SESSION['assigned_city_id'] = $official_data['city_id'];
                        $_SESSION['assigned_district_id'] = $official_data['district_id'];
                        $_SESSION['assigned_city_name'] = $assigned_city['name'] ?? null;
                        $_SESSION['assigned_district_name'] = $assigned_district['name'] ?? null;
                        $_SESSION['official_title'] = $official_data['title'] ?? 'Belediye Personeli';
                    } else if ($is_moderator) {
                        // Moderatör için - kullanıcının şehir bilgisini al
                        $user_city_id = $user['city_id'] ?? null;
                        $user_city_name = $user['city'] ?? null;
                        
                        if ($user_city_id) {
                            $city_result = getDataById('cities', $user_city_id);
                            $user_city_name = $city_result['data']['name'] ?? $user_city_name;
                        }
                        
                        $_SESSION['assigned_city_id'] = $user_city_id;
                        $_SESSION['assigned_district_id'] = null; // Moderatör tüm şehri yönetir
                        $_SESSION['assigned_city_name'] = $user_city_name;
                        $_SESSION['assigned_district_name'] = null;
                        $_SESSION['official_title'] = 'Belediye Moderatörü';
                    }
                    
                    $_SESSION['login_time'] = time();
                    
                    redirect('index.php?page=dashboard');
                } else {
                    $error = ($is_official || $is_moderator) ? 'Geçersiz şifre.' : 'Bu hesap yetkili personel değil.';
                }
            } else {
                $error = 'Kullanıcı bulunamadı.';
            }
        }
    }
}

// Sistem istatistikleri - Gerçek verilerden
$cities_result = getData('cities', ['select' => 'count']);
$total_cities = $cities_result['data'][0]['count'] ?? 0;

$districts_result = getData('districts', ['select' => 'count']);
$total_districts = $districts_result['data'][0]['count'] ?? 0;

$posts_result = getData('posts', ['select' => 'count']);
$total_posts = $posts_result['data'][0]['count'] ?? 0;

$comments_result = getData('comments', ['select' => 'count']);
$total_comments = $comments_result['data'][0]['count'] ?? 0;

$solved_posts_result = getData('posts', ['is_resolved' => 'eq.true', 'select' => 'count']);
$solved_posts = $solved_posts_result['data'][0]['count'] ?? 0;
$solution_rate = $total_posts > 0 ? round(($solved_posts / $total_posts) * 100) : 0;
?>

<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🏛️ Belediye Yönetim Sistemi - Giriş</title>
    
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            margin: 0;
            padding: 20px;
        }
        
        .main-container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .login-card {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.15);
            overflow: hidden;
            margin-bottom: 2rem;
        }
        
        .login-header {
            background: linear-gradient(45deg, #2980b9, #3498db);
            color: white;
            padding: 2rem;
            text-align: center;
        }
        
        .stats-card {
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
            padding: 1.5rem;
            margin-bottom: 1rem;
            transition: transform 0.3s ease;
        }
        
        .stats-card:hover {
            transform: translateY(-5px);
        }
        
        .btn-primary {
            background: linear-gradient(45deg, #2980b9, #3498db);
            border: none;
            border-radius: 10px;
            padding: 12px 24px;
        }
        
        .btn-secondary {
            background: linear-gradient(45deg, #95a5a6, #bdc3c7);
            border: none;
            border-radius: 10px;
            padding: 12px 24px;
        }
        
        .form-control {
            border-radius: 10px;
            border: 2px solid #ecf0f1;
            padding: 12px 15px;
        }
        
        .form-control:focus {
            border-color: #3498db;
            box-shadow: 0 0 0 0.2rem rgba(52, 152, 219, 0.25);
        }
        
        .login-type-btn {
            border-radius: 10px;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>
    <div class="main-container">
        <!-- Başlık -->
        <div class="text-center mb-4">
            <h1 class="text-white">
                <i class="fas fa-shield-alt me-3"></i>
                Belediye Yönetim Paneli
            </h1>
            <p class="text-white-50">
                <i class="fas fa-lock me-1"></i>
                Yetkili Personel ve Moderatör Erişimi
            </p>
        </div>

        <div class="row">
            <div class="col-lg-6">
                <!-- Giriş Formu -->
                <div class="login-card">
                    <div class="login-header">
                        <h3 class="mb-0">
                            <i class="fas fa-user-shield me-2"></i>
                            Yetkili Giriş
                        </h3>
                        <p class="mb-0 mt-2 opacity-75">Sadece admin ve moderatör erişimi</p>
                    </div>
                    
                    <div class="card-body p-4">
                        <?php if ($error): ?>
                            <div class="alert alert-danger">
                                <i class="fas fa-exclamation-triangle me-2"></i>
                                <?php echo $error; ?>
                            </div>
                        <?php endif; ?>
                        
                        <?php if ($success): ?>
                            <div class="alert alert-success">
                                <i class="fas fa-check-circle me-2"></i>
                                <?php echo $success; ?>
                            </div>
                        <?php endif; ?>

                        <form method="post" action="">
                            <!-- Giriş Tipi Seçimi -->
                            <div class="mb-4">
                                <label class="form-label fw-bold">Yetkili Giriş</label>
                                <div class="btn-group w-100" role="group">
                                    <input type="radio" class="btn-check" name="login_type" id="admin_type" value="admin" checked>
                                    <label class="btn btn-outline-primary login-type-btn" for="admin_type">
                                        <i class="fas fa-user-shield me-2"></i>
                                        Sistem Yöneticisi
                                    </label>
                                    
                                    <input type="radio" class="btn-check" name="login_type" id="official_type" value="official">
                                    <label class="btn btn-outline-primary login-type-btn" for="official_type">
                                        <i class="fas fa-user-tie me-2"></i>
                                        Personel/Moderatör
                                    </label>
                                </div>
                                <small class="text-muted mt-2 d-block">
                                    <i class="fas fa-info-circle me-1"></i>
                                    Bu panel sadece yetkili personel içindir
                                </small>
                            </div>

                            <!-- E-posta -->
                            <div class="mb-3">
                                <label for="email" class="form-label fw-bold">
                                    <i class="fas fa-envelope me-2"></i>
                                    E-posta Adresi
                                </label>
                                <input type="email" class="form-control" id="email" name="email" required 
                                       placeholder="ornek@belediye.gov.tr">
                            </div>

                            <!-- Şifre -->
                            <div class="mb-4">
                                <label for="password" class="form-label fw-bold">
                                    <i class="fas fa-lock me-2"></i>
                                    Şifre
                                </label>
                                <input type="password" class="form-control" id="password" name="password" required 
                                       placeholder="Şifrenizi girin">
                            </div>

                            <!-- Giriş Butonu -->
                            <button type="submit" class="btn btn-primary w-100">
                                <i class="fas fa-sign-in-alt me-2"></i>
                                Giriş Yap
                            </button>
                        </form>

                        <!-- Demo Bilgileri -->
                        <div class="mt-4 p-3 bg-light rounded">
                            <h6 class="fw-bold text-muted mb-2">
                                <i class="fas fa-info-circle me-2"></i>
                                Demo Giriş Bilgileri
                            </h6>
                            <div class="row">
                                <div class="col-md-6">
                                    <small class="text-muted">
                                        <strong>🔑 Yönetici:</strong><br>
                                        E-posta: mail@muzaffersanli.com<br>
                                        Şifre: 005434677197
                                    </small>
                                </div>
                                <div class="col-md-6">
                                    <small class="text-muted">
                                        <strong>🔑 Alternatif Admin:</strong><br>
                                        E-posta: admin@belediye.gov.tr<br>
                                        Şifre: admin123
                                    </small>
                                </div>
                            </div>
                            <hr class="my-3">
                            <div class="row">
                                <div class="col-12">
                                    <small class="text-muted">
                                        <strong>👤 Belediye Personeli/Moderatör:</strong><br>
                                        Supabase'deki gerçek kullanıcı e-postası + aşağıdaki şifrelerden biri:<br>
                                        <code>belediye123</code> | <code>personel2024</code> | <code>123456</code><br>
                                        <em>Not: role="moderator" olan kullanıcılar tüm verileri görebilir</em>
                                    </small>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="col-lg-6">
                <!-- Sistem İstatistikleri -->
                <div class="row">
                    <div class="col-md-6">
                        <div class="stats-card text-center">
                            <div class="d-flex align-items-center justify-content-center mb-3">
                                <div class="bg-primary rounded-circle p-3">
                                    <i class="fas fa-map-marker-alt text-white fa-2x"></i>
                                </div>
                            </div>
                            <h4 class="fw-bold text-primary"><?php echo number_format($total_cities); ?></h4>
                            <p class="text-muted mb-0">Şehir</p>
                        </div>
                    </div>
                    
                    <div class="col-md-6">
                        <div class="stats-card text-center">
                            <div class="d-flex align-items-center justify-content-center mb-3">
                                <div class="bg-success rounded-circle p-3">
                                    <i class="fas fa-building text-white fa-2x"></i>
                                </div>
                            </div>
                            <h4 class="fw-bold text-success"><?php echo number_format($total_districts); ?></h4>
                            <p class="text-muted mb-0">İlçe</p>
                        </div>
                    </div>
                    
                    <div class="col-md-6">
                        <div class="stats-card text-center">
                            <div class="d-flex align-items-center justify-content-center mb-3">
                                <div class="bg-info rounded-circle p-3">
                                    <i class="fas fa-file-alt text-white fa-2x"></i>
                                </div>
                            </div>
                            <h4 class="fw-bold text-info"><?php echo number_format($total_posts); ?></h4>
                            <p class="text-muted mb-0">Gönderi</p>
                        </div>
                    </div>
                    
                    <div class="col-md-6">
                        <div class="stats-card text-center">
                            <div class="d-flex align-items-center justify-content-center mb-3">
                                <div class="bg-warning rounded-circle p-3">
                                    <i class="fas fa-comments text-white fa-2x"></i>
                                </div>
                            </div>
                            <h4 class="fw-bold text-warning"><?php echo number_format($total_comments); ?></h4>
                            <p class="text-muted mb-0">Yorum</p>
                        </div>
                    </div>
                </div>

                <!-- Özellikler -->
                <div class="stats-card mt-3">
                    <h5 class="fw-bold mb-3">
                        <i class="fas fa-star text-warning me-2"></i>
                        Sistem Özellikleri
                    </h5>
                    <div class="row">
                        <div class="col-6">
                            <ul class="list-unstyled">
                                <li><i class="fas fa-check text-success me-2"></i> Anket Yönetimi</li>
                                <li><i class="fas fa-check text-success me-2"></i> Gönderi Moderasyonu</li>
                                <li><i class="fas fa-check text-success me-2"></i> Kullanıcı Yönetimi</li>
                            </ul>
                        </div>
                        <div class="col-6">
                            <ul class="list-unstyled">
                                <li><i class="fas fa-check text-success me-2"></i> Reklam Yönetimi</li>
                                <li><i class="fas fa-check text-success me-2"></i> İstatistikler</li>
                                <li><i class="fas fa-check text-success me-2"></i> Rapor Sistemi</li>
                            </ul>
                        </div>
                    </div>
                    
                    <div class="mt-3 p-3 bg-light rounded">
                        <div class="d-flex justify-content-between align-items-center">
                            <span class="fw-bold">Çözüm Oranı</span>
                            <span class="badge bg-success fs-6"><?php echo $solution_rate; ?>%</span>
                        </div>
                        <div class="progress mt-2" style="height: 8px;">
                            <div class="progress-bar bg-success" style="width: <?php echo $solution_rate; ?>%"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Alt Bilgi -->
        <div class="text-center mt-4">
            <p class="text-white-50 mb-0">
                <i class="fas fa-shield-alt me-2"></i>
                Güvenli ve modern belediye yönetim sistemi
            </p>
            <small class="text-white-50">
                © <?php echo date('Y'); ?> Belediye Yönetim Sistemi - Tüm hakları saklıdır.
            </small>
        </div>
    </div>

    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
            margin-bottom: 2.5rem;
            font-weight: 600;
        }
        
        .section-title:after {
            content: '';
            position: absolute;
            left: 0;
            bottom: -10px;
            width: 100px;
            height: 4px;
            background-color: var(--secondary-color);
            border-radius: 5px;
        }
        
        .footer {
            background-color: var(--primary-color);
            color: white;
            padding: 1.5rem 0;
            margin-top: auto;
        }
        
        /* Animasyonlar */
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        .animate {
            animation: fadeIn 0.8s ease forwards;
        }
        
        .delay-1 { animation-delay: 0.2s; }
        .delay-2 { animation-delay: 0.4s; }
        .delay-3 { animation-delay: 0.6s; }
        .delay-4 { animation-delay: 0.8s; }

        .feature-count {
            font-size: 2.5rem;
            font-weight: 700;
            color: var(--secondary-color);
            margin-bottom: 0.5rem;
        }
        
        .progress-bar {
            background-color: var(--success-color);
        }
    </style>
</head>
<body>
    <div class="container login-container">
        <!-- Hero Section -->
        <div class="row mb-5">
            <div class="col-12">
                <div class="hero-section text-center p-5 animate">
                    <h1 class="display-4 fw-bold mb-4">Belediye Yönetim Sistemi</h1>
                    <p class="lead">Şehirlerimizin geleceğini birlikte inşa ediyoruz</p>
                    <div class="d-flex justify-content-center gap-3 mt-4">
                        <span class="badge bg-light text-dark p-2"><i class="fas fa-city me-2"></i>Şehir Yönetimi</span>
                        <span class="badge bg-light text-dark p-2"><i class="fas fa-chart-line me-2"></i>Performans İzleme</span>
                        <span class="badge bg-light text-dark p-2"><i class="fas fa-comments me-2"></i>Vatandaş İletişimi</span>
                        <span class="badge bg-light text-dark p-2"><i class="fas fa-tasks me-2"></i>Sorun Takibi</span>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Main Content -->
        <div class="row">
            <!-- Sol Taraf - Tanıtım ve İstatistikler -->
            <div class="col-lg-8 pe-lg-5">
                <!-- İstatistikler -->
                <h2 class="section-title mb-4 animate">Genel Bakış</h2>
                <div class="row mb-5">
                    <div class="col-md-3 mb-4 animate delay-1">
                        <div class="stats-card card text-center p-3">
                            <div class="feature-count"><?php echo number_format($total_cities); ?></div>
                            <div class="text-muted">Şehir</div>
                            <div class="mt-3 text-primary">
                                <i class="fas fa-city fa-2x"></i>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3 mb-4 animate delay-2">
                        <div class="stats-card card text-center p-3">
                            <div class="feature-count"><?php echo number_format($total_districts); ?></div>
                            <div class="text-muted">İlçe</div>
                            <div class="mt-3 text-success">
                                <i class="fas fa-map-marker-alt fa-2x"></i>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3 mb-4 animate delay-3">
                        <div class="stats-card card text-center p-3">
                            <div class="feature-count"><?php echo number_format($total_posts); ?></div>
                            <div class="text-muted">Paylaşım</div>
                            <div class="mt-3 text-info">
                                <i class="fas fa-file-alt fa-2x"></i>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3 mb-4 animate delay-4">
                        <div class="stats-card card text-center p-3">
                            <div class="feature-count"><?php echo $solution_rate; ?>%</div>
                            <div class="text-muted">Çözüm Oranı</div>
                            <div class="mt-3 text-warning">
                                <i class="fas fa-check-circle fa-2x"></i>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Özellikler -->
                <h2 class="section-title mb-4 animate">Sistem Özellikleri</h2>
                <div class="row mb-5">
                    <div class="col-md-6 mb-4 animate delay-1">
                        <div class="d-flex">
                            <div class="feature-icon bg-primary me-3">
                                <i class="fas fa-chart-bar"></i>
                            </div>
                            <div>
                                <h5>Detaylı Analizler</h5>
                                <p class="text-muted">İl ve ilçe bazında detaylı performans analizleri ve raporlama araçları.</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-6 mb-4 animate delay-2">
                        <div class="d-flex">
                            <div class="feature-icon bg-success me-3">
                                <i class="fas fa-users"></i>
                            </div>
                            <div>
                                <h5>Kullanıcı Yönetimi</h5>
                                <p class="text-muted">Rol bazlı kullanıcı yönetimi ve yetkilendirme sistemi.</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-6 mb-4 animate delay-3">
                        <div class="d-flex">
                            <div class="feature-icon bg-info me-3">
                                <i class="fas fa-ad"></i>
                            </div>
                            <div>
                                <h5>Reklam Yönetimi</h5>
                                <p class="text-muted">Hedefli reklam kampanyaları ve performans takibi.</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-6 mb-4 animate delay-4">
                        <div class="d-flex">
                            <div class="feature-icon bg-warning me-3">
                                <i class="fas fa-tasks"></i>
                            </div>
                            <div>
                                <h5>Sorun Takibi</h5>
                                <p class="text-muted">Vatandaş şikayetlerinin hızlı ve etkili yönetimi.</p>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Performans Göstergeleri -->
                <h2 class="section-title mb-4 animate">Performans Göstergeleri</h2>
                <div class="row mb-4 animate delay-1">
                    <div class="col-12">
                        <div class="card stats-card p-4">
                            <h6>Çözüm Oranı</h6>
                            <div class="progress mb-3" style="height: 10px;">
                                <div class="progress-bar" role="progressbar" style="width: <?php echo $solution_rate; ?>%;" aria-valuenow="<?php echo $solution_rate; ?>" aria-valuemin="0" aria-valuemax="100"></div>
                            </div>
                            <div class="d-flex justify-content-between">
                                <small>Hedef: 90%</small>
                                <small>Mevcut: <?php echo $solution_rate; ?>%</small>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Sağ Taraf - Giriş Formu -->
            <div class="col-lg-4 animate delay-2">
                <div class="card login-card">
                    <div class="card-header text-white text-center">
                        <h4 class="mb-0"><i class="fas fa-lock me-2"></i> Yönetici Girişi</h4>
                    </div>
                    <div class="card-body p-4">
                        <?php if (!empty($error)): ?>
                            <div class="alert alert-danger">
                                <?php echo htmlspecialchars($error); ?>
                            </div>
                        <?php endif; ?>
                        
                        <form method="post" action="">
                            <div class="mb-3">
                                <label for="username" class="form-label">Kullanıcı Adı</label>
                                <div class="input-group">
                                    <span class="input-group-text"><i class="fas fa-user"></i></span>
                                    <input type="text" class="form-control" id="username" name="username" required placeholder="Kullanıcı adınız">
                                </div>
                            </div>
                            
                            <div class="mb-4">
                                <label for="password" class="form-label">Şifre</label>
                                <div class="input-group">
                                    <span class="input-group-text"><i class="fas fa-key"></i></span>
                                    <input type="password" class="form-control" id="password" name="password" required placeholder="Şifreniz">
                                    <button class="btn btn-outline-secondary" type="button" id="togglePassword">
                                        <i class="fas fa-eye"></i>
                                    </button>
                                </div>
                            </div>
                            
                            <div class="d-grid gap-2">
                                <button type="submit" class="btn btn-primary btn-lg">
                                    <i class="fas fa-sign-in-alt me-2"></i> Giriş Yap
                                </button>
                            </div>
                        </form>
                    </div>
                    <div class="card-footer text-center py-3">
                        <div>
                            <a href="index.php?page=official_login" class="text-decoration-none">
                                <i class="fas fa-user-tie me-1"></i> Belediye görevlisi girişi için tıklayın
                            </a>
                        </div>
                    </div>
                </div>
                
                <!-- İletişim Bilgileri -->
                <div class="card stats-card mt-4 p-4 animate delay-3">
                    <h5><i class="fas fa-headset me-2"></i> Destek</h5>
                    <p class="mb-2 text-muted">Teknik destek için iletişime geçin:</p>
                    <div class="mb-2">
                        <i class="fas fa-envelope me-2 text-primary"></i> destek@belediye-yonetim.com
                    </div>
                    <div>
                        <i class="fas fa-phone me-2 text-primary"></i> +90 (212) 555 1234
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Footer -->
    <footer class="footer text-center">
        <div class="container">
            <p class="mb-0">&copy; 2025 Belediye Yönetim Sistemi. Tüm hakları saklıdır.</p>
        </div>
    </footer>
    
    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
    document.addEventListener('DOMContentLoaded', function() {
        const togglePassword = document.getElementById('togglePassword');
        const password = document.getElementById('password');
        
        togglePassword.addEventListener('click', function() {
            const type = password.getAttribute('type') === 'password' ? 'text' : 'password';
            password.setAttribute('type', type);
            
            this.querySelector('i').classList.toggle('fa-eye');
            this.querySelector('i').classList.toggle('fa-eye-slash');
        });
        
        // Animasyonları aktif et
        const animatedElements = document.querySelectorAll('.animate');
        animatedElements.forEach(el => {
            el.style.opacity = '0';
        });
        
        // Sayfa yüklendiğinde animasyonları başlat
        setTimeout(() => {
            animatedElements.forEach(el => {
                el.style.opacity = '1';
            });
        }, 100);
    });
    </script>
</body>
</html>
</script>