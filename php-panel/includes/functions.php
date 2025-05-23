<?php
// Supabase API ile iletişim fonksiyonları

/**
 * Tarih formatla
 * 
 * @param string $date ISO 8601 tarih formatı
 * @param string $format Çıktı formatı
 * @return string Formatlanmış tarih
 */
function formatDateStr($date, $format = 'd.m.Y H:i') {
    if (empty($date)) return '-';
    
    $timestamp = strtotime($date);
    return date($format, $timestamp);
}

// formatDate fonksiyonu config.php'de tanımlandığı için buradan kaldırıldı

// isLoggedIn ve isOfficial fonksiyonları config.php'de tanımlandığı için buradan kaldırıldı

// escape fonksiyonu config.php'de tanımlandığı için buradan kaldırıldı

// safeRedirect fonksiyonu yerine config.php'deki redirect fonksiyonu kullanılıyor

/**
 * Supabase'den veri al
 * 
 * @param string $table Tablo adı
 * @param array $params Sorgu parametreleri
 * @return array Veri ve hata bilgisini içeren dizi
 */
function getData($table, $params = []) {
    // API URL oluştur
    $url = SUPABASE_REST_URL . '/' . $table;
    
    // Parametreler varsa URL'ye ekle
    if (!empty($params)) {
        $url .= '?' . http_build_query($params);
    }
    
    try {
        // API isteği yap
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'apikey: ' . SUPABASE_API_KEY,
            'Authorization: ' . SUPABASE_AUTH_HEADER,
            'Content-Type: application/json',
            'Prefer: return=representation'
        ]);
        
        $response = curl_exec($ch);
        $status_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        // API yanıtını kontrol et
        if ($status_code >= 200 && $status_code < 300) {
            $data = json_decode($response, true);
            return ['error' => false, 'data' => $data, 'message' => 'Veriler başarıyla alındı'];
        } else {
            // API hatası, boş veri döndür
            $error_message = "API Hatası: HTTP $status_code";
            error_log($error_message);
            
            return ['error' => true, 'data' => [], 'message' => 'Verilere erişilemedi: ' . $error_message];
        }
    } catch (Exception $e) {
        // İstek hatası, boş veri döndür
        $error_message = "İstek Hatası: " . $e->getMessage();
        error_log($error_message);
        
        return ['error' => true, 'data' => [], 'message' => 'Verilere erişilemedi: ' . $error_message];
    }
}

/**
 * Supabase'e veri ekle
 * 
 * @param string $table Tablo adı
 * @param array $data Eklenecek veri
 * @return array Sonuç ve hata bilgisini içeren dizi
 */
function addData($table, $data) {
    // API URL oluştur
    $url = SUPABASE_REST_URL . '/' . $table;
    
    try {
        // JSON alanlarını kontrol et - image_urls özel olarak işle
        if (isset($data['image_urls'])) {
            // Eğer image_urls boş veya dizi değilse, boş diziyle değiştir
            if (empty($data['image_urls']) || !is_array($data['image_urls'])) {
                $data['image_urls'] = [];
            }
            
            // Boş değerleri filtrele
            $data['image_urls'] = array_values(array_filter($data['image_urls'], function($url) {
                return !empty(trim($url));
            }));
        }
        
        // API isteği yap
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'apikey: ' . SUPABASE_API_KEY,
            'Authorization: ' . SUPABASE_AUTH_HEADER,
            'Content-Type: application/json',
            'Prefer: return=representation'
        ]);
        
        $response = curl_exec($ch);
        $status_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        // API yanıtını kontrol et
        if ($status_code >= 200 && $status_code < 300) {
            $result = json_decode($response, true);
            return ['error' => false, 'data' => $result, 'message' => 'Veri başarıyla eklendi'];
        } else {
            $error = json_decode($response, true);
            $error_message = isset($error['message']) ? $error['message'] : "API Hatası: HTTP $status_code";
            return ['error' => true, 'data' => null, 'message' => $error_message];
        }
    } catch (Exception $e) {
        return ['error' => true, 'data' => null, 'message' => 'İstek Hatası: ' . $e->getMessage()];
    }
}

/**
 * Supabase'deki veriyi güncelle
 * 
 * @param string $table Tablo adı
 * @param string $id Güncellenecek verinin ID'si
 * @param array $data Güncellenecek alanlar
 * @return array Sonuç ve hata bilgisini içeren dizi
 */
function updateData($table, $id, $data) {
    // API URL oluştur
    $url = SUPABASE_REST_URL . '/' . $table . '?id=eq.' . urlencode($id);
    
    try {
        // JSON alanlarını kontrol et - image_urls özel olarak işle
        if (isset($data['image_urls'])) {
            // Eğer image_urls boş veya dizi değilse, boş diziyle değiştir
            if (empty($data['image_urls']) || !is_array($data['image_urls'])) {
                $data['image_urls'] = [];
            }
            
            // Boş değerleri filtrele
            $data['image_urls'] = array_values(array_filter($data['image_urls'], function($url) {
                return !empty(trim($url));
            }));
        }
        
        // API isteği yap
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PATCH');
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'apikey: ' . SUPABASE_API_KEY,
            'Authorization: ' . SUPABASE_AUTH_HEADER,
            'Content-Type: application/json',
            'Prefer: return=representation'
        ]);
        
        $response = curl_exec($ch);
        $status_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        // API yanıtını kontrol et
        if ($status_code >= 200 && $status_code < 300) {
            $result = json_decode($response, true);
            return ['error' => false, 'data' => $result, 'message' => 'Veri başarıyla güncellendi'];
        } else {
            $error = json_decode($response, true);
            $error_message = isset($error['message']) ? $error['message'] : "API Hatası: HTTP $status_code";
            return ['error' => true, 'data' => null, 'message' => $error_message];
        }
    } catch (Exception $e) {
        return ['error' => true, 'data' => null, 'message' => 'İstek Hatası: ' . $e->getMessage()];
    }
}

/**
 * Supabase'den veri sil
 * 
 * @param string $table Tablo adı
 * @param string $id Silinecek verinin ID'si
 * @return array Sonuç ve hata bilgisini içeren dizi
 */
function deleteData($table, $id) {
    // API URL oluştur
    $url = SUPABASE_REST_URL . '/' . $table . '?id=eq.' . urlencode($id);
    
    try {
        // API isteği yap
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'apikey: ' . SUPABASE_API_KEY,
            'Authorization: ' . SUPABASE_AUTH_HEADER,
            'Content-Type: application/json'
        ]);
        
        $response = curl_exec($ch);
        $status_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        // API yanıtını kontrol et
        if ($status_code >= 200 && $status_code < 300) {
            return ['error' => false, 'message' => 'Veri başarıyla silindi'];
        } else {
            $error = json_decode($response, true);
            $error_message = isset($error['message']) ? $error['message'] : "API Hatası: HTTP $status_code";
            return ['error' => true, 'message' => $error_message];
        }
    } catch (Exception $e) {
        return ['error' => true, 'message' => 'İstek Hatası: ' . $e->getMessage()];
    }
}

/**
 * ID'ye göre veriyi al
 * 
 * @param string $table Tablo adı
 * @param string $id Veri ID'si
 * @return array Veri ve hata bilgisini içeren dizi
 */
function getDataById($table, $id) {
    $result = getData($table, ['id' => 'eq.' . $id]);
    
    if (!$result['error'] && !empty($result['data'])) {
        return ['error' => false, 'data' => $result['data'][0], 'message' => 'Veri başarıyla alındı'];
    }
    
    return ['error' => true, 'data' => null, 'message' => 'Veri bulunamadı'];
}

/**
 * Supabase'e veri ekle (insertData) - addData ile aynı, alias olarak tanımlandı
 * 
 * @param string $table Tablo adı
 * @param array $data Eklenecek veri
 * @return array Sonuç ve hata bilgisini içeren dizi
 */
function insertData($table, $data) {
    return addData($table, $data);
}

/**
 * ID listesine göre veri filtrele
 * 
 * @param array $data Tüm veri dizisi
 * @param string $idField ID alanı adı
 * @param array $idList Filtrelenecek ID listesi
 * @return array Filtrelenmiş veri dizisi
 */
function filterDataByIds($data, $idField, $idList) {
    return array_filter($data, function($item) use ($idField, $idList) {
        return isset($item[$idField]) && in_array($item[$idField], $idList);
    });
}

/**
 * Political party ID'sine göre parti bilgilerini al
 * 
 * @param int $political_party_id Parti ID'si
 * @return array|null Parti bilgileri veya bulunamazsa null
 */
function getPartyInfoById($political_party_id) {
    if (empty($political_party_id)) {
        return null;
    }
    
    $party_result = getDataById('political_parties', $political_party_id);
    return $party_result;
}

/**
 * Ham SQL sorgusu çalıştır
 * 
 * @param string $sql_query SQL sorgusu
 * @return array Sonuç ve hata bilgisini içeren dizi
 */
function executeRawSql($sql_query) {
    // API URL oluştur
    $url = SUPABASE_REST_URL . '/rpc/execute_sql';
    
    // Sorgu parametreleri
    $data = [
        'query' => $sql_query
    ];
    
    try {
        // API isteği yap
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'apikey: ' . SUPABASE_API_KEY,
            'Authorization: ' . SUPABASE_AUTH_HEADER,
            'Content-Type: application/json',
            'Prefer: return=representation'
        ]);
        
        $response = curl_exec($ch);
        $status_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curl_error = curl_error($ch);
        curl_close($ch);
        
        // Cevabı değerlendir
        if ($curl_error) {
            return [
                'error' => true,
                'error_message' => 'CURL Hatası: ' . $curl_error
            ];
        }
        
        if ($status_code >= 400) {
            return [
                'error' => true,
                'error_message' => 'API Hatası (' . $status_code . '): ' . $response
            ];
        }
        
        // Başarılı sonuç
        return [
            'error' => false,
            'data' => json_decode($response, true)
        ];
        
    } catch (Exception $e) {
        return [
            'error' => true,
            'error_message' => 'Hata: ' . $e->getMessage()
        ];
    }
}

/**
 * Dashboard için özet istatistikleri al
 * 
 * @return array İstatistikler
 */
function getDashboardStats() {
    $cities_result = getData('cities');
    $cities = $cities_result['data'];
    
    $users_result = getData('users');
    $users = $users_result['data'];
    
    $posts_result = getData('posts');
    $posts = $posts_result['data'];
    
    // Bekleyen şikayetleri say
    $pending_complaints = 0;
    foreach ($posts as $post) {
        if (isset($post['type']) && $post['type'] === 'complaint' && 
            (!isset($post['is_resolved']) || $post['is_resolved'] === 'false')) {
            $pending_complaints++;
        }
    }
    
    // Aktif kullanıcı: son 30 gün içinde etkileşimde bulunanlar
    $active_users = 0;
    $thirty_days_ago = time() - (30 * 24 * 60 * 60);
    foreach ($users as $user) {
        if (isset($user['created_at']) && strtotime($user['created_at']) > $thirty_days_ago) {
            $active_users++;
        }
    }
    
    return [
        'total_cities' => count($cities),
        'active_users' => $active_users,
        'total_posts' => count($posts),
        'pending_complaints' => $pending_complaints
    ];
}

/**
 * Son aktiviteleri al
 * 
 * @param int $limit Kaç aktivite alınacak
 * @return array Aktiviteler listesi
 */
function getRecentActivities($limit = 10) {
    $posts_result = getData('posts', ['order' => 'created_at.desc', 'limit' => $limit]);
    $posts = $posts_result['data'];
    
    $comments_result = getData('comments', ['order' => 'created_at.desc', 'limit' => $limit]);
    $comments = $comments_result['data'];
    
    $users_result = getData('users');
    $users = $users_result['data'];
    
    $activities = [];
    
    // Gönderileri aktivitelere ekle
    foreach ($posts as $post) {
        if (isset($post['created_at'])) {
            $user_name = 'Bilinmeyen Kullanıcı';
            $user_avatar = '';
            
            // Kullanıcı bilgilerini bul
            if (isset($post['user_id'])) {
                foreach ($users as $user) {
                    if ($user['id'] === $post['user_id']) {
                        $user_name = $user['username'];
                        $user_avatar = $user['profile_image_url'] ?? '';
                        break;
                    }
                }
            }
            
            $post_type = 'gönderi';
            if (isset($post['type'])) {
                switch ($post['type']) {
                    case 'complaint': $post_type = 'şikayet'; break;
                    case 'suggestion': $post_type = 'öneri'; break;
                    case 'question': $post_type = 'soru'; break;
                    case 'thanks': $post_type = 'teşekkür'; break;
                }
            }
            
            $activities[] = [
                'id' => $post['id'],
                'userId' => $post['user_id'] ?? '',
                'username' => $user_name,
                'userAvatar' => $user_avatar,
                'action' => $post_type . ' paylaştı',
                'target' => $post['title'] ?? 'Başlıksız',
                'timestamp' => $post['created_at'],
                'type' => 'post'
            ];
        }
    }
    
    // Yorumları aktivitelere ekle
    foreach ($comments as $comment) {
        if (isset($comment['created_at'])) {
            $user_name = 'Bilinmeyen Kullanıcı';
            $user_avatar = '';
            
            // Kullanıcı bilgilerini bul
            if (isset($comment['user_id'])) {
                foreach ($users as $user) {
                    if ($user['id'] === $comment['user_id']) {
                        $user_name = $user['username'];
                        $user_avatar = $user['profile_image_url'] ?? '';
                        break;
                    }
                }
            }
            
            // Gönderi başlığını bul
            $post_title = 'Bilinmeyen Gönderi';
            foreach ($posts as $post) {
                if ($post['id'] === $comment['post_id']) {
                    $post_title = $post['title'] ?? 'Başlıksız';
                    break;
                }
            }
            
            $activities[] = [
                'id' => $comment['id'],
                'userId' => $comment['user_id'] ?? '',
                'username' => $user_name,
                'userAvatar' => $user_avatar,
                'action' => 'yorum yaptı',
                'target' => $post_title,
                'timestamp' => $comment['created_at'],
                'type' => 'comment'
            ];
        }
    }
    
    // Tarihe göre sırala (en yeni en üstte)
    usort($activities, function($a, $b) {
        return strtotime($b['timestamp']) - strtotime($a['timestamp']);
    });
    
    // Limiti uygula
    return array_slice($activities, 0, $limit);
}

/**
 * Gönderi kategorilerinin dağılımını al
 * 
 * @return array Kategori dağılımı
 */
function getPostCategoriesDistribution() {
    $posts_result = getData('posts');
    $posts = $posts_result['data'];
    
    $categories = [
        'complaint' => ['count' => 0, 'name' => 'Şikayet', 'color' => '#dc3545', 'icon' => 'fa-exclamation-circle'],
        'suggestion' => ['count' => 0, 'name' => 'Öneri', 'color' => '#0d6efd', 'icon' => 'fa-lightbulb'],
        'question' => ['count' => 0, 'name' => 'Soru', 'color' => '#ffc107', 'icon' => 'fa-question-circle'],
        'thanks' => ['count' => 0, 'name' => 'Teşekkür', 'color' => '#198754', 'icon' => 'fa-heart']
    ];
    
    $total = 0;
    
    // Kategori sayılarını hesapla
    foreach ($posts as $post) {
        if (isset($post['type']) && isset($categories[$post['type']])) {
            $categories[$post['type']]['count']++;
            $total++;
        }
    }
    
    // Yüzdeleri hesapla
    if ($total > 0) {
        foreach ($categories as $key => $category) {
            $categories[$key]['percentage'] = round(($category['count'] / $total) * 100, 1);
        }
    }
    
    return array_values($categories);
}

/**
 * Siyasi parti dağılımını al
 * 
 * @return array Parti dağılımı
 */
function getPoliticalPartyDistribution() {
    $cities_result = getData('cities');
    $cities = $cities_result['data'];
    
    $parties_result = getData('political_parties');
    $parties = $parties_result['data'];
    
    $distribution = [];
    $total = 0;
    
    // Parti adlarına göre dağılımı hesapla
    foreach ($cities as $city) {
        if (isset($city['mayor_party']) && !empty($city['mayor_party'])) {
            $party_name = $city['mayor_party'];
            
            if (!isset($distribution[$party_name])) {
                // Parti logosunu ve rengini bul
                $logo = '';
                $color = '#aaa';
                
                foreach ($parties as $party) {
                    if ($party['name'] === $party_name) {
                        $logo = $party['logo_url'] ?? '';
                        $color = $party['color'] ?? '';
                        break;
                    }
                }
                
                // Renk tanımlanmamışsa rastgele renk ata
                if (empty($color)) {
                    $colors = ['#0d6efd', '#6610f2', '#6f42c1', '#d63384', '#dc3545', '#fd7e14', '#ffc107', '#198754', '#20c997', '#0dcaf0'];
                    $color = $colors[array_rand($colors)];
                }
                
                $distribution[$party_name] = [
                    'name' => $party_name,
                    'count' => 0,
                    'logo' => $logo,
                    'color' => $color
                ];
            }
            
            $distribution[$party_name]['count']++;
            $total++;
        }
    }
    
    // Yüzdeleri hesapla
    if ($total > 0) {
        foreach ($distribution as $key => $party) {
            $distribution[$key]['percentage'] = round(($party['count'] / $total) * 100, 1);
        }
    }
    
    // Count değerine göre azalan sıralama yap
    usort($distribution, function($a, $b) {
        return $b['count'] - $a['count'];
    });
    
    return array_values($distribution);
}

/**
 * Breadcrumb navigasyonu oluştur
 * 
 * @param array $items Navigasyon öğeleri [['title' => 'Ana Sayfa', 'url' => 'index.php'], ...]
 * @return string HTML breadcrumb 
 */
function generateBreadcrumb($items) {
    $html = '<nav aria-label="breadcrumb"><ol class="breadcrumb">';
    
    $count = count($items);
    foreach ($items as $index => $item) {
        $isLast = $index === $count - 1;
        
        if ($isLast) {
            $html .= '<li class="breadcrumb-item active" aria-current="page">' . escape($item['title']) . '</li>';
        } else {
            $html .= '<li class="breadcrumb-item"><a href="' . escape($item['url']) . '">' . escape($item['title']) . '</a></li>';
        }
    }
    
    $html .= '</ol></nav>';
    return $html;
}

/**
 * Ana menü öğelerini oluştur
 * 
 * @param string $active_page Aktif sayfa
 * @return array Menü öğeleri
 */
function getMainMenuItems($active_page = '') {
    return [
        [
            'id' => 'dashboard',
            'title' => 'Dashboard',
            'url' => 'index.php?page=dashboard',
            'icon' => 'fas fa-tachometer-alt',
            'active' => $active_page === 'dashboard'
        ],
        [
            'id' => 'cities',
            'title' => 'Şehirler',
            'url' => 'index.php?page=cities',
            'icon' => 'fas fa-city',
            'active' => $active_page === 'cities'
        ],
        [
            'id' => 'districts',
            'title' => 'İlçeler',
            'url' => 'index.php?page=districts',
            'icon' => 'fas fa-map-marker-alt',
            'active' => $active_page === 'districts'
        ],
        [
            'id' => 'parties',
            'title' => 'Siyasi Partiler',
            'url' => 'index.php?page=parties',
            'icon' => 'fas fa-flag',
            'active' => $active_page === 'parties'
        ],
        [
            'id' => 'posts',
            'title' => 'Gönderiler',
            'url' => 'index.php?page=posts',
            'icon' => 'fas fa-newspaper',
            'active' => $active_page === 'posts'
        ],
        [
            'id' => 'comments',
            'title' => 'Yorumlar',
            'url' => 'index.php?page=comments',
            'icon' => 'fas fa-comments',
            'active' => $active_page === 'comments'
        ],
        [
            'id' => 'announcements',
            'title' => 'Duyurular',
            'url' => 'index.php?page=announcements',
            'icon' => 'fas fa-bullhorn',
            'active' => $active_page === 'announcements'
        ],
        [
            'id' => 'users',
            'title' => 'Kullanıcılar',
            'url' => 'index.php?page=users',
            'icon' => 'fas fa-users',
            'active' => $active_page === 'users'
        ]
    ];
}

/**
 * Sayfa başlığı oluştur
 * 
 * @param string $page_id Sayfa kimliği
 * @return string Sayfa başlığı
 */
function getPageTitle($page_id) {
    $titles = [
        'dashboard' => 'Dashboard',
        'cities' => 'Şehirler Yönetimi',
        'districts' => 'İlçeler Yönetimi',
        'parties' => 'Siyasi Partiler Yönetimi',
        'posts' => 'Gönderiler Yönetimi',
        'comments' => 'Yorumlar Yönetimi',
        'announcements' => 'Duyurular Yönetimi',
        'users' => 'Kullanıcılar Yönetimi',
        'login' => 'Giriş Yap',
        'error' => 'Hata',
        'not_found' => 'Sayfa Bulunamadı'
    ];
    
    return isset($titles[$page_id]) ? $titles[$page_id] . ' - ' . SITE_TITLE : SITE_TITLE;
}

/**
 * Rastgele UUID oluştur
 * 
 * @return string UUID
 */
function generateUUID() {
    return sprintf(
        '%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
        mt_rand(0, 0xffff), mt_rand(0, 0xffff),
        mt_rand(0, 0xffff),
        mt_rand(0, 0x0fff) | 0x4000,
        mt_rand(0, 0x3fff) | 0x8000,
        mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
    );
}

/**
 * Güvenli yönlendirme yapar, headers already sent hatası olmadan
 * 
 * @param string $url Yönlendirilecek URL
 * @return void
 */
function safeRedirect($url) {
    if (!headers_sent()) {
        header('Location: ' . $url);
        exit;
    } else {
        echo '<script>window.location.href = "' . $url . '";</script>';
        exit;
    }
}

/**
 * Dosya yükle
 * 
 * @param array $file $_FILES dizisi içindeki dosya
 * @param string $target_dir Hedef dizin
 * @param array $allowed_types İzin verilen dosya tipleri
 * @param int $max_size Maksimum dosya boyutu (byte)
 * @return array Başarı durumu ve mesaj içeren dizi
 */
function uploadImage($file, $target_dir, $allowed_types = ['image/jpeg', 'image/png', 'image/gif', 'video/mp4', 'video/webm'], $max_size = 5242880) {
    // Dosya kontrolü
    if (!isset($file['tmp_name']) || empty($file['tmp_name'])) {
        return ['success' => false, 'message' => 'Dosya yüklenemedi'];
    }
    
    // Hata kontrolü
    if ($file['error'] !== UPLOAD_ERR_OK) {
        $error_messages = [
            UPLOAD_ERR_INI_SIZE => 'Dosya boyutu PHP ayarlarında izin verilen maksimum boyutu aşıyor',
            UPLOAD_ERR_FORM_SIZE => 'Dosya boyutu formda belirtilen maksimum boyutu aşıyor',
            UPLOAD_ERR_PARTIAL => 'Dosya sadece kısmen yüklendi',
            UPLOAD_ERR_NO_FILE => 'Dosya yüklenmedi',
            UPLOAD_ERR_NO_TMP_DIR => 'Geçici klasör bulunamadı',
            UPLOAD_ERR_CANT_WRITE => 'Dosya diske yazılamadı',
            UPLOAD_ERR_EXTENSION => 'Bir PHP uzantısı dosya yüklemesini durdurdu'
        ];
        
        $error_message = isset($error_messages[$file['error']]) 
            ? $error_messages[$file['error']] 
            : 'Bilinmeyen hata: ' . $file['error'];
        
        return ['success' => false, 'message' => $error_message];
    }
    
    // Dosya boyutu kontrolü
    if ($file['size'] > $max_size) {
        return ['success' => false, 'message' => 'Dosya boyutu çok büyük (maksimum 5MB)'];
    }
    
    // Dosya tipi kontrolü
    $file_type = $file['type'];
    if (!in_array($file_type, $allowed_types)) {
        return ['success' => false, 'message' => 'Geçersiz dosya tipi. İzin verilen tipler: İzin verilen formatlar: JPG, PNG, GIF'];
    }
    
    // Dosya uzantısını belirle
    $extension = '';
    switch ($file_type) {
        case 'image/jpeg':
            $extension = 'jpg';
            break;
        case 'image/png':
            $extension = 'png';
            break;
        case 'image/gif':
            $extension = 'gif';
            break;
        case 'video/mp4':
            $extension = 'mp4';
            break;
        case 'video/webm':
            $extension = 'webm';
            break;
        default:
            // Bilinmeyen dosya tipi için dosya adından uzantıyı al
            $file_info = pathinfo($file['name']);
            $extension = strtolower($file_info['extension'] ?? '');
            
            // Uzantı yoksa veya boşsa hata döndür
            if (empty($extension)) {
                return ['success' => false, 'message' => 'Dosya türü tanımlanamadı'];
            }
            break;
    }
    
    // Hedef dizini kontrol et ve oluştur
    if (!is_dir($target_dir) && !mkdir($target_dir, 0777, true)) {
        return ['success' => false, 'message' => 'Yükleme dizini oluşturulamadı'];
    }
    
    // Benzersiz dosya adı oluştur
    $file_name = uniqid() . '_' . time() . '.' . $extension;
    $target_path = $target_dir . '/' . $file_name;
    
    // Dosyayı yükle
    if (!move_uploaded_file($file['tmp_name'], $target_path)) {
        return ['success' => false, 'message' => 'Dosya yüklenirken bir hata oluştu'];
    }
    
    // Hedef dizin adını çıkar (son klasör adı)
    $dir_parts = explode('/', $target_dir);
    $last_dir = end($dir_parts);
    
    // Tam bağlantı URL'i oluştur
    $base_url = 'https://onvao.net/adminpanel';
    $full_url = $base_url . '/uploads/' . $last_dir . '/' . $file_name;
    
    // Başarılı sonucu döndür
    return [
        'success' => true,
        'message' => 'Dosya başarıyla yüklendi',
        'file_name' => $file_name,
        'file_path' => $target_path,
        'file_url' => $full_url
    ];
}
?>