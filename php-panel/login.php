<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');

// Kullanıcı zaten giriş yapmışsa ana sayfaya yönlendir
if (isLoggedIn()) {
    redirect('index.php');
    exit;
}

// Hata ve bildirim mesajları
$error_message = '';
$success_message = '';

// Giriş formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = isset($_POST['username']) ? trim($_POST['username']) : '';
    $password = isset($_POST['password']) ? trim($_POST['password']) : '';
    
    // Basit kimlik doğrulama (gerçek uygulamada veritabanı kullanılmalı)
    if ($username === ADMIN_USERNAME && $password === ADMIN_PASSWORD) {
        // Oturum başlat
        $_SESSION['admin_logged_in'] = true;
        $_SESSION['admin_username'] = $username;
        
        // Kullanıcıyı ana sayfaya yönlendir
        redirect('index.php');
        exit;
    } else {
        $error_message = 'Geçersiz kullanıcı adı veya şifre. Lütfen tekrar deneyin.';
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
    
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.2.1/css/all.min.css">
    
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .login-container {
            max-width: 400px;
            margin: 100px auto;
            padding: 30px;
            background-color: #fff;
            border-radius: 10px;
            box-shadow: 0 0 20px rgba(0, 0, 0, 0.1);
        }
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        .login-header h1 {
            color: #3c4b64;
            font-size: 24px;
            font-weight: 600;
        }
        .login-logo {
            width: 80px;
            height: 80px;
            margin-bottom: 20px;
        }
        .btn-login {
            background-color: #3c4b64;
            border-color: #3c4b64;
            width: 100%;
            padding: 10px;
            font-weight: 500;
        }
        .btn-login:hover {
            background-color: #2d3a4f;
            border-color: #2d3a4f;
        }
        .form-control:focus {
            border-color: #3c4b64;
            box-shadow: 0 0 0 0.25rem rgba(60, 75, 100, 0.25);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="login-container">
            <div class="login-header">
                <i class="fas fa-city login-logo"></i>
                <h1><?php echo SITE_TITLE; ?></h1>
                <p class="text-muted">Yönetim paneline giriş yapın</p>
            </div>
            
            <?php if (!empty($error_message)): ?>
                <div class="alert alert-danger" role="alert">
                    <?php echo $error_message; ?>
                </div>
            <?php endif; ?>
            
            <?php if (!empty($success_message)): ?>
                <div class="alert alert-success" role="alert">
                    <?php echo $success_message; ?>
                </div>
            <?php endif; ?>
            
            <form method="post" action="">
                <div class="mb-3">
                    <label for="username" class="form-label">Kullanıcı Adı</label>
                    <div class="input-group">
                        <span class="input-group-text"><i class="fas fa-user"></i></span>
                        <input type="text" class="form-control" id="username" name="username" required>
                    </div>
                </div>
                <div class="mb-4">
                    <label for="password" class="form-label">Şifre</label>
                    <div class="input-group">
                        <span class="input-group-text"><i class="fas fa-lock"></i></span>
                        <input type="password" class="form-control" id="password" name="password" required>
                    </div>
                </div>
                <div class="d-grid">
                    <button type="submit" class="btn btn-primary btn-login">Giriş Yap</button>
                </div>
            </form>
        </div>
    </div>
    
    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>