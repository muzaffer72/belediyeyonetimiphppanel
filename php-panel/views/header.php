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
    
    <!-- DataTables -->
    <link rel="stylesheet" href="https://cdn.datatables.net/1.13.4/css/dataTables.bootstrap5.min.css">
    
    <!-- Chart.js -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/chart.js@4.0.1/dist/chart.min.css">
    
    <style>
        :root {
            --primary-color: #3c4b64;
            --secondary-color: #ebedef;
            --sidebar-width: 250px;
            --sidebar-collapsed-width: 70px;
            --header-height: 60px;
            --success-color: #2eb85c;
            --info-color: #39f;
            --warning-color: #f9b115;
            --danger-color: #e55353;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f8f9fa;
            margin: 0;
            padding: 0;
            display: flex;
            flex-direction: column;
            min-height: 100vh;
        }
        
        .wrapper {
            display: flex;
            flex: 1;
        }
        
        /* Sidebar Styles */
        .sidebar {
            width: var(--sidebar-width);
            background-color: var(--primary-color);
            color: #fff;
            position: fixed;
            height: 100vh;
            z-index: 100;
            transition: all 0.3s;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
        }
        
        .sidebar.collapsed {
            width: var(--sidebar-collapsed-width);
        }
        
        .sidebar-header {
            padding: 15px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            background-color: rgba(0, 0, 0, 0.1);
            height: var(--header-height);
        }
        
        .sidebar-brand {
            font-size: 1.2rem;
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        .sidebar.collapsed .sidebar-brand {
            display: none;
        }
        
        .sidebar-toggle {
            background: none;
            border: none;
            color: #fff;
            cursor: pointer;
            font-size: 1.2rem;
        }
        
        .sidebar-menu {
            padding: 0;
            list-style: none;
            margin: 0;
        }
        
        .sidebar-item {
            position: relative;
        }
        
        .sidebar-link {
            padding: 15px;
            display: flex;
            align-items: center;
            color: rgba(255, 255, 255, 0.8);
            text-decoration: none;
            transition: all 0.3s;
        }
        
        .sidebar-link:hover, .sidebar-link.active {
            color: #fff;
            background-color: rgba(255, 255, 255, 0.1);
            text-decoration: none;
        }
        
        .sidebar-icon {
            margin-right: 15px;
            min-width: 20px;
            text-align: center;
        }
        
        .sidebar.collapsed .sidebar-title {
            display: none;
        }
        
        /* Main Content Styles */
        .main-content {
            margin-left: var(--sidebar-width);
            flex: 1;
            transition: all 0.3s;
            padding: 20px;
            padding-top: calc(var(--header-height) + 20px);
        }
        
        .main-content.expanded {
            margin-left: var(--sidebar-collapsed-width);
        }
        
        /* Header Styles */
        .main-header {
            position: fixed;
            top: 0;
            left: var(--sidebar-width);
            right: 0;
            height: var(--header-height);
            background-color: #fff;
            border-bottom: 1px solid var(--secondary-color);
            z-index: 99;
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0 20px;
            transition: all 0.3s;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.05);
        }
        
        .main-header.expanded {
            left: var(--sidebar-collapsed-width);
        }
        
        .header-left {
            display: flex;
            align-items: center;
        }
        
        .header-right {
            display: flex;
            align-items: center;
        }
        
        .header-item {
            margin-left: 15px;
            position: relative;
        }
        
        .header-icon {
            color: var(--primary-color);
            font-size: 1.2rem;
            cursor: pointer;
        }
        
        .dropdown-toggle::after {
            display: none;
        }
        
        .user-info {
            display: flex;
            align-items: center;
        }
        
        .user-name {
            margin-right: 10px;
            font-weight: 500;
        }
        
        .user-avatar {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            background-color: var(--primary-color);
            color: #fff;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 600;
        }
        
        /* Card Styles */
        .card {
            border: none;
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.05);
            margin-bottom: 20px;
        }
        
        .card-header {
            background-color: #fff;
            border-bottom: 1px solid var(--secondary-color);
            padding: 15px 20px;
            font-weight: 600;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        
        .card-body {
            padding: 20px;
        }
        
        /* Dashboard Widgets */
        .stat-card {
            border-radius: 10px;
            padding: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            color: #fff;
            margin-bottom: 20px;
            box-shadow: 0 0 15px rgba(0, 0, 0, 0.1);
            transition: all 0.3s;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.15);
        }
        
        .stat-card.primary {
            background-color: var(--primary-color);
        }
        
        .stat-card.success {
            background-color: var(--success-color);
        }
        
        .stat-card.info {
            background-color: var(--info-color);
        }
        
        .stat-card.warning {
            background-color: var(--warning-color);
        }
        
        .stat-card.danger {
            background-color: var(--danger-color);
        }
        
        .stat-card-icon {
            font-size: 3rem;
            opacity: 0.8;
        }
        
        .stat-card-info {
            text-align: right;
        }
        
        .stat-card-value {
            font-size: 2rem;
            font-weight: 600;
            margin-bottom: 5px;
        }
        
        .stat-card-label {
            font-size: 1rem;
            opacity: 0.8;
        }
        
        /* Table Styles */
        .table-container {
            background-color: #fff;
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.05);
            padding: 20px;
            margin-bottom: 20px;
        }
        
        .table-responsive {
            overflow-x: auto;
        }
        
        .table thead th {
            background-color: #f8f9fa;
            border-bottom: 2px solid var(--secondary-color);
            font-weight: 600;
        }
        
        .table-actions {
            display: flex;
            gap: 5px;
            justify-content: center;
        }
        
        .btn-action {
            width: 30px;
            height: 30px;
            padding: 0;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 5px;
        }
        
        /* Form Styles */
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-control {
            border-radius: 5px;
            padding: 10px 15px;
            border: 1px solid var(--secondary-color);
        }
        
        .form-control:focus {
            box-shadow: 0 0 0 0.25rem rgba(60, 75, 100, 0.25);
            border-color: var(--primary-color);
        }
        
        /* Badge Styles */
        .badge.bg-success {
            background-color: var(--success-color) !important;
        }
        
        .badge.bg-info {
            background-color: var(--info-color) !important;
        }
        
        .badge.bg-warning {
            background-color: var(--warning-color) !important;
        }
        
        .badge.bg-danger {
            background-color: var(--danger-color) !important;
        }
        
        /* Activity Timeline */
        .timeline {
            margin: 0;
            padding: 0;
            list-style: none;
            position: relative;
        }
        
        .timeline:before {
            content: '';
            position: absolute;
            top: 0;
            bottom: 0;
            left: 32px;
            width: 2px;
            background-color: var(--secondary-color);
        }
        
        .timeline-item {
            position: relative;
            padding-left: 70px;
            padding-bottom: 25px;
        }
        
        .timeline-badge {
            position: absolute;
            left: 10px;
            width: 45px;
            height: 45px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            background-color: #fff;
            color: var(--primary-color);
            border: 2px solid var(--secondary-color);
            z-index: 1;
        }
        
        .timeline-content {
            background-color: #fff;
            border-radius: 10px;
            padding: 15px;
            position: relative;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.05);
        }
        
        .timeline-date {
            color: #6c757d;
            font-size: 0.875rem;
        }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <nav class="sidebar" id="sidebar">
        <div class="sidebar-header">
            <div class="sidebar-brand">Belediye Yönetim Paneli</div>
            <button class="sidebar-toggle" id="sidebarToggle">
                <i class="fas fa-bars"></i>
            </button>
        </div>
        
        <ul class="sidebar-menu">
            <?php 
            require_once(__DIR__ . '/../includes/menu.php');
            $menu_items = getMenuItems($page);
            foreach ($menu_items as $item): 
            ?>
            <li class="sidebar-item">
                <a href="<?php echo $item['url']; ?>" class="sidebar-link <?php echo $item['active'] ? 'active' : ''; ?>">
                    <span class="sidebar-icon"><i class="<?php echo $item['icon']; ?>"></i></span>
                    <span class="sidebar-title"><?php echo $item['text']; ?></span>
                </a>
            </li>
            <?php endforeach; ?>
        </ul>
    </nav>
    
    <!-- Main Content -->
    <div class="wrapper">
        <div class="main-content" id="mainContent">
            <!-- Header -->
            <header class="main-header" id="mainHeader">
                <div class="header-left">
                    <ol class="breadcrumb mb-0">
                        <li class="breadcrumb-item"><a href="index.php">Ana Sayfa</a></li>
                        <?php if (isset($page) && $page !== 'dashboard'): ?>
                        <li class="breadcrumb-item active"><?php echo ucfirst($page); ?></li>
                        <?php endif; ?>
                    </ol>
                </div>
                
                <div class="header-right">
                    <div class="dropdown header-item">
                        <button class="btn dropdown-toggle" type="button" id="userDropdown" data-bs-toggle="dropdown" aria-expanded="false">
                            <div class="user-info">
                                <span class="user-name"><?php echo isset($_SESSION['admin_username']) ? $_SESSION['admin_username'] : 'Admin'; ?></span>
                                <div class="user-avatar">
                                    <i class="fas fa-user"></i>
                                </div>
                            </div>
                        </button>
                        <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="userDropdown">
                            <li><a class="dropdown-item" href="#">Profil</a></li>
                            <li><a class="dropdown-item" href="#">Ayarlar</a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><a class="dropdown-item" href="logout.php">Çıkış Yap</a></li>
                        </ul>
                    </div>
                </div>
            </header>
            
            <!-- Page Content -->
            <div class="container-fluid mt-4">
                <!-- Page Header -->
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <h1 class="h3"><?php echo isset($page) ? getPageTitle($page) : 'Belediye Yönetim Paneli'; ?></h1>
                    
                    <?php if (isset($page) && in_array($page, ['cities', 'districts', 'parties', 'posts', 'comments', 'announcements', 'users'])): ?>
                    <a href="?page=<?php echo $page; ?>&action=add" class="btn btn-primary">
                        <i class="fas fa-plus-circle me-1"></i> Yeni Ekle
                    </a>
                    <?php endif; ?>
                </div>
                
                <!-- Main Content Area -->