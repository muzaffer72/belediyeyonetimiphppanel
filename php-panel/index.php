<?php
// Konfigürasyon dosyası
require_once 'config/config.php';

// Fonksiyonlar
require_once 'includes/functions.php';

// Kullanıcı giriş kontrolü
if (!isLoggedIn() && $_GET['page'] !== 'login') {
    header('Location: login.php');
    exit;
}

// Sayfa parametresi
$page = isset($_GET['page']) ? $_GET['page'] : 'dashboard';

// Geçerli sayfalar listesi
$valid_pages = [
    'dashboard', 'cities', 'districts', 'parties', 
    'posts', 'comments', 'announcements', 'users',
    'post_detail', 'user_detail', 'district_detail', 'city_detail',
    'user_edit', 'city_edit', 'district_edit', 'featured_posts'
];

// Sayfa geçerli değilse
if (!in_array($page, $valid_pages)) {
    $page = 'not_found';
}

// Sayfa başlığı
$page_title = getPageTitle($page);

// Sayfayı dahil et
$page_path = 'views/' . $page . '.php';
if (!file_exists($page_path)) {
    $page_path = 'views/not_found.php';
}

// Ana menü öğeleri
$menu_items = getMainMenuItems($page);
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
        :root {
            --primary-color: #0d6efd;
            --secondary-color: #6c757d;
            --success-color: #198754;
            --info-color: #0dcaf0;
            --warning-color: #ffc107;
            --danger-color: #dc3545;
            --light-color: #f8f9fa;
            --dark-color: #212529;
        }
        
        body {
            font-family: 'Roboto', sans-serif;
            background-color: #f5f5f5;
        }
        
        .sidebar {
            min-width: 250px;
            max-width: 250px;
            background-color: #343a40;
            color: #fff;
            height: 100vh;
            position: fixed;
            left: 0;
            top: 0;
            z-index: 1000;
            overflow-y: auto;
            transition: all 0.3s;
        }
        
        .sidebar.collapsed {
            margin-left: -250px;
        }
        
        .sidebar .sidebar-header {
            padding: 20px;
            background-color: #2c3136;
        }
        
        .sidebar ul.components {
            padding: 20px 0;
        }
        
        .sidebar ul li a {
            padding: 10px 20px;
            display: block;
            color: rgba(255, 255, 255, 0.8);
            border-left: 3px solid transparent;
            text-decoration: none;
        }
        
        .sidebar ul li a:hover,
        .sidebar ul li a.active {
            color: #fff;
            background-color: rgba(255, 255, 255, 0.05);
            border-left-color: var(--primary-color);
        }
        
        .sidebar ul li a i {
            margin-right: 10px;
            width: 20px;
            text-align: center;
        }
        
        .content {
            width: calc(100% - 250px);
            min-height: 100vh;
            margin-left: 250px;
            transition: all 0.3s;
        }
        
        .content.expanded {
            width: 100%;
            margin-left: 0;
        }
        
        .navbar {
            background-color: #fff;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
        }
        
        .card {
            border-radius: 10px;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
            border: none;
            margin-bottom: 20px;
        }
        
        .card-header {
            font-weight: 500;
            background-color: #fff;
            border-bottom: 1px solid rgba(0, 0, 0, 0.1);
        }
        
        .table-responsive {
            overflow-x: auto;
        }
        
        .table {
            white-space: nowrap;
        }
        
        .table th {
            font-weight: 600;
            background-color: #f8f9fa;
        }
        
        .btn-sm {
            padding: 0.25rem 0.5rem;
            font-size: 0.75rem;
        }
        
        .progress {
            height: 0.75rem;
            font-size: 0.65rem;
        }
        
        .breadcrumb {
            background-color: transparent;
            padding: 0;
            margin-bottom: 1rem;
        }
        
        .avatar-sm {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            object-fit: cover;
        }
        
        .dropdown-toggle::after {
            display: none;
        }
        
        /* Mobil için responsive düzenlemeler */
        @media (max-width: 768px) {
            .sidebar {
                margin-left: -250px;
            }
            
            .sidebar.active {
                margin-left: 0;
            }
            
            .content {
                width: 100%;
                margin-left: 0;
            }
            
            .content.active {
                width: calc(100% - 250px);
                margin-left: 250px;
            }
            
            .navbar-toggler {
                display: block;
            }
        }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <nav id="sidebar" class="sidebar">
        <div class="sidebar-header">
            <h5 class="mb-0">Bimer Yönetim Paneli</h5>
            <small class="text-light">v1.0</small>
        </div>
        
        <ul class="list-unstyled components">
            <?php foreach ($menu_items as $item): ?>
                <li>
                    <a href="<?php echo $item['url']; ?>" class="<?php echo $item['active'] ? 'active' : ''; ?>">
                        <i class="<?php echo $item['icon']; ?>"></i>
                        <?php echo $item['title']; ?>
                    </a>
                </li>
            <?php endforeach; ?>
            
            <li>
                <a href="logout.php">
                    <i class="fas fa-sign-out-alt"></i>
                    Çıkış Yap
                </a>
            </li>
        </ul>
    </nav>
    
    <!-- Page Content -->
    <div id="content" class="content">
        <!-- Navbar -->
        <nav class="navbar navbar-expand-lg navbar-light">
            <div class="container-fluid">
                <button type="button" id="sidebarToggle" class="btn btn-light">
                    <i class="fas fa-bars"></i>
                </button>
                
                <div class="navbar-collapse">
                    <ul class="navbar-nav ms-auto">
                        <li class="nav-item dropdown">
                            <a class="nav-link dropdown-toggle" href="#" id="userDropdown" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                                <i class="fas fa-user-circle me-1"></i>
                                <?php echo isset($_SESSION['display_name']) ? $_SESSION['display_name'] : $_SESSION['username']; ?>
                            </a>
                            <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="userDropdown">
                                <li><a class="dropdown-item" href="index.php?page=profile"><i class="fas fa-user me-2"></i> Profil</a></li>
                                <li><a class="dropdown-item" href="index.php?page=settings"><i class="fas fa-cog me-2"></i> Ayarlar</a></li>
                                <li><hr class="dropdown-divider"></li>
                                <li><a class="dropdown-item" href="logout.php"><i class="fas fa-sign-out-alt me-2"></i> Çıkış Yap</a></li>
                            </ul>
                        </li>
                    </ul>
                </div>
            </div>
        </nav>
        
        <!-- Main Content -->
        <div class="container-fluid py-4">
            <?php include $page_path; ?>
        </div>
    </div>
    
    <!-- Bootstrap & jQuery JS -->
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js"></script>
    
    <!-- Custom JS -->
    <script>
        // Sidebar Toggle
        document.getElementById('sidebarToggle').addEventListener('click', function() {
            document.getElementById('sidebar').classList.toggle('collapsed');
            document.getElementById('content').classList.toggle('expanded');
        });
        
        // Mobil görünümde otomatik sidebar collapse
        function checkSize() {
            if (window.innerWidth < 768) {
                document.getElementById('sidebar').classList.add('collapsed');
                document.getElementById('content').classList.add('expanded');
            } else {
                document.getElementById('sidebar').classList.remove('collapsed');
                document.getElementById('content').classList.remove('expanded');
            }
        }
        
        // Sayfa yüklendiğinde ve boyut değiştiğinde kontrol et
        window.addEventListener('resize', checkSize);
        window.addEventListener('load', checkSize);
    </script>
</body>
</html>