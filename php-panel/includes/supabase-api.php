<?php
/**
 * Supabase API entegrasyonu için yardımcı fonksiyonlar
 */

/**
 * Supabase API isteği gönderir
 * 
 * @param string $endpoint API endpoint'i
 * @param string $method HTTP metodu (GET, POST, PATCH, DELETE)
 * @param array $data İstek gövdesi (JSON olarak gönderilir)
 * @return array|false Yanıt veya hata durumunda false
 */
function supabase_request($endpoint, $method = 'GET', $data = null) {
    $supabase_url = getenv('SUPABASE_URL');
    $supabase_key = getenv('SUPABASE_SERVICE_ROLE_KEY');
    
    if (!$supabase_url || !$supabase_key) {
        error_log("Supabase yapılandırma bilgileri eksik!");
        return false;
    }
    
    // Endpoint'i oluştur
    $url = rtrim($supabase_url, '/') . '/' . ltrim($endpoint, '/');
    
    // cURL isteğini başlat
    $ch = curl_init($url);
    
    // Temel HTTP başlıkları
    $headers = [
        'Content-Type: application/json',
        'apikey: ' . $supabase_key,
        'Authorization: Bearer ' . $supabase_key
    ];
    
    // HTTP metodu ve veri ayarla
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    if ($data !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
    }
    
    // Diğer cURL ayarları
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    
    // SSL doğrulamasını devre dışı bırakma (geliştirme için - üretimde etkinleştirin)
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    
    // İsteği çalıştır
    $response = curl_exec($ch);
    $status_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    
    // Hata kontrolü
    if (curl_errno($ch)) {
        error_log('Supabase API hatası: ' . curl_error($ch));
        curl_close($ch);
        return false;
    }
    
    curl_close($ch);
    
    // Yanıtı JSON olarak ayrıştır
    $result = json_decode($response, true);
    
    // Başarılı bir yanıt mı?
    if ($status_code >= 200 && $status_code < 300) {
        return $result;
    } else {
        $error_message = isset($result['error']) ? $result['error'] : 'Bilinmeyen hata';
        error_log("Supabase API hatası ($status_code): $error_message");
        return false;
    }
}

/**
 * Supabase üzerinden veri tablosu sorgulaması yapar
 * 
 * @param string $table Tablo adı
 * @param array $params Sorgu parametreleri 
 *                      (select, order, limit, offset, filter vb.)
 * @return array|false Veri veya hata durumunda false
 */
function supabase_query($table, $params = []) {
    $endpoint = 'rest/v1/' . $table;
    
    // Query parametrelerini oluştur
    $query_params = [];
    
    // Select alanları
    if (isset($params['select'])) {
        $query_params[] = 'select=' . urlencode($params['select']);
    }
    
    // Sıralama
    if (isset($params['order'])) {
        $query_params[] = 'order=' . urlencode($params['order']);
    }
    
    // Limit
    if (isset($params['limit'])) {
        $query_params[] = 'limit=' . intval($params['limit']);
    }
    
    // Offset
    if (isset($params['offset'])) {
        $query_params[] = 'offset=' . intval($params['offset']);
    }
    
    // Filtreler
    if (isset($params['filters']) && is_array($params['filters'])) {
        foreach ($params['filters'] as $column => $value) {
            $query_params[] = $column . '=eq.' . urlencode($value);
        }
    }
    
    // Query string'i oluştur
    if (!empty($query_params)) {
        $endpoint .= '?' . implode('&', $query_params);
    }
    
    return supabase_request($endpoint, 'GET');
}

/**
 * Supabase'e yeni veri ekler
 * 
 * @param string $table Tablo adı
 * @param array $data Eklenecek veri
 * @param bool $upsert Güncelleme veya ekleme yapılsın mı?
 * @return array|false Yanıt veya hata durumunda false
 */
function supabase_insert($table, $data, $upsert = false) {
    $endpoint = 'rest/v1/' . $table;
    
    if ($upsert) {
        $endpoint .= '?upsert=true';
    }
    
    return supabase_request($endpoint, 'POST', $data);
}

/**
 * Supabase'de veri günceller
 * 
 * @param string $table Tablo adı
 * @param array $data Güncellenecek veri
 * @param array $match Eşleşme kriterleri
 * @return array|false Yanıt veya hata durumunda false
 */
function supabase_update($table, $data, $match) {
    $endpoint = 'rest/v1/' . $table;
    
    // Match kriterleri oluştur
    $match_params = [];
    foreach ($match as $column => $value) {
        $match_params[] = $column . '=eq.' . urlencode($value);
    }
    
    if (!empty($match_params)) {
        $endpoint .= '?' . implode('&', $match_params);
    }
    
    return supabase_request($endpoint, 'PATCH', $data);
}

/**
 * Supabase'de veri siler
 * 
 * @param string $table Tablo adı
 * @param array $match Eşleşme kriterleri
 * @return array|false Yanıt veya hata durumunda false
 */
function supabase_delete($table, $match) {
    $endpoint = 'rest/v1/' . $table;
    
    // Match kriterleri oluştur
    $match_params = [];
    foreach ($match as $column => $value) {
        $match_params[] = $column . '=eq.' . urlencode($value);
    }
    
    if (!empty($match_params)) {
        $endpoint .= '?' . implode('&', $match_params);
    }
    
    return supabase_request($endpoint, 'DELETE');
}

/**
 * Kullanıcılara bildirim gönderir
 * 
 * @param array $notification Bildirim verileri
 * @param array $user_ids Kullanıcı ID'leri dizisi
 * @return bool Başarılı olup olmadığı
 */
function send_notification($notification, $user_ids = []) {
    // Bildirim temel verilerini kontrol et
    if (empty($notification['title']) || empty($notification['content']) || empty($notification['type'])) {
        error_log("Eksik bildirim verileri");
        return false;
    }
    
    // Geçerli bildirim tiplerini kontrol et
    $valid_types = ['like', 'comment', 'reply', 'mention', 'system'];
    if (!in_array($notification['type'], $valid_types)) {
        error_log("Geçersiz bildirim tipi: " . $notification['type']);
        return false;
    }
    
    // Gönderilecek kullanıcılar
    if (empty($user_ids)) {
        // Tüm kullanıcılara gönder
        $users = supabase_query('auth.users', [
            'select' => 'id', 
            'filters' => ['is_admin' => false]
        ]);
        
        if ($users) {
            $user_ids = array_column($users, 'id');
        } else {
            error_log("Kullanıcılar alınamadı");
            return false;
        }
    }
    
    // Her kullanıcı için bildirimleri ekle
    $success_count = 0;
    $total_count = count($user_ids);
    
    foreach ($user_ids as $user_id) {
        $notification_data = [
            'user_id' => $user_id,
            'title' => $notification['title'],
            'content' => $notification['content'],
            'type' => $notification['type'],
            'is_read' => false,
            'created_at' => date('c'), // ISO 8601 formatında şu anki zaman
            'updated_at' => date('c')
        ];
        
        // Opsiyonel alanları ekle
        if (isset($notification['related_entity_id'])) {
            $notification_data['related_entity_id'] = $notification['related_entity_id'];
        }
        if (isset($notification['related_entity_type'])) {
            $notification_data['related_entity_type'] = $notification['related_entity_type'];
        }
        if (isset($notification['sender_id'])) {
            $notification_data['sender_id'] = $notification['sender_id'];
        }
        if (isset($notification['sender_name'])) {
            $notification_data['sender_name'] = $notification['sender_name'];
        }
        if (isset($notification['sender_profile_url'])) {
            $notification_data['sender_profile_url'] = $notification['sender_profile_url'];
        }
        
        $result = supabase_insert('notifications', $notification_data);
        
        if ($result) {
            $success_count++;
        }
    }
    
    // Sonuç raporu
    if ($success_count > 0) {
        return true;
    } else {
        error_log("Bildirim gönderme hatası: Hiçbir bildirim gönderilemedi");
        return false;
    }
}

/**
 * Bildirim tercihlerini getirir
 * 
 * @param int $limit Maksimum kayıt sayısı
 * @return array|false Bildirim tercihleri veya hata durumunda false
 */
function get_notification_preferences($limit = 100) {
    return supabase_query('notification_preferences', [
        'select' => '*',
        'limit' => $limit,
        'order' => 'created_at.desc'
    ]);
}

/**
 * Kullanıcıların bildirim tercihlerini istatistiksel olarak analiz eder
 * 
 * @return array|false İstatistikler veya hata durumunda false
 */
function get_notification_preferences_stats() {
    $preferences = get_notification_preferences(1000); // Yeterince büyük bir limit
    
    if (!$preferences) {
        return false;
    }
    
    $total = count($preferences);
    if ($total === 0) {
        return [
            'total_users' => 0,
            'likes_enabled' => 0,
            'comments_enabled' => 0,
            'replies_enabled' => 0, 
            'mentions_enabled' => 0,
            'system_notifications_enabled' => 0
        ];
    }
    
    $stats = [
        'total_users' => $total,
        'likes_enabled' => 0,
        'comments_enabled' => 0,
        'replies_enabled' => 0,
        'mentions_enabled' => 0,
        'system_notifications_enabled' => 0
    ];
    
    foreach ($preferences as $pref) {
        if ($pref['likes_enabled']) $stats['likes_enabled']++;
        if ($pref['comments_enabled']) $stats['comments_enabled']++;
        if ($pref['replies_enabled']) $stats['replies_enabled']++;
        if ($pref['mentions_enabled']) $stats['mentions_enabled']++;
        if ($pref['system_notifications_enabled']) $stats['system_notifications_enabled']++;
    }
    
    // Yüzdeleri hesapla
    foreach ($stats as $key => $value) {
        if ($key !== 'total_users') {
            $stats[$key . '_percent'] = round(($value / $total) * 100);
        }
    }
    
    return $stats;
}

/**
 * Bildirimleri getirir
 * 
 * @param array $params Sorgu parametreleri
 * @return array|false Bildirimler veya hata durumunda false
 */
function get_notifications($params = []) {
    $default_params = [
        'select' => '*',
        'limit' => 200,
        'order' => 'created_at.desc'
    ];
    
    $query_params = array_merge($default_params, $params);
    
    return supabase_query('notifications', $query_params);
}

/**
 * Bildirim siler
 * 
 * @param string $notification_id Bildirim ID'si
 * @return bool Başarılı olup olmadığı
 */
function delete_notification($notification_id) {
    if (!$notification_id) {
        return false;
    }
    
    $result = supabase_delete('notifications', ['id' => $notification_id]);
    
    return ($result !== false);
}