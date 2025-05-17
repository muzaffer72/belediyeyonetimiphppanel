<?php
// Temel fonksiyonlar

/**
 * Mevcut sayfanın adını al
 */
function getCurrentPage() {
    $page = '';
    $script_name = basename($_SERVER['SCRIPT_FILENAME']);
    
    if ($script_name === 'index.php' && isset($_GET['page'])) {
        $page = $_GET['page'];
    } elseif ($script_name !== 'index.php') {
        $page = basename($script_name, '.php');
    }
    
    return $page;
}

/**
 * Sayfa başlığını al
 */
function getPageTitle($page) {
    global $page_titles;
    return isset($page_titles[$page]) ? $page_titles[$page] : APP_NAME;
}

/**
 * Supabase API isteği gönder
 */
function supabaseRequest($table, $method = 'GET', $params = [], $headers = []) {
    $url = API_URL . '/' . $table;
    
    // Varsayılan başlıklar
    $default_headers = [
        'apikey: ' . API_KEY,
        'Authorization: Bearer ' . API_KEY,
        'Content-Type: application/json',
        'Prefer: return=representation'
    ];
    
    // Başlıkları birleştir
    $headers = array_merge($default_headers, $headers);
    
    // GET istekleri için query parametreleri
    if ($method === 'GET' && !empty($params)) {
        $url .= '?' . http_build_query($params);
    }
    
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    
    // POST, PUT, DELETE için veri gönder
    if ($method !== 'GET' && !empty($params)) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($params));
    }
    
    // HTTP metodunu ayarla
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    
    // SSL doğrulamasını devre dışı bırak (geliştirme ortamında)
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    
    if (curl_errno($ch)) {
        $error = curl_error($ch);
        curl_close($ch);
        return [
            'error' => true,
            'message' => $error,
            'code' => $http_code
        ];
    }
    
    curl_close($ch);
    
    // JSON yanıtını işle
    $data = json_decode($response, true);
    
    // Hata kontrolü
    if ($http_code >= 400) {
        return [
            'error' => true,
            'message' => isset($data['message']) ? $data['message'] : 'API isteği başarısız oldu',
            'code' => $http_code,
            'response' => $data
        ];
    }
    
    return [
        'error' => false,
        'data' => $data,
        'code' => $http_code
    ];
}

/**
 * Demo verileri kullan (API bağlantısı çalışmadığında)
 */
function getDemoData($table) {
    $demo_data = [
        'cities' => [
            [
                'id' => 'city-01',
                'name' => 'Ankara',
                'email' => 'info@ankara.bel.tr',
                'mayor_name' => 'Mansur Yavaş',
                'mayor_party' => 'CHP',
                'population' => '5.5M',
                'logo_url' => 'https://upload.wikimedia.org/wikipedia/tr/9/99/Ankara_B%C3%BCy%C3%BCk%C5%9Fehir_Belediyesi_logo.png',
                'party_logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/d/dd/CHP_logo.png'
            ],
            [
                'id' => 'city-02',
                'name' => 'İstanbul',
                'email' => 'info@ibb.gov.tr',
                'mayor_name' => 'Ekrem İmamoğlu',
                'mayor_party' => 'CHP',
                'population' => '16M',
                'logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/a/a8/%C4%B0BB_logo.png',
                'party_logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/d/dd/CHP_logo.png'
            ],
            [
                'id' => 'city-03',
                'name' => 'İzmir',
                'email' => 'info@izmir.bel.tr',
                'mayor_name' => 'Cemil Tugay',
                'mayor_party' => 'CHP',
                'population' => '4.4M',
                'logo_url' => 'https://upload.wikimedia.org/wikipedia/tr/2/20/Izmir_Buyuksehir_Belediyesi.png',
                'party_logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/d/dd/CHP_logo.png'
            ]
        ],
        'districts' => [
            [
                'id' => 'district-01',
                'name' => 'Çankaya',
                'email' => 'info@cankaya.bel.tr',
                'city_id' => 'city-01',
                'mayor_name' => 'Hüseyin Boz',
                'mayor_party' => 'CHP',
                'population' => '600K',
                'logo_url' => 'https://upload.wikimedia.org/wikipedia/tr/f/f2/%C3%87ankaya_Belediyesi_logo.png',
                'party_logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/d/dd/CHP_logo.png'
            ],
            [
                'id' => 'district-02',
                'name' => 'Keçiören',
                'email' => 'info@kecioren.bel.tr',
                'city_id' => 'city-01',
                'mayor_name' => 'Mesut Akgül',
                'mayor_party' => 'AK Parti',
                'population' => '950K',
                'logo_url' => 'https://www.kecioren.bel.tr/varliklar/img/logo.png',
                'party_logo_url' => 'https://upload.wikimedia.org/wikipedia/tr/d/d5/Adalet_ve_Kalk%C4%B1nma_Partisi_logo.png'
            ],
            [
                'id' => 'district-03',
                'name' => 'Kadıköy',
                'email' => 'info@kadikoy.bel.tr',
                'city_id' => 'city-02',
                'mayor_name' => 'Şerdil Odabaşı',
                'mayor_party' => 'CHP',
                'population' => '420K',
                'logo_url' => 'https://www.kadikoy.bel.tr/Content/template/MainTemplate/frontend/img/logo.png',
                'party_logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/d/dd/CHP_logo.png'
            ]
        ],
        'political_parties' => [
            [
                'id' => 'party-01',
                'name' => 'CHP',
                'logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/d/dd/CHP_logo.png'
            ],
            [
                'id' => 'party-02',
                'name' => 'AK Parti',
                'logo_url' => 'https://upload.wikimedia.org/wikipedia/tr/d/d5/Adalet_ve_Kalk%C4%B1nma_Partisi_logo.png'
            ],
            [
                'id' => 'party-03',
                'name' => 'MHP',
                'logo_url' => 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3c/Logo_of_the_Nationalist_Movement_Party.svg/800px-Logo_of_the_Nationalist_Movement_Party.svg.png'
            ]
        ],
        'posts' => [
            [
                'id' => 'post-01',
                'title' => 'Sokaktaki çöpler toplanmıyor',
                'content' => 'Evimizin önündeki çöpler 3 gündür toplanmıyor, lütfen ilgilenin.',
                'type' => 'complaint',
                'user_id' => 'user-01',
                'username' => 'ahmet.yilmaz',
                'is_resolved' => false,
                'created_at' => '2023-05-15T12:30:00Z'
            ],
            [
                'id' => 'post-02',
                'title' => 'Parkta daha fazla bank olmalı',
                'content' => 'Mahalle parkımızda yeterli bank yok, lütfen ekleyin.',
                'type' => 'suggestion',
                'user_id' => 'user-03',
                'username' => 'mehmet.kaya',
                'is_resolved' => false,
                'created_at' => '2023-05-15T11:30:00Z'
            ],
            [
                'id' => 'post-03',
                'title' => 'Trafik ışıkları çalışmıyor',
                'content' => 'Ana caddedeki trafik ışıkları arızalı, kazaya sebep olabilir.',
                'type' => 'complaint',
                'user_id' => 'user-05',
                'username' => 'can.ozturk',
                'is_resolved' => false,
                'created_at' => '2023-05-15T10:00:00Z'
            ]
        ],
        'users' => [
            [
                'id' => 'user-01',
                'username' => 'ahmet.yilmaz',
                'email' => 'ahmet@example.com',
                'full_name' => 'Ahmet Yılmaz',
                'role' => 'user',
                'created_at' => '2023-01-15T08:30:00Z'
            ],
            [
                'id' => 'user-02',
                'username' => 'ayse.demir',
                'email' => 'ayse@example.com',
                'full_name' => 'Ayşe Demir',
                'role' => 'user',
                'created_at' => '2023-02-20T14:15:00Z'
            ],
            [
                'id' => 'user-03',
                'username' => 'mehmet.kaya',
                'email' => 'mehmet@example.com',
                'full_name' => 'Mehmet Kaya',
                'role' => 'user',
                'created_at' => '2023-03-10T11:45:00Z'
            ],
            [
                'id' => 'user-04',
                'username' => 'zeynep.yildiz',
                'email' => 'zeynep@example.com',
                'full_name' => 'Zeynep Yıldız',
                'role' => 'user',
                'created_at' => '2023-04-05T09:20:00Z'
            ],
            [
                'id' => 'user-05',
                'username' => 'can.ozturk',
                'email' => 'can@example.com',
                'full_name' => 'Can Öztürk',
                'role' => 'user',
                'created_at' => '2023-05-01T16:30:00Z'
            ],
            [
                'id' => 'admin-01',
                'username' => 'admin',
                'email' => 'admin@belediye.gov.tr',
                'full_name' => 'Sistem Yöneticisi',
                'role' => 'admin',
                'created_at' => '2023-01-01T00:00:00Z'
            ]
        ]
    ];
    
    return isset($demo_data[$table]) ? $demo_data[$table] : [];
}

/**
 * Verileri getir (önce API'den dene, başarısız olursa demo verilere düş)
 */
function getData($table, $params = []) {
    // Supabase API'den veri çekmeyi dene
    $response = supabaseRequest($table, 'GET', $params);
    
    // API başarılı olursa sonuçları döndür
    if (!$response['error'] && isset($response['data'])) {
        return [
            'success' => true,
            'data' => $response['data'],
            'source' => 'api'
        ];
    }
    
    // API başarısız olursa demo verileri kullan
    return [
        'success' => true,
        'data' => getDemoData($table),
        'source' => 'demo',
        'api_error' => $response['error'] ? $response['message'] : 'Bilinmeyen hata'
    ];
}

/**
 * Veri ekle
 */
function addData($table, $data) {
    return supabaseRequest($table, 'POST', $data);
}

/**
 * Veri güncelle
 */
function updateData($table, $id, $data) {
    $params = ['id' => 'eq.' . $id];
    return supabaseRequest($table, 'PATCH', $data, [], $params);
}

/**
 * Veri sil
 */
function deleteData($table, $id) {
    $params = ['id' => 'eq.' . $id];
    return supabaseRequest($table, 'DELETE', [], [], $params);
}

/**
 * Güvenli giriş kontrolü
 */
function authenticate($username, $password) {
    // Gerçek uygulamada burada Supabase Auth kullanılabilir
    // Şimdilik basit bir demo login
    
    if ($username === 'admin' && $password === 'admin123') {
        $_SESSION['user_id'] = 'admin-01';
        $_SESSION['username'] = 'admin';
        $_SESSION['role'] = 'admin';
        return true;
    }
    
    return false;
}

/**
 * Tarih formatlama
 */
function formatDate($date, $format = 'd.m.Y H:i') {
    $dt = new DateTime($date);
    return $dt->format($format);
}

/**
 * HTML çıktısı güvenli hale getirme
 */
function escape($string) {
    return htmlspecialchars($string, ENT_QUOTES, 'UTF-8');
}