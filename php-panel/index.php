<?php
// Ana dosya
session_start();
require_once 'config/config.php';
require_once 'includes/functions.php';

// Oturum kontrolü
if (!isset($_SESSION['user_id']) && !in_array(getCurrentPage(), ['login', 'logout', ''])) {
    header('Location: login.php');
    exit;
}

// Mevcut sayfa ve başlık belirleme
$current_page = getCurrentPage();
$page_title = getPageTitle($current_page);

// Sayfa içeriğini yükle
include_once 'views/header.php';

if ($current_page && file_exists("views/{$current_page}.php")) {
    include_once "views/{$current_page}.php";
} else {
    include_once 'views/dashboard.php';
}

include_once 'views/footer.php';
?>