<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $page_title; ?> - <?php echo APP_NAME; ?></title>
    
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <!-- Custom CSS -->
    <link rel="stylesheet" href="assets/css/style.css">
</head>
<body>
    <!-- Ana Container -->
    <div class="container-fluid">
        <div class="row">
            <!-- Sidebar -->
            <nav id="sidebar" class="col-md-3 col-lg-2 d-md-block bg-dark sidebar collapse">
                <div class="position-sticky pt-3">
                    <div class="text-center mb-4">
                        <h5 class="text-white"><?php echo APP_NAME; ?></h5>
                    </div>
                    <ul class="nav flex-column">
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'dashboard' || $current_page == '' ? 'active' : ''; ?>" href="index.php">
                                <i class="fas fa-tachometer-alt me-2"></i>
                                Gösterge Paneli
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'cities' ? 'active' : ''; ?>" href="index.php?page=cities">
                                <i class="fas fa-city me-2"></i>
                                Şehirler
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'districts' ? 'active' : ''; ?>" href="index.php?page=districts">
                                <i class="fas fa-map-marker-alt me-2"></i>
                                İlçeler
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'posts' ? 'active' : ''; ?>" href="index.php?page=posts">
                                <i class="fas fa-clipboard-list me-2"></i>
                                Gönderiler
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'comments' ? 'active' : ''; ?>" href="index.php?page=comments">
                                <i class="fas fa-comments me-2"></i>
                                Yorumlar
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'announcements' ? 'active' : ''; ?>" href="index.php?page=announcements">
                                <i class="fas fa-bullhorn me-2"></i>
                                Duyurular
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'users' ? 'active' : ''; ?>" href="index.php?page=users">
                                <i class="fas fa-users me-2"></i>
                                Kullanıcılar
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'parties' ? 'active' : ''; ?>" href="index.php?page=parties">
                                <i class="fas fa-flag me-2"></i>
                                Siyasi Partiler
                            </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link <?php echo $current_page == 'settings' ? 'active' : ''; ?>" href="index.php?page=settings">
                                <i class="fas fa-cog me-2"></i>
                                Ayarlar
                            </a>
                        </li>
                        <?php if(isset($_SESSION['user_id'])): ?>
                        <li class="nav-item mt-3">
                            <a class="nav-link" href="logout.php">
                                <i class="fas fa-sign-out-alt me-2"></i>
                                Çıkış Yap
                            </a>
                        </li>
                        <?php endif; ?>
                    </ul>
                </div>
            </nav>
            
            <!-- Ana İçerik -->
            <main class="col-md-9 ms-sm-auto col-lg-10 px-md-4">
                <div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
                    <h1 class="h2"><?php echo $page_title; ?></h1>
                    
                    <?php if(isset($_SESSION['user_id'])): ?>
                    <div class="btn-toolbar mb-2 mb-md-0">
                        <div class="btn-group me-2">
                            <span class="badge bg-primary">
                                <i class="fas fa-user me-1"></i> <?php echo isset($_SESSION['username']) ? $_SESSION['username'] : 'Misafir'; ?>
                            </span>
                        </div>
                    </div>
                    <?php endif; ?>
                </div>
                
                <?php if(isset($_SESSION['message'])): ?>
                <div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
                    <?php echo $_SESSION['message']; ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                </div>
                <?php 
                    unset($_SESSION['message']);
                    unset($_SESSION['message_type']);
                endif; 
                ?>
                
                <!-- Ana içerik buraya gelecek -->