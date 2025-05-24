<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Kullanıcı zaten giriş yapmışsa yönlendir
if (isLoggedIn()) {
    if (isAdmin()) {
        redirect('index.php?page=dashboard');
    } else {
        redirect('index.php?page=official_dashboard');
    }
}

$error = '';

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $email = $_POST['email'] ?? '';
    $password = $_POST['password'] ?? '';
    
    if (empty($email) || empty($password)) {
        $error = 'E-posta ve şifre gereklidir';
    } else {
        // TEST AMAÇLI: Gerçek veritabanı yapısına uygun test girişi (geliştirme modu)
        // NOT: Bu kod sadece test amaçlıdır, gerçek ortamda API bağlantısı kullanılmalıdır
        if ($password === '123456') {
            // Veritabanındaki örnek belediye görevlisi verilerine göre giriş yapılıyor
            // Gerçek veritabanı yapısına uygun olarak UUID formatında veriler kullanılıyor
            
            // officials tablosundan alınan örnek veri:
            // id, user_id, city_id, district_id, title, notes, created_at, updated_at
            $official_id = '4'; // Officials tablosundaki ID
            $user_id = '83190944-98d5-41be-ac3a-178676faf017'; // User ID (UUID formatında)
            $city_id = '550e8400-e29b-41d4-a716-446655440072'; // City ID (UUID formatında)
            $district_id = '660e8400-e29b-41d4-a716-446655593166'; // District ID (UUID formatında)
            
            // Session'a görevli bilgilerini kaydet
            $_SESSION['user_id'] = $user_id;
            $_SESSION['email'] = $email;
            $_SESSION['is_admin'] = false;
            $_SESSION['is_official'] = true;
            $_SESSION['official_id'] = $official_id;
            $_SESSION['city_id'] = $city_id;
            $_SESSION['district_id'] = $district_id;
            $_SESSION['city_name'] = 'İstanbul'; // Normalde veritabanından çekilecek
            $_SESSION['district_name'] = 'Kadıköy'; // Normalde veritabanından çekilecek
            
            // Görevli paneline yönlendir
            redirect('index.php?page=official_dashboard');
            exit;
        }
        
        // Gerçek API bağlantısı (şu anda devre dışı bırakıldı)
        /* 
        // Supabase API ile giriş denemesi
        $login_data = [
            'email' => $email,
            'password' => $password
        ];
        
        $login_result = supabaseLogin($login_data);
        
        if (!$login_result['error']) {
            // Kullanıcı bilgilerini al
            $user_data = $login_result['data'];
            $user_id = $user_data['user']['id'] ?? '';
            
            // Kullanıcının belediye görevlisi olup olmadığını kontrol et
            $official_result = getData('officials', [
                'select' => '*',
                'filters' => ['user_id' => 'eq.' . $user_id]
            ]);
            
            if (!$official_result['error'] && !empty($official_result['data'])) {
                // Belediye görevlisi bilgilerini session'a kaydet
                $official = $official_result['data'][0];
                
                $_SESSION['user_id'] = $user_id;
                $_SESSION['email'] = $email;
                $_SESSION['is_admin'] = false;
                $_SESSION['is_official'] = true;
                $_SESSION['official_id'] = $official['id'];
                $_SESSION['city_id'] = $official['city_id'] ?? null;
                $_SESSION['district_id'] = $official['district_id'] ?? null;
                
                // Görevlinin şehir ve ilçe bilgilerini al
                if ($_SESSION['city_id']) {
                    $city_result = getData('cities', [
                        'select' => 'name',
                        'filters' => ['id' => 'eq.' . $_SESSION['city_id']]
                    ]);
                    
                    if (!$city_result['error'] && !empty($city_result['data'])) {
                        $_SESSION['city_name'] = $city_result['data'][0]['name'] ?? '';
                    }
                }
                
                if ($_SESSION['district_id']) {
                    $district_result = getData('districts', [
                        'select' => 'name',
                        'filters' => ['id' => 'eq.' . $_SESSION['district_id']]
                    ]);
                    
                    if (!$district_result['error'] && !empty($district_result['data'])) {
                        $_SESSION['district_name'] = $district_result['data'][0]['name'] ?? '';
                    }
                }
                
                // Görevli paneline yönlendir
                redirect('index.php?page=official_dashboard');
            } else {
                // Admin girişi kontrolü
                if ($email === ADMIN_USERNAME && $password === ADMIN_PASSWORD) {
                    $_SESSION['user_id'] = 'admin';
                    $_SESSION['email'] = $email;
                    $_SESSION['is_admin'] = true;
                    $_SESSION['is_official'] = false;
                    
                    redirect('index.php?page=dashboard');
                } else {
                    $error = 'Bu e-posta ve şifre ile ilişkili bir belediye görevlisi hesabı bulunamadı';
                }
            }
        } else {
            $error = 'Giriş yapılamadı: ' . ($login_result['message'] ?? 'Hatalı e-posta veya şifre');
        }
        */
        
        // Kaldırılacak kod: Supabase bağlantısı olmadığı için her zaman hata veriyor
        $error = 'Geliştirme modunda test için şifre olarak 123456 kullanınız.';
    }
}
?>

<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Belediye Görevlisi Girişi - Belediye Yönetim Sistemi</title>
    
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <!-- Google Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    
    <style>
        :root {
            --primary-color: #2c3e50;
            --secondary-color: #3498db;
            --accent-color: #e74c3c;
            --light-color: #ecf0f1;
            --dark-color: #2c3e50;
            --success-color: #27ae60;
        }
        
        body {
            font-family: 'Poppins', sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            overflow-x: hidden;
        }
        
        .login-container {
            margin-top: 2rem;
            margin-bottom: 2rem;
            max-width: 1200px;
        }
        
        .hero-section {
            background: linear-gradient(rgba(44, 62, 80, 0.8), rgba(44, 62, 80, 0.9)), url('https://images.unsplash.com/photo-1559070169-a3077159ee16?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxzZWFyY2h8MTZ8fGNpdHklMjBoYWxsfGVufDB8fDB8fA%3D%3D&auto=format&fit=crop&w=1200&q=60');
            background-size: cover;
            background-position: center;
            color: white;
            padding: 3rem 0;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
        }
        
        .stats-card {
            border-radius: 15px;
            transition: all 0.3s ease;
            border: none;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.05);
            height: calc(100% - 1.5rem);
            margin-bottom: 1.5rem;
        }
        
        .stats-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 30px rgba(0, 0, 0, 0.1);
        }
        
        .login-card {
            border-radius: 15px;
            box-shadow: 0 15px 30px rgba(0, 0, 0, 0.1);
            border: none;
            overflow: hidden;
            margin-bottom: 1.5rem;
        }
        
        .login-card .card-header {
            background-color: var(--primary-color);
            border-bottom: none;
            padding: 1.5rem;
        }
        
        .btn-primary {
            background-color: var(--primary-color);
            border-color: var(--primary-color);
        }
        
        .btn-primary:hover {
            background-color: var(--secondary-color);
            border-color: var(--secondary-color);
        }
        
        .feature-icon {
            height: 3.5rem;
            width: 3.5rem;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.25rem;
            margin-bottom: 0;
            color: white;
            flex-shrink: 0;
        }
        
        .section-title {
            position: relative;
            margin-bottom: 2.5rem;
            font-weight: 600;
            font-size: 1.75rem;
        }
        
        .section-title:after {
            content: '';
            position: absolute;
            left: 0;
            bottom: -10px;
            width: 80px;
            height: 4px;
            background-color: var(--secondary-color);
            border-radius: 5px;
        }
        
        .footer {
            background-color: var(--primary-color);
            color: white;
            padding: 1rem 0;
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
        
        /* Responsive düzenlemeler */
        @media (max-width: 991px) {
            .login-container {
                padding-left: 1rem;
                padding-right: 1rem;
            }
            
            .hero-section {
                padding: 2rem 0;
            }
            
            .section-title {
                font-size: 1.5rem;
            }
            
            .feature-card h5 {
                font-size: 1.1rem;
            }
        }
        
        @media (max-width: 767px) {
            .feature-badges {
                flex-wrap: wrap;
                justify-content: center;
            }
            
            .feature-badges .badge {
                margin-bottom: 0.5rem;
            }
        }
        
        /* Daha derli toplu kartlar */
        .feature-card {
            display: flex;
            align-items: flex-start;
        }
        
        .feature-card-content {
            flex-grow: 1;
            min-width: 0; /* İçeriğin taşmasını engeller */
        }
        
        .feature-card-content h5 {
            margin-bottom: 0.5rem;
            font-size: 1.1rem;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        .feature-card-content p {
            margin-bottom: 0;
            font-size: 0.9rem;
            line-height: 1.4;
        }
        
        /* Belirli yüksekliklere sahip kartlar */
        .fixed-height-card {
            height: 100%;
            display: flex;
            flex-direction: column;
        }
        
        .card-body-scroll {
            overflow-y: auto;
            max-height: 180px;
        }
    </style>
</head>
<body>
    <div class="container login-container">
        <!-- Hero Section -->
        <div class="row mb-4">
            <div class="col-12">
                <div class="hero-section text-center p-4 animate">
                    <h1 class="display-5 fw-bold mb-3">Belediye Görevlisi Portali</h1>
                    <p class="lead mb-3">Vatandaşlara daha iyi hizmet sunmak için güçlü yönetim araçları</p>
                    <div class="d-flex justify-content-center gap-2 mt-3 feature-badges flex-wrap">
                        <span class="badge bg-light text-dark p-2 m-1"><i class="fas fa-building me-1"></i>İlçe Yönetimi</span>
                        <span class="badge bg-light text-dark p-2 m-1"><i class="fas fa-tachometer-alt me-1"></i>Performans Takibi</span>
                        <span class="badge bg-light text-dark p-2 m-1"><i class="fas fa-users me-1"></i>Vatandaş Hizmetleri</span>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Main Content -->
        <div class="row">
            <!-- Sol Taraf - Özellikler -->
            <div class="col-lg-7 pe-lg-4">
                <h2 class="section-title animate">Görevli Platformu Özellikleri</h2>
                
                <div class="row">
                    <div class="col-md-6 animate delay-1">
                        <div class="stats-card card p-3">
                            <div class="feature-card">
                                <div class="feature-icon bg-primary me-3">
                                    <i class="fas fa-tasks"></i>
                                </div>
                                <div class="feature-card-content">
                                    <h5>Görev Yönetimi</h5>
                                    <p class="text-muted">İlçenize ait talepleri önceliklendirin ve takip edin.</p>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-6 animate delay-2">
                        <div class="stats-card card p-3">
                            <div class="feature-card">
                                <div class="feature-icon bg-success me-3">
                                    <i class="fas fa-chart-line"></i>
                                </div>
                                <div class="feature-card-content">
                                    <h5>Performans İzleme</h5>
                                    <p class="text-muted">İlçenizin çözüm oranlarını ve metriklerini analiz edin.</p>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-6 animate delay-3">
                        <div class="stats-card card p-3">
                            <div class="feature-card">
                                <div class="feature-icon bg-info me-3">
                                    <i class="fas fa-comments"></i>
                                </div>
                                <div class="feature-card-content">
                                    <h5>Vatandaş İletişimi</h5>
                                    <p class="text-muted">Vatandaş talep ve şikayetlerini hızlı şekilde yanıtlayın.</p>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-6 animate delay-4">
                        <div class="stats-card card p-3">
                            <div class="feature-card">
                                <div class="feature-icon bg-warning me-3">
                                    <i class="fas fa-file-alt"></i>
                                </div>
                                <div class="feature-card-content">
                                    <h5>Rapor Oluşturma</h5>
                                    <p class="text-muted">Detaylı raporlar oluşturun ve ilçenizin gelişimini izleyin.</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="card stats-card p-3 animate delay-1">
                    <h5 class="mb-2"><i class="fas fa-info-circle me-2 text-primary"></i> Platform Özellikleri</h5>
                    <div class="card-body-scroll">
                        <p class="text-muted mb-2">Belediye görevlileri için özel olarak tasarlanmış bu platform ile:</p>
                        <ul class="text-muted mb-0 ps-3">
                            <li>Sorumlu olduğunuz bölgenin taleplerini görüntüleyebilir</li>
                            <li>Çözüm süreçlerini takip edebilir</li>
                            <li>Performans metriklerinizi izleyebilir</li>
                            <li>Diğer birimlerle koordinasyon sağlayabilirsiniz</li>
                        </ul>
                    </div>
                </div>
            </div>
            
            <!-- Sağ Taraf - Giriş Formu -->
            <div class="col-lg-5 animate delay-2">
                <div class="login-card card">
                    <div class="card-header text-white text-center">
                        <h4 class="mb-0"><i class="fas fa-user-tie me-2"></i> Belediye Görevlisi Girişi</h4>
                    </div>
                    <div class="card-body p-4">
                        <?php if (!empty($error)): ?>
                            <div class="alert alert-danger">
                                <?php echo htmlspecialchars($error); ?>
                            </div>
                        <?php endif; ?>
                        
                        <form method="post" action="">
                            <div class="mb-3">
                                <label for="email" class="form-label">E-posta Adresi</label>
                                <div class="input-group">
                                    <span class="input-group-text"><i class="fas fa-envelope"></i></span>
                                    <input type="email" class="form-control" id="email" name="email" required placeholder="ornek@belediye.gov.tr">
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
                                <div class="form-text mt-1">Test için şifre: 123456</div>
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
                            <a href="index.php?page=login" class="text-decoration-none">
                                <i class="fas fa-user-shield me-1"></i> Yönetici girişi için tıklayın
                            </a>
                        </div>
                    </div>
                </div>
                
                <!-- Destek Bilgileri -->
                <div class="card stats-card p-3 animate delay-3">
                    <h5 class="mb-2"><i class="fas fa-question-circle me-2 text-primary"></i> Yardım & Destek</h5>
                    <div class="card-body-scroll">
                        <p class="mb-2 text-muted">Giriş yaparken sorun yaşıyorsanız:</p>
                        <ul class="text-muted mb-3 ps-3">
                            <li>E-posta adresinizi ve şifrenizi kontrol edin</li>
                            <li>Görevli kaydınızın aktif olduğundan emin olun</li>
                            <li>Teknik destek ekibiyle iletişime geçin</li>
                        </ul>
                        <div class="d-flex align-items-center mb-2">
                            <i class="fas fa-envelope me-2 text-primary"></i> 
                            <span>destek@belediye-yonetim.com</span>
                        </div>
                        <div class="d-flex align-items-center">
                            <i class="fas fa-phone me-2 text-primary"></i> 
                            <span>+90 (212) 555 1234</span>
                        </div>
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