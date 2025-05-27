<?php
/**
 * Menü öğelerini döndürür
 * 
 * @param string $current_page Mevcut sayfa
 * @return array Menü öğeleri dizisi
 */
function getMenuItems($current_page) {
    // Kullanıcı tipine göre menü öğelerini ayarla
    $user_type = $_SESSION['user_type'] ?? '';
    
    if ($user_type === 'official') {
        // Belediye personeli menüsü (sınırlı erişim)
        $menu_items = [
            ['id' => 'dashboard', 'icon' => 'fas fa-tachometer-alt', 'text' => 'Dashboard'],
            ['id' => 'posts', 'icon' => 'fas fa-clipboard-list', 'text' => 'Gönderiler'],
            ['id' => 'comments', 'icon' => 'fas fa-comments', 'text' => 'Yorumlar'],
            ['id' => 'users', 'icon' => 'fas fa-users', 'text' => 'Kullanıcılar'],
        ];
    } elseif ($user_type === 'moderator') {
        // Moderatör menüsü (sınırlı yönetim)
        $menu_items = [
            ['id' => 'dashboard', 'icon' => 'fas fa-tachometer-alt', 'text' => 'Dashboard'],
            ['id' => 'posts', 'icon' => 'fas fa-clipboard-list', 'text' => 'Gönderiler'],
            ['id' => 'users', 'icon' => 'fas fa-users', 'text' => 'Kullanıcılar'],
            ['id' => 'cities', 'icon' => 'fas fa-city', 'text' => 'Şehir Profili'],
            ['id' => 'districts', 'icon' => 'fas fa-map-marker-alt', 'text' => 'İlçe Profilleri'],
        ];
    } else {
        // Admin menüsü (tam erişim)
        $menu_items = [
            ['id' => 'dashboard', 'icon' => 'fas fa-tachometer-alt', 'text' => 'Dashboard'],
            ['id' => 'cities', 'icon' => 'fas fa-city', 'text' => 'Şehirler'],
            ['id' => 'districts', 'icon' => 'fas fa-map-marker-alt', 'text' => 'İlçeler'],
            ['id' => 'parties', 'icon' => 'fas fa-flag', 'text' => 'Siyasi Partiler'],
            ['id' => 'cozumorani', 'icon' => 'fas fa-chart-line', 'text' => 'Çözüm Oranları'],
            ['id' => 'use_cron_only', 'icon' => 'fas fa-cogs', 'text' => 'Puanlama Sistemi'],
            ['id' => 'notifications', 'icon' => 'fas fa-bell', 'text' => 'Bildirimler'],
            ['id' => 'posts', 'icon' => 'fas fa-clipboard-list', 'text' => 'Gönderiler'],
            ['id' => 'comments', 'icon' => 'fas fa-comments', 'text' => 'Yorumlar'],
            ['id' => 'announcements', 'icon' => 'fas fa-bullhorn', 'text' => 'Duyurular'],
            ['id' => 'users', 'icon' => 'fas fa-users', 'text' => 'Kullanıcılar'],
            ['id' => 'officials', 'icon' => 'fas fa-user-tie', 'text' => 'Belediye Görevlileri'],
            ['id' => 'polls', 'icon' => 'fas fa-poll', 'text' => 'Anketler'],
            ['id' => 'advertisements', 'icon' => 'fas fa-ad', 'text' => 'Sponsorlu Reklamlar'],
        ];
    }
    
    // Her menü öğesi için active durumunu belirle
    foreach ($menu_items as &$item) {
        $item['active'] = ($item['id'] === $current_page);
        $item['url'] = 'index.php?page=' . $item['id'];
    }
    
    return $menu_items;
}
?>