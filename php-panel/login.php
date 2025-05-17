<?php
// Konfigürasyon dosyası
require_once 'config/config.php';

// Fonksiyonlar
require_once 'includes/functions.php';

// Kullanıcı zaten giriş yapmışsa dashboard'a yönlendir
if (isLoggedIn()) {
    header('Location: index.php?page=dashboard');
    exit;
}

// Giriş işlemi
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = trim($_POST['password'] ?? '');
    
    // Basit doğrulama
    if (empty($username) || empty($password)) {
        $error = 'Kullanıcı adı ve şifre gereklidir';
    } else {
        // Admin kullanıcılarında ara
        $authenticated = false;
        foreach ($admin_users as $user) {
            if ($user['username'] === $username && $user['password'] === $password) {
                // Giriş başarılı, oturum bilgilerini ayarla
                $_SESSION['user_id'] = 'admin-01'; // Sabit bir ID
                $_SESSION['username'] = $username;
                $_SESSION['display_name'] = $user['display_name'];
                $_SESSION['email'] = $user['email'];
                $_SESSION['user_role'] = $user['role'];
                
                $authenticated = true;
                break;
            }
        }
        
        if ($authenticated) {
            // Dashboard'a yönlendir
            header('Location: index.php?page=dashboard');
            exit;
        } else {
            $error = 'Geçersiz kullanıcı adı veya şifre';
        }
    }
}

// Sayfa başlığı
$page_title = getPageTitle('login');
?>
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?></title>
    
    <!-- Favicon -->
    <link rel="shortcut icon" href="assets/img/favicon.ico" type="image/x-icon">
    
    <!-- Bootstrap 5 CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Font Awesome -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    
    <!-- Google Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&display=swap" rel="stylesheet">
    
    <!-- Custom CSS -->
    <style>
        body {
            font-family: 'Roboto', sans-serif;
            background-color: #f5f5f5;
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .login-container {
            max-width: 400px;
            width: 100%;
            padding: 20px;
        }
        
        .login-card {
            border-radius: 10px;
            border: none;
            box-shadow: 0 0 20px rgba(0, 0, 0, 0.1);
            overflow: hidden;
        }
        
        .card-header {
            background-color: #0d6efd;
            color: white;
            text-align: center;
            padding: 20px;
            border-bottom: none;
        }
        
        .card-header .logo {
            font-size: 2rem;
            margin-bottom: 10px;
        }
        
        .card-body {
            padding: 30px;
        }
        
        .form-control {
            padding: 12px;
            border-radius: 5px;
        }
        
        .btn-primary {
            padding: 12px;
            border-radius: 5px;
            width: 100%;
            font-weight: 500;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-label {
            font-weight: 500;
        }
        
        .input-group-text {
            background-color: transparent;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="card login-card">
            <div class="card-header">
                <div class="logo">
                    <i class="fas fa-city"></i>
                </div>
                <h4 class="mb-0">Bimer Yönetim Paneli</h4>
                <small>Belediye Yönetim Sistemi</small>
            </div>
            <div class="card-body">
                <?php if (!empty($error)): ?>
                    <div class="alert alert-danger" role="alert">
                        <?php echo $error; ?>
                    </div>
                <?php endif; ?>
                
                <form method="post" action="login.php">
                    <div class="form-group">
                        <label for="username" class="form-label">Kullanıcı Adı</label>
                        <div class="input-group">
                            <span class="input-group-text"><i class="fas fa-user"></i></span>
                            <input type="text" class="form-control" id="username" name="username" placeholder="Kullanıcı adınızı girin" required>
                        </div>
                    </div>
                    
                    <div class="form-group">
                        <label for="password" class="form-label">Şifre</label>
                        <div class="input-group">
                            <span class="input-group-text"><i class="fas fa-lock"></i></span>
                            <input type="password" class="form-control" id="password" name="password" placeholder="Şifrenizi girin" required>
                        </div>
                    </div>
                    
                    <div class="form-group mt-4">
                        <button type="submit" class="btn btn-primary">
                            <i class="fas fa-sign-in-alt me-2"></i> Giriş Yap
                        </button>
                    </div>
                </form>
                
                <div class="text-center mt-3">
                    <small class="text-muted">Demo hesabı: admin / admin123</small>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>