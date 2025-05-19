<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');

// Fonksiyonlar config.php içinden dahil ediliyor

// Oturum kontrolü
if (!isLoggedIn() && basename($_SERVER['PHP_SELF']) !== 'login.php') {
    safeRedirect('login.php');
}

// Sayfa parametresi
$page = isset($_GET['page']) ? $_GET['page'] : 'dashboard';

// Kullanıcı isteği
$action = isset($_GET['action']) ? $_GET['action'] : '';

// Geçerli sayfalar
$valid_pages = [
    'dashboard', 'cities', 'districts', 'parties', 'posts', 'comments', 'announcements', 'users', 'not_found',
    'city_edit', 'city_detail', 'district_edit', 'district_detail', 'post_edit', 'post_detail', 'cozumorani',
    'user_edit', 'update_party_scoring', 'update_scoring', 'update_triggers', 'api', 'disable_triggers', 'manuel_query',
    'show_schema', 'trigger_posts', 'custom_sql', 'new_party_scoring', 'advanced_party_scoring', 'trigger_setup',
    'fix_post_sharing'
];

// Sayfa geçerli mi kontrol et
if (!in_array($page, $valid_pages)) {
    $page = 'not_found';
}

// Başlık belirle
$page_title = getPageTitle($page);

// Sayfa içeriğini yükle
$page_content = __DIR__ . '/views/' . $page . '.php';

// Header yükle
include(__DIR__ . '/views/header.php');

// Sayfa içeriği 
if (file_exists($page_content)) {
    include($page_content);
} else {
    echo 'Sayfa içeriği bulunamadı: ' . $page;
}

// Footer yükle
include(__DIR__ . '/views/footer.php');
?>