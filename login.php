<?php
session_start();
require_once 'includes/config.php';
require_once 'includes/functions.php';
require_once 'includes/auth.php';

// Redirect if already logged in
if (isLoggedIn()) {
    header('Location: index.php');
    exit;
}

// Process login form
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = sanitize($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';
    
    if (loginUser($username, $password)) {
        // Successful login
        header('Location: index.php');
        exit;
    } else {
        // Failed login
        $_SESSION['error_message'] = "Geçersiz kullanıcı adı veya şifre. Lütfen tekrar deneyin.";
    }
}
?>
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Giriş - <?php echo SITE_NAME; ?></title>
    
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Custom CSS -->
    <link rel="stylesheet" href="assets/css/style.css">
    
    <style>
        body {
            height: 100vh;
            display: flex;
            align-items: center;
            background-color: #f5f5f5;
        }
        
        .form-signin {
            max-width: 400px;
            padding: 15px;
            margin: auto;
        }
        
        .form-signin .form-floating:focus-within {
            z-index: 2;
        }
        
        .form-signin input[type="text"] {
            margin-bottom: -1px;
            border-bottom-right-radius: 0;
            border-bottom-left-radius: 0;
        }
        
        .form-signin input[type="password"] {
            margin-bottom: 10px;
            border-top-left-radius: 0;
            border-top-right-radius: 0;
        }
    </style>
</head>
<body class="text-center">
    <main class="form-signin w-100">
        <form method="post" action="login.php">
            <img class="mb-4" src="assets/images/municipality-logo.png" alt="Belediye Logo" width="120" height="120" onerror="this.src='https://via.placeholder.com/120?text=Logo'; this.onerror=null;">
            
            <h1 class="h3 mb-3 fw-normal">Belediye Yönetim Paneli</h1>
            
            <?php echo displayMessages(); ?>
            
            <div class="form-floating">
                <input type="text" class="form-control" id="username" name="username" placeholder="Kullanıcı Adı" required autofocus>
                <label for="username">Kullanıcı Adı</label>
            </div>
            <div class="form-floating">
                <input type="password" class="form-control" id="password" name="password" placeholder="Şifre" required>
                <label for="password">Şifre</label>
            </div>
            
            <div class="checkbox mb-3">
                <label>
                    <input type="checkbox" value="remember-me" name="remember"> Beni Hatırla
                </label>
            </div>
            
            <button class="w-100 btn btn-lg btn-primary" type="submit">
                <i class="fas fa-sign-in-alt me-2"></i>Giriş Yap
            </button>
            
            <p class="mt-5 mb-3 text-muted">&copy; <?php echo date('Y'); ?> Belediye Yönetim Sistemi</p>
        </form>
    </main>
    
    <!-- Bootstrap JS Bundle with Popper -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>