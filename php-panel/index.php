<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');

// Auth fonksiyonlarını dahil et
require_once(__DIR__ . '/includes/auth_functions.php');

// Fonksiyonlar config.php içinden dahil ediliyor

// Sayfa parametresi
$page = isset($_GET['page']) ? $_GET['page'] : 'dashboard';

// Açık sayfalar (giriş gerektirmeyen)
$public_pages = ['login', 'official_login'];

// Oturum kontrolü
if (!isLoggedIn() && !in_array($page, $public_pages)) {
    safeRedirect('index.php?page=login');
}

// Kullanıcı rol kontrolü - Belediye görevlisi kısıtlaması
if (isLoggedIn() && isOfficial() && !in_array($page, $public_pages) && $page != 'official_dashboard' && strpos($page, 'official_') !== 0) {
    // Belediye görevlisi sadece kendi sayfalarına erişebilir
    safeRedirect('index.php?page=official_dashboard');
}

// Kullanıcı isteği
$action = isset($_GET['action']) ? $_GET['action'] : '';

// Geçerli sayfalar
// Geçerli sayfalar
$valid_pages = [
    'dashboard', 'cities', 'districts', 'parties', 'posts', 'comments', 'announcements', 'users', 'not_found',
    'city_edit', 'city_detail', 'district_edit', 'district_detail', 'post_edit', 'post_detail', 'cozumorani',
    'user_edit', 'user_create', 'update_party_scoring', 'update_scoring', 'update_triggers', 'api', 'disable_triggers', 'manuel_query',
    'show_schema', 'trigger_posts', 'custom_sql', 'new_party_scoring', 'advanced_party_scoring', 'trigger_setup',
    'fix_post_sharing', 'use_cron_only', 'notifications', 'official_login', 'official_dashboard', 'officials',
    'district_performance', 'party_performance', 'update_district_performance', 'update_party_performance',
    'advertisements', 'ad_edit', 'ad_detail', 'ad_analytics', 'polls','poll_detail','poll_edit','poll_statistics', 'login'
];

// Sayfa geçerli mi kontrol et
if (!in_array($page, $valid_pages)) {
    $page = 'not_found';
}

// Başlık belirle
$page_title = getPageTitle($page);

// Sayfa içeriğini yükle
$page_content = __DIR__ . '/views/' . $page . '.php';

// Giriş sayfaları için header ve footer gösterme
$show_header_footer = !in_array($page, $public_pages);

// Header yükle (giriş sayfaları hariç)
if ($show_header_footer) {
    include(__DIR__ . '/views/header.php');
}

// Sayfa içeriği 
if (file_exists($page_content)) {
    include($page_content);
} else {
    echo 'Sayfa içeriği bulunamadı: ' . $page;
}

// Footer yükle (giriş sayfaları hariç)
if ($show_header_footer) {
    include(__DIR__ . '/views/footer.php');
}
?>