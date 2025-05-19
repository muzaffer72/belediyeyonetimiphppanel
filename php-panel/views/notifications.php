<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/supabase-api.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn()) {
    redirect('index.php?page=login');
}

// Action kontrolü (düzenleme, silme vb)
$action = isset($_GET['action']) ? $_GET['action'] : '';
$notification_id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
$success_message = '';
$error_message = '';

// Toplu bildirim gönderme işlemi
if (isset($_POST['submit_bulk_notification'])) {
    $title = $_POST['title'] ?? '';
    $message = $_POST['message'] ?? '';
    $link = $_POST['link'] ?? '';
    $type = $_POST['type'] ?? 'system';
    $target_type = $_POST['target_type'] ?? 'all';
    $city_id = isset($_POST['city_id']) && $_POST['city_id'] != '' ? $_POST['city_id'] : null;
    $district_id = isset($_POST['district_id']) && $_POST['district_id'] != '' ? $_POST['district_id'] : null;
    
    error_log("FORM BİLGİLERİ - Başlık: $title, Mesaj: $message, Tip: $type, Hedef: $target_type, Şehir ID: " . ($city_id ?? 'boş') . ", İlçe ID: " . ($district_id ?? 'boş'));
    
    try {
        // Hedeflenen kullanıcıları belirle
        $users = [];
        
        if ($target_type == 'city' && $city_id) {
            $users = [];
            // Tüm kullanıcıları alıp şehir filtresini PHP'de yapalım
            $all_users_result = getData('users', [
                'select' => '*'
            ]);
            
            error_log("Şehir hedefi seçildi, ID:" . $city_id);
            
            if (!$all_users_result['error'] && !empty($all_users_result['data'])) {
                $all_users = $all_users_result['data'];
                error_log("Toplam " . count($all_users) . " kullanıcı bulundu, şehir filtreleniyor...");
                
                // Önce şehir adını bulalım
                $city_name = null;
                
                // city_id bir sayı mı yoksa metin mi kontrol edelim
                if (is_numeric($city_id)) {
                    $city_result = getData('cities', [
                        'select' => 'name',
                        'id' => 'eq.' . $city_id
                    ]);
                    
                    if (!$city_result['error'] && !empty($city_result['data'])) {
                        $city_name = $city_result['data'][0]['name'] ?? null;
                        error_log("Şehir ID'sine göre şehir adı bulundu: " . ($city_name ?? 'bulunamadı'));
                    }
                } else {
                    // city_id doğrudan şehir adı olabilir
                    $city_name = $city_id;
                    error_log("Şehir adı doğrudan alındı: " . $city_name);
                }
                
                // Şehre göre kullanıcıları filtrele
                foreach ($all_users as $user) {
                    $user_city = $user['city'] ?? '';
                    
                    // Şehir adı veya ID eşleşmesini kontrol et
                    if (($city_name && strcasecmp($user_city, $city_name) === 0) || 
                        ($user['city_id'] ?? '') == $city_id) {
                        $users[] = $user['id'];
                        error_log("Kullanıcı şehre uygun: " . $user['email'] . " - Şehir: " . $user_city);
                    }
                }
                
                error_log("Şehir filtrelemesinden sonra kalan kullanıcı sayısı: " . count($users));
            } else {
                error_log("Kullanıcılar alınırken hata oluştu: " . ($all_users_result['message'] ?? 'Bilinmeyen hata'));
            }
            
        } elseif ($target_type == 'district' && $district_id) {
            $users = [];
            // Tüm kullanıcıları alıp ilçe filtresini PHP'de yapalım
            $all_users_result = getData('users', [
                'select' => '*'
            ]);
            
            error_log("İlçe hedefi seçildi, ID:" . $district_id);
            
            if (!$all_users_result['error'] && !empty($all_users_result['data'])) {
                $all_users = $all_users_result['data'];
                error_log("Toplam " . count($all_users) . " kullanıcı bulundu, ilçe filtreleniyor...");
                
                // Önce ilçe adını bulalım
                $district_name = null;
                
                // district_id bir sayı mı yoksa metin mi kontrol edelim
                if (is_numeric($district_id)) {
                    $district_result = getData('districts', [
                        'select' => 'name',
                        'id' => 'eq.' . $district_id
                    ]);
                    
                    if (!$district_result['error'] && !empty($district_result['data'])) {
                        $district_name = $district_result['data'][0]['name'] ?? null;
                        error_log("İlçe ID'sine göre ilçe adı bulundu: " . ($district_name ?? 'bulunamadı'));
                    }
                } else {
                    // district_id doğrudan ilçe adı olabilir
                    $district_name = $district_id;
                    error_log("İlçe adı doğrudan alındı: " . $district_name);
                }
                
                // İlçeye göre kullanıcıları filtrele
                foreach ($all_users as $user) {
                    $user_district = $user['district'] ?? '';
                    
                    // İlçe adı veya ID eşleşmesini kontrol et
                    if (($district_name && strcasecmp($user_district, $district_name) === 0) || 
                        ($user['district_id'] ?? '') == $district_id) {
                        $users[] = $user['id'];
                        error_log("Kullanıcı ilçeye uygun: " . $user['email'] . " - İlçe: " . $user_district);
                    }
                }
                
                error_log("İlçe filtrelemesinden sonra kalan kullanıcı sayısı: " . count($users));
            } else {
                error_log("Kullanıcılar alınırken hata oluştu: " . ($all_users_result['message'] ?? 'Bilinmeyen hata'));
            }
        } else {
            // Notification preferences tablosundan kullanıcıları al
            $users_result = getData('notification_preferences', [
                'select' => 'user_id'
            ]);
            
            if (!$users_result['error'] && !empty($users_result['data'])) {
                $users = array_column($users_result['data'], 'user_id');
                error_log("Notification preferences tablosundan " . count($users) . " kullanıcı bulundu.");
            } else {
                error_log("Notification preferences tablosundan kullanıcılar alınamadı: " . ($users_result['message'] ?? 'Bilinmeyen hata'));
                
                // Kullanıcı bulunamadıysa, users tablosundan deneyelim
                $users_alternate = getData('users', [
                    'select' => 'id'
                ]);
                
                if (!$users_alternate['error'] && !empty($users_alternate['data'])) {
                    $users = array_column($users_alternate['data'], 'id');
                    error_log("Users tablosundan " . count($users) . " kullanıcı bulundu.");
                } else {
                    // Sabit kullanıcı listesi
                    $users = [
                        '2372d46c-da91-4c5d-a4de-7eab455932ab',
                        'f4191657-a714-4ddc-a6fa-c5e54d4c1f7a',
                        '8cf8d436-82cd-4160-8394-ba29323cd2b2',
                        '83190944-98d5-41be-ac3a-178676faf017',
                        'b5008bcd-3119-4789-8568-9da762fa4341'
                    ];
                    error_log("Sabit kullanıcı listesi kullanılıyor: " . count($users) . " kullanıcı");
                }
            }
        }
        
        if (empty($users)) {
            $error_message = "Hedeflenen kullanıcı bulunamadı.";
        } else {
            $success_count = 0;
            $error_count = 0;
            
            // Bildirim tercihleri olan kullanıcıları kontrol et
            $prefs_result = getData('notification_preferences', [
                'select' => '*'
            ]);
            
            $preferences = [];
            if (!$prefs_result['error'] && !empty($prefs_result['data'])) {
                foreach ($prefs_result['data'] as $pref) {
                    if (isset($pref['user_id'])) {
                        $preferences[$pref['user_id']] = $pref;
                    }
                }
                error_log("Bildirim tercihleri alındı: " . count($preferences) . " kullanıcı için");
            }
            
            // Her kullanıcıya bildirim gönder - tercihlerine göre
            foreach ($users as $user_id) {
                // Kullanıcının tercihlerine göre bildirim gönderme kontrolü
                $should_send = true;
                
                if (isset($preferences[$user_id])) {
                    $pref = $preferences[$user_id];
                    
                    // Bildirim tipine göre kullanıcı tercihini kontrol et
                    switch ($type) {
                        case 'like':
                            $should_send = ($pref['likes_enabled'] ?? true);
                            break;
                        case 'comment':
                            $should_send = ($pref['comments_enabled'] ?? true);
                            break;
                        case 'reply':
                            $should_send = ($pref['replies_enabled'] ?? true);
                            break;
                        case 'mention':
                            $should_send = ($pref['mentions_enabled'] ?? true);
                            break;
                        case 'system':
                            $should_send = ($pref['system_notifications_enabled'] ?? true);
                            break;
                    }
                    
                    error_log("Kullanıcı ID: $user_id, Bildirim tipi: $type, Gönderilecek mi: " . ($should_send ? 'Evet' : 'Hayır'));
                }
                
                // Kullanıcı bu bildirim tipini almayı tercih etmişse gönder
                if ($should_send) {
                    $notification_data = [
                        'user_id' => $user_id,
                        'title' => $title,
                        'content' => $message,
                        'type' => $type,
                        'is_read' => false,
                        'related_entity_id' => $link,
                        'related_entity_type' => 'link',
                        'created_at' => date('c'),
                        'updated_at' => date('c')
                    ];
                    
                    $result = addData('notifications', $notification_data);
                    
                    if (!$result['error']) {
                        $success_count++;
                    } else {
                        $error_count++;
                        error_log("Bildirim gönderme hatası: " . ($result['message'] ?? 'Bilinmeyen hata'));
                    }
                } else {
                    error_log("Kullanıcı $user_id için bildirim tercihi kapalı olduğundan gönderilmedi");
                }
            }
            
            if ($success_count > 0) {
                $success_message = "$success_count kullanıcıya bildirim başarıyla gönderildi.";
                if ($error_count > 0) {
                    $success_message .= " ($error_count bildirim gönderilemedi)";
                }
            } else {
                $error_message = "Bildirim gönderme hatası: Hiçbir bildirim gönderilemedi.";
            }
        }
    } catch (Exception $e) {
        $error_message = "Hata: " . $e->getMessage();
    }
}

// Silme işlemi
if ($action == 'delete' && $notification_id > 0) {
    try {
        $result = deleteData('notifications', ['id' => 'eq.' . $notification_id]);
        
        if (!$result['error']) {
            $success_message = "Bildirim başarıyla silindi!";
        } else {
            $error_message = "Bildirim silinirken hata oluştu: " . $result['message'];
        }
    } catch (Exception $e) {
        $error_message = "Hata: " . $e->getMessage();
    }
}

// Bildirim listesini al
try {
    // Bildirimleri al
    $notifications_result = getData('notifications', [
        'select' => '*',
        'order' => 'created_at.desc',
        'limit' => '200'
    ]);
    
    $notifications = $notifications_result['error'] ? [] : $notifications_result['data'];
    
    // Kullanıcı e-postalarını birleştir
    if (!empty($notifications)) {
        $user_ids = array_column($notifications, 'user_id');
        $user_emails = [];
        $user_cities = [];
        $user_districts = [];
        
        // Benzersiz kullanıcı ID'lerini al
        $unique_user_ids = array_unique($user_ids);
        
        // Önce users tablosundan kullanıcı bilgilerini almayı dene
        $users_result = getData('users', [
            'select' => '*'
        ]);
        
        if (!$users_result['error'] && !empty($users_result['data'])) {
            foreach ($users_result['data'] as $user) {
                if (isset($user['id'])) {
                    $user_emails[$user['id']] = $user['email'] ?? 'Bilinmiyor';
                    $user_cities[$user['id']] = $user['city'] ?? 'Bilinmiyor';
                    $user_districts[$user['id']] = $user['district'] ?? 'Bilinmiyor';
                }
            }
            error_log("Users tablosundan " . count($users_result['data']) . " kullanıcı bilgisi alındı.");
        } else {
            // Users tablosundan alınamazsa notification_preferences'den deneyelim
            $users_pref_result = getData('notification_preferences', [
                'select' => 'user_id'
            ]);
            
            if (!$users_pref_result['error'] && !empty($users_pref_result['data'])) {
                foreach ($users_pref_result['data'] as $pref) {
                    $user_emails[$pref['user_id']] = "Kullanıcı #" . substr($pref['user_id'], 0, 8);
                }
                error_log("Notification preferences tablosundan " . count($users_pref_result['data']) . " kullanıcı bilgisi alındı.");
            } else {
                error_log("Kullanıcı bilgileri alınamadı: " . ($users_result['message'] ?? 'Bilinmeyen hata'));
            }
        }
        
        // E-postaları ve diğer bilgileri bildirim verilerine ekle
        foreach ($notifications as &$notification) {
            $uid = $notification['user_id'];
            $notification['user_email'] = $user_emails[$uid] ?? 'Bilinmiyor';
            $notification['user_city'] = $user_cities[$uid] ?? '';
            $notification['user_district'] = $user_districts[$uid] ?? '';
        }
    }
} catch (Exception $e) {
    $error_message = "Hata: " . $e->getMessage();
    $notifications = [];
}

// Şehir ve ilçe verilerini functions.php içindeki getData() fonksiyonu ile al
// Şehirleri al
$cities_result = getData('cities', ['select' => 'id,name', 'order' => 'name']);
$cities = $cities_result['error'] ? [] : $cities_result['data'];

// İlçeleri al
$districts_result = getData('districts', ['select' => 'id,name,city_id', 'order' => 'name']);
$districts = $districts_result['error'] ? [] : $districts_result['data'];

// Uyarı ve bilgilendirme mesajları
if (!empty($success_message)) {
    echo '<div class="alert alert-success">' . $success_message . '</div>';
}
if (!empty($error_message)) {
    echo '<div class="alert alert-danger">' . $error_message . '</div>';
}
?>

<!-- Bildirim Yönetimi -->
<div class="card mb-4">
    <div class="card-header">
        <h5 class="card-title mb-0">
            <i class="fas fa-bell me-2"></i> Bildirim Yönetimi
        </h5>
    </div>
    <div class="card-body">
        <ul class="nav nav-tabs" id="myTab" role="tablist">
            <li class="nav-item" role="presentation">
                <button class="nav-link active" id="notification-list-tab" data-bs-toggle="tab" data-bs-target="#notification-list" type="button" role="tab" aria-controls="notification-list" aria-selected="true">Bildirim Listesi</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="bulk-notification-tab" data-bs-toggle="tab" data-bs-target="#bulk-notification" type="button" role="tab" aria-controls="bulk-notification" aria-selected="false">Toplu Bildirim Gönder</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="notification-preferences-tab" data-bs-toggle="tab" data-bs-target="#notification-preferences" type="button" role="tab" aria-controls="notification-preferences" aria-selected="false">Bildirim Tercihleri</button>
            </li>
        </ul>
        
        <div class="tab-content" id="myTabContent">
            <!-- Bildirim Listesi -->
            <div class="tab-pane fade show active" id="notification-list" role="tabpanel" aria-labelledby="notification-list-tab">
                <div class="table-responsive mt-3">
                    <table class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Kullanıcı</th>
                                <th>Başlık</th>
                                <th>İçerik</th>
                                <th>Tip</th>
                                <th>Okunma Durumu</th>
                                <th>Oluşturma Tarihi</th>
                                <th>İşlemler</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (empty($notifications)): ?>
                                <tr>
                                    <td colspan="8" class="text-center">Bildirim bulunamadı.</td>
                                </tr>
                            <?php else: ?>
                                <?php foreach ($notifications as $notification): ?>
                                    <tr>
                                        <td><?php echo htmlspecialchars($notification['id']); ?></td>
                                        <td>
                                            <?php 
                                            if (isset($notification['user_email'])) {
                                                echo htmlspecialchars($notification['user_email']);
                                                
                                                // Şehir ve ilçe bilgisi varsa göster
                                                if (!empty($notification['user_city']) || !empty($notification['user_district'])) {
                                                    echo '<br><small class="text-muted">';
                                                    
                                                    if (!empty($notification['user_city'])) {
                                                        echo htmlspecialchars($notification['user_city']);
                                                    }
                                                    
                                                    if (!empty($notification['user_city']) && !empty($notification['user_district'])) {
                                                        echo ' / ';
                                                    }
                                                    
                                                    if (!empty($notification['user_district'])) {
                                                        echo htmlspecialchars($notification['user_district']);
                                                    }
                                                    
                                                    echo '</small>';
                                                }
                                            } else {
                                                echo '<span class="text-muted">Bilinmiyor</span>';
                                            }
                                            ?>
                                        </td>
                                        <td><?php echo htmlspecialchars($notification['title']); ?></td>
                                        <td><?php echo htmlspecialchars(substr($notification['content'], 0, 50)) . (strlen($notification['content']) > 50 ? '...' : ''); ?></td>
                                        <td>
                                            <span class="badge bg-<?php 
                                                switch ($notification['type']) {
                                                    case 'comment': echo 'primary'; break;
                                                    case 'reply': echo 'info'; break;
                                                    case 'like': echo 'success'; break;
                                                    case 'mention': echo 'warning'; break;
                                                    case 'system': echo 'secondary'; break;
                                                    default: echo 'info';
                                                }
                                            ?>">
                                                <?php 
                                                $types = [
                                                    'like' => 'Beğeni',
                                                    'comment' => 'Yorum',
                                                    'reply' => 'Yanıt',
                                                    'mention' => 'Bahsetme',
                                                    'system' => 'Sistem'
                                                ];
                                                echo htmlspecialchars($types[$notification['type']] ?? $notification['type']); 
                                                ?>
                                            </span>
                                        </td>
                                        <td>
                                            <?php if ($notification['is_read']): ?>
                                                <span class="badge bg-success">Okundu</span>
                                            <?php else: ?>
                                                <span class="badge bg-secondary">Okunmadı</span>
                                            <?php endif; ?>
                                        </td>
                                        <td><?php echo htmlspecialchars(date('d.m.Y H:i', strtotime($notification['created_at']))); ?></td>
                                        <td>
                                            <div class="btn-group btn-group-sm">
                                                <a href="index.php?page=notifications&action=delete&id=<?php echo $notification['id']; ?>" 
                                                   class="btn btn-danger btn-sm" 
                                                   onclick="return confirm('Bu bildirimi silmek istediğinizden emin misiniz?');">
                                                    <i class="fas fa-trash"></i>
                                                </a>
                                            </div>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
            
            <!-- Toplu Bildirim Gönder -->
            <div class="tab-pane fade" id="bulk-notification" role="tabpanel" aria-labelledby="bulk-notification-tab">
                <div class="row mt-3">
                    <div class="col-md-8 offset-md-2">
                        <div class="card">
                            <div class="card-header bg-primary text-white">
                                <h5 class="mb-0">Toplu Bildirim Gönder</h5>
                            </div>
                            <div class="card-body">
                                <form method="post" action="">
                                    <div class="mb-3">
                                        <label for="title" class="form-label">Başlık</label>
                                        <input type="text" class="form-control" id="title" name="title" required>
                                    </div>
                                    
                                    <div class="mb-3">
                                        <label for="message" class="form-label">İçerik</label>
                                        <textarea class="form-control" id="message" name="message" rows="3" required></textarea>
                                    </div>
                                    
                                    <div class="mb-3">
                                        <label for="link" class="form-label">Bağlantı (Opsiyonel)</label>
                                        <input type="text" class="form-control" id="link" name="link" placeholder="Örn: /posts/123">
                                    </div>
                                    
                                    <div class="mb-3">
                                        <label for="type" class="form-label">Tip</label>
                                        <select class="form-select" id="type" name="type">
                                            <option value="system">Sistem</option>
                                            <option value="like">Beğeni</option>
                                            <option value="comment">Yorum</option>
                                            <option value="reply">Yanıt</option>
                                            <option value="mention">Bahsetme</option>
                                        </select>
                                    </div>
                                    
                                    <div class="mb-3">
                                        <label for="target_type" class="form-label">Hedef Kitle</label>
                                        <select class="form-select" id="target_type" name="target_type" onchange="toggleTargetFields()">
                                            <option value="all">Tüm Kullanıcılar</option>
                                            <option value="city">Belirli Şehirdeki Kullanıcılar</option>
                                            <option value="district">Belirli İlçedeki Kullanıcılar</option>
                                        </select>
                                    </div>
                                    
                                    <div class="mb-3" id="city_selector" style="display: none;">
                                        <label for="city_id" class="form-label">Şehir</label>
                                        <select class="form-select" id="city_id" name="city_id" onchange="loadDistricts()">
                                            <option value="">Şehir Seçin</option>
                                            <?php foreach ($cities as $city): ?>
                                                <option value="<?php echo htmlspecialchars($city['name']); ?>"><?php echo htmlspecialchars($city['name']); ?></option>
                                            <?php endforeach; ?>
                                        </select>
                                        <div class="form-text text-muted">Not: Şehir adını kullanarak filtreleme yapılır.</div>
                                    </div>
                                    
                                    <div class="mb-3" id="district_selector" style="display: none;">
                                        <label for="district_id" class="form-label">İlçe</label>
                                        <select class="form-select" id="district_id" name="district_id">
                                            <option value="">Önce Şehir Seçin</option>
                                        </select>
                                        <div class="form-text text-muted">Not: İlçe adını kullanarak filtreleme yapılır.</div>
                                    </div>
                                    
                                    <div class="d-grid gap-2">
                                        <button type="submit" name="submit_bulk_notification" class="btn btn-primary">
                                            <i class="fas fa-paper-plane me-2"></i> Bildirimleri Gönder
                                        </button>
                                    </div>
                                </form>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Bildirim Tercihleri -->
            <div class="tab-pane fade" id="notification-preferences" role="tabpanel" aria-labelledby="notification-preferences-tab">
                <div class="mt-3">
                    <div class="alert alert-info">
                        <h5 class="alert-heading">Bildirim Tercihleri İstatistikleri</h5>
                        <p>Kullanıcı bildirim tercihleri istatistikleri burada gösterilir.</p>
                        
                        <?php
                        // Bildirim tercihleri istatistiklerini al
                        try {
                            // Bildirim tercihlerini al
                            $prefs_result = getData('notification_preferences', [
                                'select' => '*'
                            ]);
                            
                            // İstatistikleri hesapla
                            $stats = [
                                'total_users' => 0,
                                'likes_enabled' => 0,
                                'comments_enabled' => 0,
                                'replies_enabled' => 0,
                                'mentions_enabled' => 0,
                                'system_notifications_enabled' => 0
                            ];
                            
                            if ($stats && $stats['total_users'] > 0) {
                                $likes_percent = $stats['likes_enabled_percent'] ?? 0;
                                $comments_percent = $stats['comments_enabled_percent'] ?? 0;
                                $replies_percent = $stats['replies_enabled_percent'] ?? 0;
                                $mentions_percent = $stats['mentions_enabled_percent'] ?? 0;
                                $system_percent = $stats['system_notifications_enabled_percent'] ?? 0;
                                
                                echo '<div class="row mt-3">';
                                echo '<div class="col-md-4">';
                                echo '<p><strong>Beğeni Bildirimleri:</strong> %' . $likes_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-success" role="progressbar" style="width: ' . $likes_percent . '%" aria-valuenow="' . $likes_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
                                echo '</div>';
                                echo '</div>';
                                
                                echo '<div class="col-md-4">';
                                echo '<p><strong>Yorum Bildirimleri:</strong> %' . $comments_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-info" role="progressbar" style="width: ' . $comments_percent . '%" aria-valuenow="' . $comments_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
                                echo '</div>';
                                echo '</div>';
                                
                                echo '<div class="col-md-4">';
                                echo '<p><strong>Yanıt Bildirimleri:</strong> %' . $replies_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-primary" role="progressbar" style="width: ' . $replies_percent . '%" aria-valuenow="' . $replies_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
                                echo '</div>';
                                echo '</div>';
                                echo '</div>';
                                
                                echo '<div class="row mt-3">';
                                echo '<div class="col-md-6">';
                                echo '<p><strong>Bahsetme Bildirimleri:</strong> %' . $mentions_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-warning" role="progressbar" style="width: ' . $mentions_percent . '%" aria-valuenow="' . $mentions_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
                                echo '</div>';
                                echo '</div>';
                                
                                echo '<div class="col-md-6">';
                                echo '<p><strong>Sistem Bildirimleri:</strong> %' . $system_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-secondary" role="progressbar" style="width: ' . $system_percent . '%" aria-valuenow="' . $system_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
                                echo '</div>';
                                echo '</div>';
                                echo '</div>';
                                
                                echo '<p class="mt-3">Toplam Kullanıcı Sayısı: ' . $stats['total_users'] . '</p>';
                            } else {
                                echo '<p>Henüz bildirim tercihi verisi bulunmamaktadır.</p>';
                            }
                        } catch (Exception $e) {
                            echo '<p class="text-danger">İstatistikler alınırken hata oluştu: ' . $e->getMessage() . '</p>';
                        }
                        ?>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Row Level Security Politikaları -->
<div class="card">
    <div class="card-header">
        <h5 class="card-title mb-0">
            <i class="fas fa-shield-alt me-2"></i> Bildirim Güvenlik Politikaları
        </h5>
    </div>
    <div class="card-body">
        <div class="alert alert-success">
            <h6 class="alert-heading">Row Level Security Politikaları</h6>
            <p>Bildirim tabloları için güvenlik politikaları aşağıda listelenmiştir. Bu politikalar, kullanıcıların sadece kendi bildirimlerine erişmesini sağlar.</p>
        </div>
        
        <div class="accordion" id="rlsPoliciesAccordion">
            <div class="accordion-item">
                <h2 class="accordion-header" id="headingOne">
                    <button class="accordion-button" type="button" data-bs-toggle="collapse" data-bs-target="#collapseOne" aria-expanded="true" aria-controls="collapseOne">
                        Bildirim Tablosu Güvenlik Politikaları
                    </button>
                </h2>
                <div id="collapseOne" class="accordion-collapse collapse show" aria-labelledby="headingOne" data-bs-parent="#rlsPoliciesAccordion">
                    <div class="accordion-body">
                        <pre class="bg-light p-3">
-- Bildirim izinleri (Row Level Security)
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Bildirim okuma politikaları
CREATE POLICY "Kullanıcılar kendi bildirimlerini görebilir" 
ON public.notifications 
FOR SELECT 
USING (auth.uid() = user_id);

-- Bildirim güncelleme politikaları
CREATE POLICY "Kullanıcılar kendi bildirimlerini güncelleyebilir" 
ON public.notifications 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Bildirim silme politikaları
CREATE POLICY "Kullanıcılar kendi bildirimlerini silebilir" 
ON public.notifications 
FOR DELETE 
USING (auth.uid() = user_id);

-- Servis rolü politikaları (tetikleyiciler için)
CREATE POLICY "Servis rolü bildirim oluşturabilir" 
ON public.notifications 
FOR INSERT 
TO service_role 
WITH CHECK (true);</pre>
                    </div>
                </div>
            </div>
            <div class="accordion-item">
                <h2 class="accordion-header" id="headingTwo">
                    <button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapseTwo" aria-expanded="false" aria-controls="collapseTwo">
                        Bildirim Tercihleri Tablosu Güvenlik Politikaları
                    </button>
                </h2>
                <div id="collapseTwo" class="accordion-collapse collapse" aria-labelledby="headingTwo" data-bs-parent="#rlsPoliciesAccordion">
                    <div class="accordion-body">
                        <pre class="bg-light p-3">
-- Bildirim izinleri (Row Level Security)
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Bildirim tercihleri politikaları
CREATE POLICY "Kullanıcılar kendi bildirim tercihlerini görebilir" 
ON public.notification_preferences 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi bildirim tercihlerini güncelleyebilir" 
ON public.notification_preferences 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Servis rolü politikaları
CREATE POLICY "Servis rolü bildirim tercihleri oluşturabilir" 
ON public.notification_preferences 
FOR INSERT 
TO service_role 
WITH CHECK (true);</pre>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="alert alert-info mt-3">
            <p><strong>Not:</strong> Bu güvenlik politikaları, kullanıcıların yalnızca kendi verilerine erişmesini sağlayarak veri güvenliğini korur. Supabase'in Row Level Security özelliği kullanılmıştır.</p>
        </div>
    </div>
</div>

<script>
// İlçe ve şehir seçim alanlarını göster/gizle
function toggleTargetFields() {
    var targetType = document.getElementById('target_type').value;
    var citySelector = document.getElementById('city_selector');
    var districtSelector = document.getElementById('district_selector');
    
    if (targetType === 'city') {
        citySelector.style.display = 'block';
        districtSelector.style.display = 'none';
    } else if (targetType === 'district') {
        citySelector.style.display = 'block';
        districtSelector.style.display = 'block';
    } else {
        citySelector.style.display = 'none';
        districtSelector.style.display = 'none';
    }
}

// Seçilen şehre göre ilçeleri yükle
function loadDistricts() {
    var cityId = document.getElementById('city_id').value;
    var districtSelect = document.getElementById('district_id');
    
    // İlçe seçim listesini temizle
    districtSelect.innerHTML = '<option value="">İlçe Seçin</option>';
    
    if (cityId) {
        // JavaScript ile ilçeleri filtrele
        <?php
        echo "var allDistricts = " . json_encode($districts) . ";\n";
        ?>
        
        console.log("Şehir seçildi:", cityId);
        console.log("Tüm ilçeler:", allDistricts);
        
        // İlçeleri filtrele - city_id karşılaştırmasını string olarak yap
        var filteredDistricts = allDistricts.filter(function(district) {
            // City değerlerini karşılaştır
            var cities_result = <?php echo json_encode($cities); ?>;
            var selectedCityId = null;
            
            // Seçilen şehrin ID'sini bul
            for (var i = 0; i < cities_result.length; i++) {
                if (cities_result[i].name === cityId) {
                    selectedCityId = cities_result[i].id;
                    break;
                }
            }
            
            console.log("Aranan şehir:", cityId, "ID:", selectedCityId);
            console.log("İlçe:", district.name, "city_id:", district.city_id);
            
            if (selectedCityId) {
                // Sayısal ve string karşılaştırması
                return district.city_id == selectedCityId || district.city_id === String(selectedCityId);
            }
            
            return false;
        });
        
        // Filtrelenmiş ilçeleri ekle
        filteredDistricts.forEach(function(district) {
            var option = document.createElement('option');
            option.value = district.id;
            option.textContent = district.name;
            districtSelect.appendChild(option);
        });
    }
}

// Sayfa yüklendiğinde form alanlarını ayarla
document.addEventListener('DOMContentLoaded', function() {
    toggleTargetFields();
});
</script>