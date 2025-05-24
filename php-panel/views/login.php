<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Kullanıcı zaten giriş yapmışsa yönlendir
if (isLoggedIn()) {
    if (isAdmin()) {
        redirect('index.php?page=dashboard');
    } elseif (isOfficial()) {
        redirect('index.php?page=official_dashboard');
    }
}

$error = '';

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    // Admin kontrolü
    if ($username === ADMIN_USERNAME && $password === ADMIN_PASSWORD) {
        // Admin girişi başarılı
        $_SESSION['admin_logged_in'] = true;
        $_SESSION['user_id'] = 'admin';
        $_SESSION['is_admin'] = true;
        
        // Ana sayfaya yönlendir
        redirect('index.php?page=dashboard');
    } else {
        $error = 'Geçersiz kullanıcı adı veya şifre';
    }
}

// İstatistikler için örnek veriler (gerçek sistemde veritabanından çekilecektir)
$total_cities = 81; // Türkiye'deki il sayısı
$total_districts = 973; // Tahmini ilçe sayısı
$total_posts = 12500; // Örnek paylaşım sayısı
$total_comments = 45800; // Örnek yorum sayısı
$solution_rate = 78; // Çözüm oranı yüzdesi
?>

<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Belediye Yönetim Sistemi - Giriş</title>
    
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
        }
        
        .login-container {
            margin-top: 2rem;
            margin-bottom: 2rem;
        }
        
        .hero-section {
            background: linear-gradient(rgba(44, 62, 80, 0.8), rgba(44, 62, 80, 0.9)), url('https://images.unsplash.com/photo-1566419808810-642d35c10b52?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxzZWFyY2h8MzJ8fGNpdHklMjB0dXJrZXl8ZW58MHx8MHx8&auto=format&fit=crop&w=1200&q=60');
            background-size: cover;
            background-position: center;
            color: white;
            padding: 4rem 0;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
        }
        
        .stats-card {
            border-radius: 15px;
            transition: all 0.3s ease;
            height: 100%;
            border: none;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.05);
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
            height: 4rem;
            width: 4rem;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.5rem;
            margin-bottom: 1rem;
            color: white;
        }
        
        .section-title {
            position: relative;
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