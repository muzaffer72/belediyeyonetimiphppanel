<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');
require_once(__DIR__ . '/includes/functions.php');
require_once(__DIR__ . '/includes/auth_functions.php');

// Kullanıcı zaten giriş yapmışsa yönlendir
if (isLoggedIn()) {
    if (isAdmin()) {
        redirect('index.php?page=dashboard');
    } elseif (isOfficial()) {
        redirect('index.php?page=official_dashboard');
    }
}

$error = '';

// Giriş formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    
    // Kullanıcı adı ve şifre kontrolü
    if ($username === ADMIN_USERNAME && $password === ADMIN_PASSWORD) {
        // Admin girişi başarılı
        $_SESSION['admin_logged_in'] = true;
        $_SESSION['user_id'] = 'admin';
        $_SESSION['is_admin'] = true;
        
        // Ana sayfaya yönlendir
        redirect('index.php?page=dashboard');
    } else {
        try {
            // Test amaçlı geçici giriş (geliştirme modu)
            if ($password === '123456') {
                // Görevli rolünde giriş yapacak
                $_SESSION['user_id'] = 'test_user_1';
                $_SESSION['email'] = $username;
                $_SESSION['is_admin'] = false;
                $_SESSION['is_official'] = true;
                $_SESSION['official_id'] = 'test_official_1';
                $_SESSION['city_id'] = 1;
                $_SESSION['district_id'] = 1;
                $_SESSION['city_name'] = 'İstanbul';
                $_SESSION['district_name'] = 'Kadıköy';
                
                // Görevli paneline yönlendir
                redirect('index.php?page=official_dashboard');
                exit;
            }
            
            // Gerçek API ile giriş (eğer API erişimi varsa)
            // Not: Prodüksiyon ortamında bu bölüm aktif edilmelidir
            /*
            // Belediye görevlisi girişini dene
            $login_data = [
                'email' => $username,
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
                    $_SESSION['email'] = $username;
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
                    $error = 'Geçersiz kullanıcı adı veya şifre';
                }
            } else {
                $error = 'Geçersiz kullanıcı adı veya şifre';
            }
            */
            
            // API bağlantısı yoksa hata mesajı
            $error = 'Geliştirme modunda test için şifre olarak "123456" kullanınız.';
        } catch (Exception $e) {
            $error = 'Giriş işlemi sırasında bir hata oluştu: ' . $e->getMessage();
        }
    }
}

// Giriş sayfasını yükle
include(__DIR__ . '/views/header.php');
?>

<div class="container mt-5">
    <div class="row justify-content-center">
        <div class="col-md-6">
            <div class="card shadow">
                <div class="card-header bg-primary text-white">
                    <h4 class="mb-0"><i class="fas fa-lock me-2"></i> Yönetici Girişi</h4>
                </div>
                <div class="card-body">
                    <?php if (!empty($error)): ?>
                        <div class="alert alert-danger">
                            <?php echo htmlspecialchars($error); ?>
                        </div>
                    <?php endif; ?>
                    
                    <form method="post" action="login.php">
                        <div class="mb-3">
                            <label for="username" class="form-label">Kullanıcı Adı</label>
                            <input type="text" class="form-control" id="username" name="username" required>
                        </div>
                        
                        <div class="mb-3">
                            <label for="password" class="form-label">Şifre</label>
                            <div class="input-group">
                                <input type="password" class="form-control" id="password" name="password" required>
                                <button class="btn btn-outline-secondary" type="button" id="togglePassword">
                                    <i class="fas fa-eye"></i>
                                </button>
                            </div>
                        </div>
                        
                        <div class="d-grid gap-2">
                            <button type="submit" class="btn btn-primary">
                                <i class="fas fa-sign-in-alt me-2"></i> Giriş Yap
                            </button>
                        </div>
                    </form>
                </div>
                <div class="card-footer text-center">
                    <div class="small">
                        <a href="index.php?page=official_login">Belediye görevlisi girişi için tıklayın</a>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

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
});
</script>

<?php
// Footer yükle
include(__DIR__ . '/views/footer.php');
?>