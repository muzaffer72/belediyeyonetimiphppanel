<?php
// Oturum başlat
session_start();

// Temel URL ayarları
define('BASE_URL', 'http://' . $_SERVER['HTTP_HOST'] . '/php-panel');
define('SITE_TITLE', 'Bimer Belediye Yönetim Paneli');

// Supabase API ayarları
define('SUPABASE_URL', 'https://bimer.onvao.net:8443');
define('SUPABASE_REST_URL', SUPABASE_URL . '/rest/v1');
define('SUPABASE_API_KEY', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q');
define('SUPABASE_AUTH_HEADER', 'Bearer ' . SUPABASE_API_KEY);

// Veritabanı demo verileri (API çalışmazsa kullanılacak)
$demo_data = [
    'cities' => [
        ['id' => '550e8400-e29b-41d4-a716-446655440001', 'name' => 'Adana', 'website' => 'https://www.adana.bel.tr', 'phone' => '+90 322 455 35 00', 'email' => 'info@adana.bel.tr', 'address' => 'Reşatbey Mahallesi, Atatürk Caddesi No:2, Merkez, Seyhan/ADANA', 'mayor_name' => 'Ahmet Yılmaz', 'mayor_party' => 'Cumhuriyet Halk Partisi', 'population' => '2.258.715', 'created_at' => '2025-05-08 22:15:39'],
        ['id' => '550e8400-e29b-41d4-a716-446655440002', 'name' => 'Ankara', 'website' => 'https://www.ankara.bel.tr', 'phone' => '+90 312 507 10 00', 'email' => 'info@ankara.bel.tr', 'address' => 'Hipodrom Caddesi No:5 Yenimahalle/ANKARA', 'mayor_name' => 'Mehmet Yavaş', 'mayor_party' => 'Cumhuriyet Halk Partisi', 'population' => '5.747.325', 'created_at' => '2025-05-08 22:15:39'],
        ['id' => '550e8400-e29b-41d4-a716-446655440003', 'name' => 'İstanbul', 'website' => 'https://www.ibb.istanbul', 'phone' => '+90 212 455 13 00', 'email' => 'info@ibb.istanbul', 'address' => 'Kemalpaşa Mah. 15 Temmuz Şehitleri Cad. No:5 Saraçhane Fatih/İSTANBUL', 'mayor_name' => 'Ekrem İmamoğlu', 'mayor_party' => 'Cumhuriyet Halk Partisi', 'population' => '15.840.900', 'created_at' => '2025-05-08 22:15:39']
    ],
    'districts' => [
        ['id' => '660e8400-e29b-41d4-a716-446655500001', 'city_id' => '550e8400-e29b-41d4-a716-446655440001', 'name' => 'Seyhan', 'website' => 'https://www.seyhan.bel.tr', 'phone' => '+90 322 433 60 13', 'email' => 'info@seyhan.bel.tr', 'mayor_name' => 'Ali Yılmaz', 'mayor_party' => 'Cumhuriyet Halk Partisi', 'population' => '800.245', 'created_at' => '2025-05-08 22:15:39'],
        ['id' => '660e8400-e29b-41d4-a716-446655500002', 'city_id' => '550e8400-e29b-41d4-a716-446655440002', 'name' => 'Çankaya', 'website' => 'https://www.cankaya.bel.tr', 'phone' => '+90 312 458 89 00', 'email' => 'info@cankaya.bel.tr', 'mayor_name' => 'Alper Taşdelen', 'mayor_party' => 'Cumhuriyet Halk Partisi', 'population' => '920.890', 'created_at' => '2025-05-08 22:15:39'],
        ['id' => '660e8400-e29b-41d4-a716-446655500003', 'city_id' => '550e8400-e29b-41d4-a716-446655440003', 'name' => 'Kadıköy', 'website' => 'https://www.kadikoy.bel.tr', 'phone' => '+90 216 542 50 00', 'email' => 'info@kadikoy.bel.tr', 'mayor_name' => 'Şerdil Dara Odabaşı', 'mayor_party' => 'Cumhuriyet Halk Partisi', 'population' => '458.638', 'created_at' => '2025-05-08 22:15:39']
    ],
    'political_parties' => [
        ['id' => '04397adc-b513-4b4e-a518-230f7aa7565d', 'name' => 'Cumhuriyet Halk Partisi', 'logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/9/92/Logo_of_the_Republican_People%27s_Party_%28Turkey%29.svg', 'score' => '6.8', 'created_at' => '2025-05-17 06:59:07'],
        ['id' => '04397adc-b513-4b4e-a518-230f7aa7565e', 'name' => 'Adalet ve Kalkınma Partisi', 'logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a6/Logo_of_the_Justice_and_Development_Party_%28Turkey%29.svg/2048px-Logo_of_the_Justice_and_Development_Party_%28Turkey%29.svg.png', 'score' => '7.2', 'created_at' => '2025-05-17 06:59:07'],
        ['id' => '04397adc-b513-4b4e-a518-230f7aa7565f', 'name' => 'İyi Parti', 'logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7d/Logo_of_the_Good_Party_%28Turkey%29.svg/2048px-Logo_of_the_Good_Party_%28Turkey%29.svg.png', 'score' => '5.4', 'created_at' => '2025-05-17 06:59:07']
    ],
    'users' => [
        ['id' => '83190944-98d5-41be-ac3a-178676faf017', 'email' => 'admin@bimer.com', 'username' => 'Admin', 'role' => 'admin', 'city' => 'İstanbul', 'district' => 'Kadıköy', 'created_at' => '2025-05-17 20:58:13'],
        ['id' => '83190944-98d5-41be-ac3a-178676faf018', 'email' => 'moderator@bimer.com', 'username' => 'Moderator', 'role' => 'moderator', 'city' => 'Ankara', 'district' => 'Çankaya', 'created_at' => '2025-05-17 20:58:13'],
        ['id' => '83190944-98d5-41be-ac3a-178676faf019', 'email' => 'user@bimer.com', 'username' => 'Standart Kullanıcı', 'role' => 'user', 'city' => 'Adana', 'district' => 'Seyhan', 'created_at' => '2025-05-17 20:58:13']
    ],
    'posts' => [
        ['id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b6', 'user_id' => '83190944-98d5-41be-ac3a-178676faf019', 'title' => 'Çöpler toplanmıyor', 'description' => 'Mahallemizde 3 gündür çöpler toplanmadı. Lütfen ilgilenin.', 'type' => 'complaint', 'city' => 'Adana', 'district' => 'Seyhan', 'like_count' => 12, 'comment_count' => 3, 'is_resolved' => 'false', 'created_at' => '2025-05-17 19:30:00'],
        ['id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b7', 'user_id' => '83190944-98d5-41be-ac3a-178676faf018', 'title' => 'Parklar için öneri', 'description' => 'Mahallemizde bulunan parkta daha fazla oturma alanı olmalı.', 'type' => 'suggestion', 'city' => 'Ankara', 'district' => 'Çankaya', 'like_count' => 25, 'comment_count' => 5, 'created_at' => '2025-05-17 20:15:00'],
        ['id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b8', 'user_id' => '83190944-98d5-41be-ac3a-178676faf017', 'title' => 'Yol çalışmaları teşekkürü', 'description' => 'Mahallemizde yapılan yol çalışmaları için teşekkürler.', 'type' => 'thanks', 'city' => 'İstanbul', 'district' => 'Kadıköy', 'like_count' => 45, 'comment_count' => 8, 'created_at' => '2025-05-17 21:00:00']
    ],
    'comments' => [
        ['id' => '74b0e3b9-2851-4b94-8d14-b543a1f875f7', 'post_id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b6', 'user_id' => '83190944-98d5-41be-ac3a-178676faf017', 'content' => 'İlgili birimlerimize bilgi verilmiştir.', 'created_at' => '2025-05-17 20:00:00'],
        ['id' => '74b0e3b9-2851-4b94-8d14-b543a1f875f8', 'post_id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b7', 'user_id' => '83190944-98d5-41be-ac3a-178676faf018', 'content' => 'Güzel bir öneri, değerlendireceğiz.', 'created_at' => '2025-05-17 20:30:00'],
        ['id' => '74b0e3b9-2851-4b94-8d14-b543a1f875f9', 'post_id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b8', 'user_id' => '83190944-98d5-41be-ac3a-178676faf019', 'content' => 'Ben de bu çalışmalardan memnunum.', 'created_at' => '2025-05-17 21:15:00']
    ],
    'municipality_announcements' => [
        ['id' => '14eb03df-0929-4844-9e41-05e6b99f626f', 'municipality_id' => '550e8400-e29b-41d4-a716-446655440003', 'title' => 'İstanbul Belediyesi Ücretsiz Sağlık Taramaları', 'content' => 'Önümüzdeki hafta boyunca İstanbul Belediyesi Sağlık Merkezinde ücretsiz sağlık taramaları gerçekleştirilecektir. Tüm İstanbulluları bekliyoruz.', 'is_active' => 'true', 'created_at' => '2025-05-17 09:30:00'],
        ['id' => '14eb03df-0929-4844-9e41-05e6b99f626g', 'municipality_id' => '550e8400-e29b-41d4-a716-446655440002', 'title' => 'Ankara Belediyesi Su Kesintisi Duyurusu', 'content' => 'Çankaya ilçesinde yarın 09:00-15:00 saatleri arasında bakım çalışmaları nedeniyle su kesintisi yaşanacaktır.', 'is_active' => 'true', 'created_at' => '2025-05-17 10:00:00'],
        ['id' => '14eb03df-0929-4844-9e41-05e6b99f626h', 'municipality_id' => '550e8400-e29b-41d4-a716-446655440001', 'title' => 'Adana Belediyesi Kültür Etkinlikleri', 'content' => 'Bu hafta sonu Adana Belediyesi Kültür Merkezinde ücretsiz konser düzenlenecektir. Tüm halkımız davetlidir.', 'is_active' => 'true', 'created_at' => '2025-05-17 11:30:00']
    ],
    'likes' => [
        ['id' => '409d334b-f853-4d34-8a5e-4bd98ff472fe', 'post_id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b6', 'user_id' => '83190944-98d5-41be-ac3a-178676faf017', 'created_at' => '2025-05-17 20:10:00'],
        ['id' => '409d334b-f853-4d34-8a5e-4bd98ff472ff', 'post_id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b7', 'user_id' => '83190944-98d5-41be-ac3a-178676faf018', 'created_at' => '2025-05-17 20:35:00'],
        ['id' => '409d334b-f853-4d34-8a5e-4bd98ff472fg', 'post_id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b8', 'user_id' => '83190944-98d5-41be-ac3a-178676faf019', 'created_at' => '2025-05-17 21:20:00']
    ],
    'featured_posts' => [
        ['id' => '24', 'post_id' => '9ac049a6-44ce-4a86-a0d9-86ee059fa8b8', 'user_id' => '83190944-98d5-41be-ac3a-178676faf017', 'created_at' => '2025-05-17 22:00:00']
    ],
    'user_bans' => [
        ['id' => '2d570df7-f91d-4028-a746-9ab56e0e34cf', 'user_id' => '83190944-98d5-41be-ac3a-178676faf019', 'banned_by' => '83190944-98d5-41be-ac3a-178676faf017', 'reason' => 'Kural ihlali', 'ban_start' => '2025-05-20 00:00:00', 'ban_end' => '2025-05-27 00:00:00', 'content_action' => 'none', 'is_active' => 'false', 'created_at' => '2025-05-17 22:10:00']
    ]
];

// Tüm tabloları global değişken olarak tanımla
global $demo_data;

// Admin kullanıcıları
$admin_users = [
    [
        'username' => 'admin',
        'password' => 'admin123',
        'display_name' => 'Admin Kullanıcı',
        'email' => 'admin@bimer.com',
        'role' => 'admin'
    ]
];

// Geçerli kullanıcı kimliğini al
function getCurrentUserId() {
    return $_SESSION['user_id'] ?? null;
}

// Geçerli kullanıcı rolünü al
function getCurrentUserRole() {
    return $_SESSION['user_role'] ?? null;
}

// Kullanıcı giriş durumunu kontrol et
function isLoggedIn() {
    return isset($_SESSION['user_id']) && isset($_SESSION['username']);
}

// Admin girişi kontrolü
function isAdmin() {
    return isLoggedIn() && $_SESSION['user_role'] === 'admin';
}

// XSS koruması için içeriği temizle
function escape($str) {
    return htmlspecialchars($str, ENT_QUOTES, 'UTF-8');
}

// Tarih formatla
function formatDate($dateStr, $format = 'd.m.Y H:i') {
    if (empty($dateStr)) return '';
    $date = new DateTime($dateStr);
    return $date->format($format);
}

// Yönlendirme
function redirect($url) {
    header("Location: $url");
    exit;
}
?>