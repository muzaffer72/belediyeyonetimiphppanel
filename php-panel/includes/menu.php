<?php
/**
 * Menü öğelerini döndürür
 * 
 * @param string $current_page Mevcut sayfa
 * @return array Menü öğeleri dizisi
 */
function getMenuItems($current_page) {
    $menu_items = [
        ['id' => 'dashboard', 'icon' => 'fas fa-tachometer-alt', 'text' => 'Dashboard'],
        ['id' => 'cities', 'icon' => 'fas fa-city', 'text' => 'Şehirler'],
        ['id' => 'districts', 'icon' => 'fas fa-map-marker-alt', 'text' => 'İlçeler'],
        ['id' => 'parties', 'icon' => 'fas fa-flag', 'text' => 'Siyasi Partiler'],
        ['id' => 'cozumorani', 'icon' => 'fas fa-chart-line', 'text' => 'Çözüm Oranları'],
        ['id' => 'posts', 'icon' => 'fas fa-clipboard-list', 'text' => 'Gönderiler'],
        ['id' => 'comments', 'icon' => 'fas fa-comments', 'text' => 'Yorumlar'],
        ['id' => 'announcements', 'icon' => 'fas fa-bullhorn', 'text' => 'Duyurular'],
        ['id' => 'users', 'icon' => 'fas fa-users', 'text' => 'Kullanıcılar'],
    ];
    
    // Her menü öğesi için active durumunu belirle
    foreach ($menu_items as &$item) {
        $item['active'] = ($item['id'] === $current_page);
        $item['url'] = 'index.php?page=' . $item['id'];
    }
    
    return $menu_items;
}
?>