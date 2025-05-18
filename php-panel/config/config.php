<?php
// Oturum başlat
session_start();

// Hata raporlamasını açık tut
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Zaman dilimini ayarla 
date_default_timezone_set('Europe/Istanbul');

// Temel sabitler
define('SITE_TITLE', 'Belediye Yönetim Paneli');
define('SITE_URL', 'http://localhost:8080');
define('ASSETS_URL', SITE_URL . '/assets');

// Çevre değişkenleri
$_ENV['SUPABASE_URL'] = getenv('SUPABASE_URL') ?: 'https://bimer.onvao.net:8443';
$_ENV['SUPABASE_KEY'] = getenv('SUPABASE_SERVICE_ROLE_KEY') ?: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IkpKaWFkZnlxYlBzYnRyc3dTQlF0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTY4Nzg2NDIzNCwiZXhwIjoxNzE5NDAwMjM0fQ.YNz7LS63eEHLK7vOCb3FjjsM-Uy5n9Pqo8wuJxHWPUU';

// API sabitleri
define('SUPABASE_REST_URL', $_ENV['SUPABASE_URL'] . '/rest/v1');
define('SUPABASE_API_KEY', $_ENV['SUPABASE_KEY']);
define('SUPABASE_AUTH_HEADER', 'Bearer ' . $_ENV['SUPABASE_KEY']);

// Yönetici kimlik bilgileri (gerçek uygulamada bunlar veritabanında olmalı)
define('ADMIN_USERNAME', 'admin');
define('ADMIN_PASSWORD', 'admin123');

// Özel fonksiyonlar
/**
 * XSS saldırılarına karşı HTML ve karakterleri temizle
 * 
 * @param string $value Temizlenecek değer
 * @return string Temizlenmiş değer
 */
function escape($value) {
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

/**
 * Mesaj göster (başarı, hata, bilgi, uyarı)
 * 
 * @param string $type Mesaj tipi (success, danger, info, warning)
 * @param string $message Mesaj içeriği
 * @return string HTML alert
 */
function showAlert($type, $message) {
    return '<div class="alert alert-' . $type . ' alert-dismissible fade show" role="alert">
                ' . $message . '
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
            </div>';
}

/**
 * Kullanıcının oturum durumunu kontrol et
 * 
 * @return bool Oturum durumu
 */
function isLoggedIn() {
    return isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true;
}

/**
 * Tarih formatla
 * 
 * @param string $date ISO 8601 tarih formatı
 * @param string $format Çıktı formatı
 * @return string Formatlanmış tarih
 */
function formatDate($date, $format = 'd.m.Y H:i') {
    if (empty($date)) return '-';
    
    $timestamp = strtotime($date);
    return date($format, $timestamp);
}

/**
 * Yönlendirme yap
 * 
 * @param string $url Yönlendirilecek URL
 * @return void
 */
function redirect($url) {
    header('Location: ' . $url);
    exit;
}

/**
 * Metni kısalt
 * 
 * @param string $text Metin
 * @param int $length Maksimum uzunluk
 * @return string Kısaltılmış metin
 */
function truncateText($text, $length = 100) {
    if (mb_strlen($text, 'UTF-8') <= $length) {
        return $text;
    }
    
    return rtrim(mb_substr($text, 0, $length, 'UTF-8')) . '...';
}

// Demo veriler (API bağlantısı kurulamazsa kullanılacak)
$demo_data = [
    'cities' => [
        [
            'id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'name' => 'İstanbul',
            'population' => 15840900,
            'area' => 5461,
            'mayor_name' => 'Ekrem İmamoğlu',
            'mayor_party' => 'CHP',
            'established_date' => '1923-10-29T00:00:00Z',
            'created_at' => '2023-08-15T14:22:45Z'
        ],
        [
            'id' => 'a8e7f3c1-dd9b-4f67-8ad4-12bb76431a9e',
            'name' => 'Ankara',
            'population' => 5663322,
            'area' => 24521,
            'mayor_name' => 'Mansur Yavaş',
            'mayor_party' => 'CHP',
            'established_date' => '1923-10-29T00:00:00Z',
            'created_at' => '2023-08-15T14:23:30Z'
        ],
        [
            'id' => 'b2d9e8a7-cc3f-48e1-95b2-7d65a98f3b2c',
            'name' => 'İzmir',
            'population' => 4367251,
            'area' => 11891,
            'mayor_name' => 'Tunç Soyer',
            'mayor_party' => 'CHP',
            'established_date' => '1923-10-29T00:00:00Z',
            'created_at' => '2023-08-15T14:24:15Z'
        ],
        [
            'id' => 'c1f8d7e6-bb5a-42c9-a3d7-8e94b17f2d5a',
            'name' => 'Bursa',
            'population' => 3101833,
            'area' => 10882,
            'mayor_name' => 'Alinur Aktaş',
            'mayor_party' => 'AKP',
            'established_date' => '1923-10-29T00:00:00Z',
            'created_at' => '2023-08-15T14:25:00Z'
        ],
        [
            'id' => 'd5e4c3b2-aa19-40b8-9cd6-7f23a16e5b49',
            'name' => 'Antalya',
            'population' => 2548308,
            'area' => 20177,
            'mayor_name' => 'Muhittin Böcek',
            'mayor_party' => 'CHP',
            'established_date' => '1923-10-29T00:00:00Z',
            'created_at' => '2023-08-15T14:25:45Z'
        ]
    ],
    'districts' => [
        [
            'id' => 'e9d8c7b6-9937-46a7-8bc5-6f12d5e4a3c2',
            'name' => 'Kadıköy',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'population' => 482713,
            'area' => 25.2,
            'postal_code' => '34700',
            'created_at' => '2023-08-15T14:30:15Z'
        ],
        [
            'id' => 'f8e7d6c5-8826-45b6-7ab4-5e01c4f3b2a1',
            'name' => 'Beşiktaş',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'population' => 182649,
            'area' => 11.1,
            'postal_code' => '34340',
            'created_at' => '2023-08-15T14:31:00Z'
        ],
        [
            'id' => 'g7f6e5d4-7715-44a5-6ba3-4d90b3e2a190',
            'name' => 'Çankaya',
            'city_id' => 'a8e7f3c1-dd9b-4f67-8ad4-12bb76431a9e',
            'population' => 920890,
            'area' => 124.6,
            'postal_code' => '06680',
            'created_at' => '2023-08-15T14:31:45Z'
        ],
        [
            'id' => 'h6e5d4c3-6604-43b4-5a92-3c89a2d1b089',
            'name' => 'Keçiören',
            'city_id' => 'a8e7f3c1-dd9b-4f67-8ad4-12bb76431a9e',
            'population' => 944609,
            'area' => 190.5,
            'postal_code' => '06300',
            'created_at' => '2023-08-15T14:32:30Z'
        ],
        [
            'id' => 'i5d4c3b2-5593-42c3-4b81-2b78a1c0a988',
            'name' => 'Konak',
            'city_id' => 'b2d9e8a7-cc3f-48e1-95b2-7d65a98f3b2c',
            'population' => 344678,
            'area' => 69.4,
            'postal_code' => '35260',
            'created_at' => '2023-08-15T14:33:15Z'
        ]
    ],
    'political_parties' => [
        [
            'id' => 'j4c3b2a1-4482-41d2-3a70-1a67b0b9a877',
            'name' => 'Adalet ve Kalkınma Partisi',
            'abbreviation' => 'AKP',
            'founded_date' => '2001-08-14T00:00:00Z',
            'leader_name' => 'Recep Tayyip Erdoğan',
            'logo_url' => 'https://example.com/logos/akp.png',
            'color' => '#FFA500',
            'created_at' => '2023-08-15T14:40:15Z'
        ],
        [
            'id' => 'k3b2a1z9-3371-40e1-2b69-0b56a9a8b766',
            'name' => 'Cumhuriyet Halk Partisi',
            'abbreviation' => 'CHP',
            'founded_date' => '1923-09-09T00:00:00Z',
            'leader_name' => 'Kemal Kılıçdaroğlu',
            'logo_url' => 'https://example.com/logos/chp.png',
            'color' => '#FF0000',
            'created_at' => '2023-08-15T14:41:00Z'
        ],
        [
            'id' => 'l2a1z9y8-2260-39f0-1a58-9a45b8b7c655',
            'name' => 'İyi Parti',
            'abbreviation' => 'İYİP',
            'founded_date' => '2017-10-25T00:00:00Z',
            'leader_name' => 'Meral Akşener',
            'logo_url' => 'https://example.com/logos/iyip.png',
            'color' => '#0000FF',
            'created_at' => '2023-08-15T14:41:45Z'
        ],
        [
            'id' => 'm1z9y8x7-1159-38e9-0b47-8b34a7a6b544',
            'name' => 'Milliyetçi Hareket Partisi',
            'abbreviation' => 'MHP',
            'founded_date' => '1969-02-08T00:00:00Z',
            'leader_name' => 'Devlet Bahçeli',
            'logo_url' => 'https://example.com/logos/mhp.png',
            'color' => '#800080',
            'created_at' => '2023-08-15T14:42:30Z'
        ],
        [
            'id' => 'n0y8x7w6-0048-37d8-9a36-7a23b6b5a433',
            'name' => 'Halkların Demokratik Partisi',
            'abbreviation' => 'HDP',
            'founded_date' => '2012-10-15T00:00:00Z',
            'leader_name' => 'Pervin Buldan',
            'logo_url' => 'https://example.com/logos/hdp.png',
            'color' => '#008000',
            'created_at' => '2023-08-15T14:43:15Z'
        ]
    ],
    'users' => [
        [
            'id' => 'o9x7w6v5-9937-36c7-8b25-6a12b5b4a322',
            'username' => 'ahmetk',
            'email' => 'ahmet.k@example.com',
            'full_name' => 'Ahmet Kaya',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'district_id' => 'e9d8c7b6-9937-46a7-8bc5-6f12d5e4a3c2',
            'phone_number' => '+905551234567',
            'profile_image_url' => 'https://example.com/profiles/ahmet.jpg',
            'role' => 'citizen',
            'status' => 'active',
            'created_at' => '2023-08-15T15:00:15Z'
        ],
        [
            'id' => 'p8w6v5u4-8826-35b6-7a15-5b01a4a3b211',
            'username' => 'ayses',
            'email' => 'ayse.s@example.com',
            'full_name' => 'Ayşe Saygın',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'district_id' => 'f8e7d6c5-8826-45b6-7ab4-5e01c4f3b2a1',
            'phone_number' => '+905559876543',
            'profile_image_url' => 'https://example.com/profiles/ayse.jpg',
            'role' => 'citizen',
            'status' => 'active',
            'created_at' => '2023-08-15T15:01:00Z'
        ],
        [
            'id' => 'q7v5u4t3-7715-34a5-6a05-4b90a3b2a100',
            'username' => 'mehmety',
            'email' => 'mehmet.y@example.com',
            'full_name' => 'Mehmet Yılmaz',
            'city_id' => 'a8e7f3c1-dd9b-4f67-8ad4-12bb76431a9e',
            'district_id' => 'g7f6e5d4-7715-44a5-6ba3-4d90b3e2a190',
            'phone_number' => '+905553456789',
            'profile_image_url' => 'https://example.com/profiles/mehmet.jpg',
            'role' => 'citizen',
            'status' => 'active',
            'created_at' => '2023-08-15T15:01:45Z'
        ],
        [
            'id' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'username' => 'zeynepk',
            'email' => 'zeynep.k@example.com',
            'full_name' => 'Zeynep Kılıç',
            'city_id' => 'b2d9e8a7-cc3f-48e1-95b2-7d65a98f3b2c',
            'district_id' => 'i5d4c3b2-5593-42c3-4b81-2b78a1c0a988',
            'phone_number' => '+905556789012',
            'profile_image_url' => 'https://example.com/profiles/zeynep.jpg',
            'role' => 'city_manager',
            'status' => 'active',
            'created_at' => '2023-08-15T15:02:30Z'
        ],
        [
            'id' => 's5t3s2r1-5593-32c3-4b85-2a78a1a0b988',
            'username' => 'emret',
            'email' => 'emre.t@example.com',
            'full_name' => 'Emre Taşçı',
            'city_id' => 'c1f8d7e6-bb5a-42c9-a3d7-8e94b17f2d5a',
            'district_id' => null,
            'phone_number' => '+905551230987',
            'profile_image_url' => 'https://example.com/profiles/emre.jpg',
            'role' => 'district_manager',
            'status' => 'banned',
            'created_at' => '2023-08-15T15:03:15Z'
        ]
    ],
    'posts' => [
        [
            'id' => 't4s2r1q0-4482-31d2-3a75-1b67a0a9b877',
            'user_id' => 'o9x7w6v5-9937-36c7-8b25-6a12b5b4a322',
            'title' => 'Kadıköy\'de çöpler toplanmıyor',
            'content' => 'Kadıköy Moda\'da son bir haftadır çöpler düzenli toplanmıyor. Sokaklar kötü kokuyor.',
            'type' => 'complaint',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'district_id' => 'e9d8c7b6-9937-46a7-8bc5-6f12d5e4a3c2',
            'status' => 'active',
            'is_anonymous' => false,
            'is_featured' => false,
            'is_resolved' => false,
            'view_count' => 145,
            'created_at' => '2023-08-16T09:00:15Z'
        ],
        [
            'id' => 'u3r1q0p9-3371-30e1-2b70-0a56b9b8a766',
            'user_id' => 'p8w6v5u4-8826-35b6-7a15-5b01a4a3b211',
            'title' => 'Beşiktaş sahilindeki parklar için öneri',
            'content' => 'Beşiktaş sahilindeki parklara daha fazla oturma alanı ve çocuk oyun grupları eklenebilir.',
            'type' => 'suggestion',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'district_id' => 'f8e7d6c5-8826-45b6-7ab4-5e01c4f3b2a1',
            'status' => 'active',
            'is_anonymous' => false,
            'is_featured' => true,
            'is_resolved' => false,
            'view_count' => 230,
            'created_at' => '2023-08-16T09:30:00Z'
        ],
        [
            'id' => 'v2q0p9o8-2260-29f0-1a60-9b45a8a7b655',
            'user_id' => 'q7v5u4t3-7715-34a5-6a05-4b90a3b2a100',
            'title' => 'Çankaya\'da otobüs saatleri hakkında',
            'content' => 'Çankaya\'da 312 numaralı otobüsün saatleri nedir? Sitede güncel bilgi bulamadım.',
            'type' => 'question',
            'city_id' => 'a8e7f3c1-dd9b-4f67-8ad4-12bb76431a9e',
            'district_id' => 'g7f6e5d4-7715-44a5-6ba3-4d90b3e2a190',
            'status' => 'active',
            'is_anonymous' => true,
            'is_featured' => false,
            'is_resolved' => true,
            'view_count' => 78,
            'created_at' => '2023-08-16T10:00:45Z'
        ],
        [
            'id' => 'w1p9o8n7-1159-28e9-0b50-8a34b7b6a544',
            'user_id' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'title' => 'Konak Belediyesi\'ne teşekkür',
            'content' => 'Konak Belediyesi ekiplerine mahallemizde yaptıkları peyzaj çalışmaları için teşekkürler.',
            'type' => 'thanks',
            'city_id' => 'b2d9e8a7-cc3f-48e1-95b2-7d65a98f3b2c',
            'district_id' => 'i5d4c3b2-5593-42c3-4b81-2b78a1c0a988',
            'status' => 'active',
            'is_anonymous' => false,
            'is_featured' => true,
            'is_resolved' => true,
            'view_count' => 320,
            'created_at' => '2023-08-16T10:30:30Z'
        ],
        [
            'id' => 'x0o8n7m6-0048-27d8-9a40-7b23a6a5b433',
            'user_id' => 'o9x7w6v5-9937-36c7-8b25-6a12b5b4a322',
            'title' => 'Kadıköy\'de yeni açılan park',
            'content' => 'Kadıköy\'de yeni açılan Gençlik Parkı çok güzel olmuş. Daha fazla yeşil alan görmek istiyoruz.',
            'type' => 'suggestion',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'district_id' => 'e9d8c7b6-9937-46a7-8bc5-6f12d5e4a3c2',
            'status' => 'active',
            'is_anonymous' => false,
            'is_featured' => false,
            'is_resolved' => false,
            'view_count' => 95,
            'created_at' => '2023-08-16T11:00:15Z'
        ]
    ],
    'comments' => [
        [
            'id' => 'y9n7m6l5-9937-26c7-8b30-6b12a5a4b322',
            'post_id' => 't4s2r1q0-4482-31d2-3a75-1b67a0a9b877',
            'user_id' => 'p8w6v5u4-8826-35b6-7a15-5b01a4a3b211',
            'content' => 'Aynı sorun bizim sokakta da var. Lütfen ilgilenin.',
            'is_anonymous' => false,
            'status' => 'active',
            'created_at' => '2023-08-16T09:15:15Z'
        ],
        [
            'id' => 'z8m6l5k4-8826-25b6-7a20-5a01b4b3a211',
            'post_id' => 't4s2r1q0-4482-31d2-3a75-1b67a0a9b877',
            'user_id' => 'q7v5u4t3-7715-34a5-6a05-4b90a3b2a100',
            'content' => 'Belediyeyi aradığımda bakacaklarını söylediler. Birkaç gün bekleyelim.',
            'is_anonymous' => false,
            'status' => 'active',
            'created_at' => '2023-08-16T09:20:00Z'
        ],
        [
            'id' => 'a7l5k4j3-7715-24a5-6a10-4a90b3a2b100',
            'post_id' => 'u3r1q0p9-3371-30e1-2b70-0a56b9b8a766',
            'user_id' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'content' => 'Harika bir fikir! Ben de bunu düşünüyordum.',
            'is_anonymous' => false,
            'status' => 'active',
            'created_at' => '2023-08-16T09:45:45Z'
        ],
        [
            'id' => 'b6k4j3i2-6604-23b4-5a15-3b89a2b1b099',
            'post_id' => 'v2q0p9o8-2260-29f0-1a60-9b45a8a7b655',
            'user_id' => 's5t3s2r1-5593-32c3-4b85-2a78a1a0b988',
            'content' => '312 numaralı otobüs hafta içi 06:00-23:00 arası her 15 dakikada bir çalışıyor. Hafta sonu ise 07:00-22:00 arası her 20 dakikada bir.',
            'is_anonymous' => false,
            'status' => 'active',
            'created_at' => '2023-08-16T10:10:30Z'
        ],
        [
            'id' => 'c5j3i2h1-5593-22c3-4b20-2a78b1a0a988',
            'post_id' => 'w1p9o8n7-1159-28e9-0b50-8a34b7b6a544',
            'user_id' => 'o9x7w6v5-9937-36c7-8b25-6a12b5b4a322',
            'content' => 'Gerçekten çok güzel olmuş, tebrikler.',
            'is_anonymous' => true,
            'status' => 'active',
            'created_at' => '2023-08-16T10:45:15Z'
        ]
    ],
    'municipality_announcements' => [
        [
            'id' => 'd4i2h1g0-4482-21d2-3a80-1a67b0b9a877',
            'city_id' => '9c5f6f2d-bb3a-4ec9-8c9e-f3ad0120fe8c',
            'district_id' => null,
            'title' => 'Su Kesintisi Duyurusu',
            'content' => 'İstanbul\'un bazı ilçelerinde 20 Ağustos 2023 tarihinde 09:00-17:00 saatleri arasında su kesintisi yapılacaktır.',
            'announcement_type' => 'warning',
            'start_date' => '2023-08-20T09:00:00Z',
            'end_date' => '2023-08-20T17:00:00Z',
            'status' => 'active',
            'created_by' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'created_at' => '2023-08-17T08:00:15Z'
        ],
        [
            'id' => 'e3h1g0f9-3371-20e1-2b75-0b56a9a8a766',
            'city_id' => 'a8e7f3c1-dd9b-4f67-8ad4-12bb76431a9e',
            'district_id' => 'g7f6e5d4-7715-44a5-6ba3-4d90b3e2a190',
            'title' => 'Çankaya Halk Koşusu',
            'content' => '25 Ağustos 2023 tarihinde Çankaya\'da geleneksel halk koşusu düzenlenecektir. Tüm vatandaşlarımız davetlidir.',
            'announcement_type' => 'event',
            'start_date' => '2023-08-25T09:00:00Z',
            'end_date' => '2023-08-25T12:00:00Z',
            'status' => 'active',
            'created_by' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'created_at' => '2023-08-17T08:30:00Z'
        ],
        [
            'id' => 'f2g0f9e8-2260-19f0-1a65-9a45b8a7a655',
            'city_id' => 'b2d9e8a7-cc3f-48e1-95b2-7d65a98f3b2c',
            'district_id' => 'i5d4c3b2-5593-42c3-4b81-2b78a1c0a988',
            'title' => 'Konak Sokak Hayvanları Aşılama Kampanyası',
            'content' => '27-31 Ağustos 2023 tarihleri arasında Konak ilçesinde sokak hayvanları için ücretsiz aşılama kampanyası düzenlenecektir.',
            'announcement_type' => 'info',
            'start_date' => '2023-08-27T08:00:00Z',
            'end_date' => '2023-08-31T17:00:00Z',
            'status' => 'active',
            'created_by' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'created_at' => '2023-08-17T09:00:45Z'
        ],
        [
            'id' => 'g1f9e8d7-1159-18e9-0b55-8b34a7a6b544',
            'city_id' => 'c1f8d7e6-bb5a-42c9-a3d7-8e94b17f2d5a',
            'district_id' => null,
            'title' => 'Bursa Büyükşehir Belediyesi Yol Çalışması',
            'content' => '1-10 Eylül 2023 tarihleri arasında Bursa merkez ilçelerinde kapsamlı yol çalışması yapılacaktır. Sürücülerin alternatif güzergahları kullanmaları önerilir.',
            'announcement_type' => 'warning',
            'start_date' => '2023-09-01T08:00:00Z',
            'end_date' => '2023-09-10T18:00:00Z',
            'status' => 'active',
            'created_by' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'created_at' => '2023-08-17T09:30:30Z'
        ],
        [
            'id' => 'h0e8d7c6-0048-17d8-9a45-7a23b6a5a433',
            'city_id' => 'd5e4c3b2-aa19-40b8-9cd6-7f23a16e5b49',
            'district_id' => null,
            'title' => 'Antalya Kültür ve Sanat Festivali',
            'content' => '15-20 Eylül 2023 tarihleri arasında Antalya\'da kültür ve sanat festivali düzenlenecektir. Konserler, sergiler ve gösteriler için biletler belediye gişelerinden temin edilebilir.',
            'announcement_type' => 'event',
            'start_date' => '2023-09-15T10:00:00Z',
            'end_date' => '2023-09-20T22:00:00Z',
            'status' => 'active',
            'created_by' => 'r6u4t3s2-6604-33b4-5a95-3a89b2a1a099',
            'created_at' => '2023-08-17T10:00:15Z'
        ]
    ]
];

// functions.php dosyasını dahil et
include_once(__DIR__ . '/../includes/functions.php');
?>