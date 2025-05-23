<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo SITE_NAME; ?></title>
    
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Custom CSS -->
    <link rel="stylesheet" href="assets/css/style.css">
    
    <!-- Chart.js for data visualization -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <!-- Top Navbar -->
    <nav class="navbar navbar-expand-lg navbar-dark bg-primary">
        <div class="container-fluid">
            <a class="navbar-brand" href="index.php">
                <i class="fas fa-city me-2"></i>
                <?php echo SITE_NAME; ?>
            </a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav" aria-controls="navbarNav" aria-expanded="false" aria-label="Toggle navigation">
                <span class="navbar-toggler-icon"></span>
            </button>
            
            <?php if(isLoggedIn()): ?>
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav ms-auto">
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle" href="#" id="navbarDropdown" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-user-circle me-1"></i>
                            <?php echo $_SESSION['username']; ?>
                        </a>
                        <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="navbarDropdown">
                            <li><a class="dropdown-item" href="index.php?page=profile">
                                <i class="fas fa-id-card me-2"></i>Profil
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><a class="dropdown-item" href="logout.php">
                                <i class="fas fa-sign-out-alt me-2"></i>Çıkış Yap
                            </a></li>
                        </ul>
                    </li>
                </ul>
            </div>
            <?php endif; ?>
        </div>
    </nav>

    <div class="container-fluid">
        <div class="row">
            <?php if(isLoggedIn()): ?>
            <!-- Sidebar -->
            <nav id="sidebar" class="col-md-3 col-lg-2 d-md-block bg-light sidebar collapse">
                <div class="position-sticky pt-3">
                    <ul class="nav flex-column">
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'dashboard' ? 'active' : ''; ?>" href="index.php?page=dashboard">
                                <i class="fas fa-tachometer-alt me-2"></i>
                                Dashboard
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'cities' ? 'active' : ''; ?>" href="index.php?page=cities">
                                <i class="fas fa-map-marker-alt me-2"></i>
                                Şehirler
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'districts' ? 'active' : ''; ?>" href="index.php?page=districts">
                                <i class="fas fa-map me-2"></i>
                                İlçeler
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'political-parties' ? 'active' : ''; ?>" href="index.php?page=political-parties">
                                <i class="fas fa-vote-yea me-2"></i>
                                Siyasi Partiler
                            </a>
                        </li>
                        
                        <li class="nav-header mt-3 mb-2 ps-3 text-muted">
                            <span>İÇERİK YÖNETİMİ</span>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'posts' ? 'active' : ''; ?>" href="index.php?page=posts">
                                <i class="fas fa-clipboard-list me-2"></i>
                                Tüm Gönderiler
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'complaints' ? 'active' : ''; ?>" href="index.php?page=complaints">
                                <i class="fas fa-exclamation-circle me-2"></i>
                                Şikayetler
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'thanks' ? 'active' : ''; ?>" href="index.php?page=thanks">
                                <i class="fas fa-thumbs-up me-2"></i>
                                Teşekkürler
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'announcements' ? 'active' : ''; ?>" href="index.php?page=announcements">
                                <i class="fas fa-bullhorn me-2"></i>
                                Duyurular
                            </a>
                        </li>
                        
                        <li class="nav-header mt-3 mb-2 ps-3 text-muted">
                            <span>KULLANICI YÖNETİMİ</span>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'users' ? 'active' : ''; ?>" href="index.php?page=users">
                                <i class="fas fa-users me-2"></i>
                                Kullanıcılar
                            </a>
                        </li>
                        
                        <?php if($_SESSION['role'] === 'admin'): ?>
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'admins' ? 'active' : ''; ?>" href="index.php?page=admins">
                                <i class="fas fa-user-shield me-2"></i>
                                Yöneticiler
                            </a>
                        </li>
                        
                        <li class="nav-header mt-3 mb-2 ps-3 text-muted">
                            <span>SİSTEM YÖNETİMİ</span>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'settings' ? 'active' : ''; ?>" href="index.php?page=settings">
                                <i class="fas fa-cog me-2"></i>
                                Ayarlar
                            </a>
                        </li>
                        
                        <li class="nav-item">
                            <a class="nav-link <?php echo ($_GET['page'] ?? '') === 'logs' ? 'active' : ''; ?>" href="index.php?page=logs">
                                <i class="fas fa-list-alt me-2"></i>
                                Sistem Logları
                            </a>
                        </li>
                        <?php endif; ?>
                    </ul>
                </div>
            </nav>
            
            <!-- Main Content -->
            <main class="col-md-9 ms-sm-auto col-lg-10 px-md-4 py-4">
                <!-- Page header and messages -->
                <div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
                    <?php
                    // Display page title based on current page
                    $page = $_GET['page'] ?? 'dashboard';
                    $titles = [
                        'dashboard' => '<i class="fas fa-tachometer-alt me-2"></i>Dashboard',
                        'cities' => '<i class="fas fa-map-marker-alt me-2"></i>Şehirler',
                        'districts' => '<i class="fas fa-map me-2"></i>İlçeler',
                        'political-parties' => '<i class="fas fa-vote-yea me-2"></i>Siyasi Partiler',
                        'posts' => '<i class="fas fa-clipboard-list me-2"></i>Tüm Gönderiler',
                        'complaints' => '<i class="fas fa-exclamation-circle me-2"></i>Şikayetler',
                        'thanks' => '<i class="fas fa-thumbs-up me-2"></i>Teşekkürler',
                        'announcements' => '<i class="fas fa-bullhorn me-2"></i>Duyurular',
                        'users' => '<i class="fas fa-users me-2"></i>Kullanıcılar',
                        'admins' => '<i class="fas fa-user-shield me-2"></i>Yöneticiler',
                        'settings' => '<i class="fas fa-cog me-2"></i>Ayarlar',
                        'logs' => '<i class="fas fa-list-alt me-2"></i>Sistem Logları',
                    ];
                    ?>
                    <h1 class="h2"><?php echo $titles[$page] ?? 'Dashboard'; ?></h1>
                </div>
                
                <?php echo displayMessages(); ?>
            <?php else: ?>
                <!-- Display content for non-logged in users -->
                <main class="col-12 px-4 py-5">
            <?php endif; ?>