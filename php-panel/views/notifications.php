<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/db.php');

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
    $city_id = isset($_POST['city_id']) && $_POST['city_id'] != '' ? (int)$_POST['city_id'] : null;
    $district_id = isset($_POST['district_id']) && $_POST['district_id'] != '' ? (int)$_POST['district_id'] : null;
    
    // SQL sorgusu oluşturma
    if ($target_type == 'all') {
        // Tüm kullanıcılara bildirim
        $sql = "INSERT INTO notifications (user_id, title, content, related_entity_id, type, is_read, created_at) 
                SELECT id, '$title', '$message', '$link', '$type', false, NOW() 
                FROM auth.users WHERE NOT is_admin";
    } elseif ($target_type == 'city' && $city_id) {
        // Belirli şehirdeki kullanıcılara bildirim
        $sql = "INSERT INTO notifications (user_id, title, content, related_entity_id, type, is_read, created_at) 
                SELECT DISTINCT u.id, '$title', '$message', '$link', '$type', false, NOW() 
                FROM auth.users u
                JOIN posts p ON u.id = p.user_id
                WHERE p.city_id = $city_id AND NOT u.is_admin";
    } elseif ($target_type == 'district' && $district_id) {
        // Belirli ilçedeki kullanıcılara bildirim
        $sql = "INSERT INTO notifications (user_id, title, content, related_entity_id, type, is_read, created_at) 
                SELECT DISTINCT u.id, '$title', '$message', '$link', '$type', false, NOW() 
                FROM auth.users u
                JOIN posts p ON u.id = p.user_id
                WHERE p.district_id = $district_id AND NOT u.is_admin";
    }

    if (isset($sql)) {
        try {
            // Bildirimi gönder
            $result = db_query($sql);
            
            if ($result) {
                $success_message = "Bildirimler başarıyla gönderildi!";
            } else {
                $error_message = "Bildirim gönderme hatası: Veritabanı hatası oluştu.";
            }
        } catch (Exception $e) {
            $error_message = "Hata: " . $e->getMessage();
        }
    } else {
        $error_message = "Geçersiz hedef tipi veya eksik bilgi.";
    }
}

// Silme işlemi
if ($action == 'delete' && $notification_id > 0) {
    $sql = "DELETE FROM notifications WHERE id = '$notification_id'";
    
    try {
        $result = db_query($sql);
        
        if ($result) {
            $success_message = "Bildirim başarıyla silindi!";
        } else {
            $error_message = "Bildirim silinirken hata oluştu.";
        }
    } catch (Exception $e) {
        $error_message = "Hata: " . $e->getMessage();
    }
}

// Bildirim listesini al
$sql = "SELECT n.*, u.email as user_email
        FROM notifications n
        LEFT JOIN auth.users u ON n.user_id = u.id
        ORDER BY n.created_at DESC
        LIMIT 200";
try {
    $result = db_query($sql);
    $notifications = db_fetch_all($result) ?: [];
} catch (Exception $e) {
    $error_message = "Hata: " . $e->getMessage();
    $notifications = [];
}

// Şehir listesini al
$sql = "SELECT id, name FROM cities ORDER BY name";
try {
    $result = db_query($sql);
    $cities = db_fetch_all($result) ?: [];
} catch (Exception $e) {
    $cities = [];
}

// İlçe listesini al
$sql = "SELECT id, name, city_id FROM districts ORDER BY name";
try {
    $result = db_query($sql);
    $districts = db_fetch_all($result) ?: [];
} catch (Exception $e) {
    $districts = [];
}

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
                                            <option value="info">Bilgi</option>
                                            <option value="success">Başarı</option>
                                            <option value="warning">Uyarı</option>
                                            <option value="danger">Tehlike</option>
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
                                                <option value="<?php echo $city['id']; ?>"><?php echo htmlspecialchars($city['name']); ?></option>
                                            <?php endforeach; ?>
                                        </select>
                                    </div>
                                    
                                    <div class="mb-3" id="district_selector" style="display: none;">
                                        <label for="district_id" class="form-label">İlçe</label>
                                        <select class="form-select" id="district_id" name="district_id">
                                            <option value="">Önce Şehir Seçin</option>
                                        </select>
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
                        $sql = "SELECT 
                                SUM(CASE WHEN likes_enabled = true THEN 1 ELSE 0 END) as likes_count,
                                SUM(CASE WHEN comments_enabled = true THEN 1 ELSE 0 END) as comments_count,
                                SUM(CASE WHEN replies_enabled = true THEN 1 ELSE 0 END) as replies_count,
                                SUM(CASE WHEN mentions_enabled = true THEN 1 ELSE 0 END) as mentions_count,
                                SUM(CASE WHEN system_notifications_enabled = true THEN 1 ELSE 0 END) as system_count,
                                COUNT(*) as total_users
                                FROM notification_preferences";
                        
                        try {
                            $result = db_query($sql);
                            $stats = db_fetch_one($result);
                            
                            if ($stats && $stats['total_users'] > 0) {
                                $post_replies_percent = round(($stats['post_replies_count'] / $stats['total_users']) * 100);
                                $post_status_percent = round(($stats['post_status_count'] / $stats['total_users']) * 100);
                                $system_announcements_percent = round(($stats['system_announcements_count'] / $stats['total_users']) * 100);
                                
                                echo '<div class="row mt-3">';
                                echo '<div class="col-md-4">';
                                echo '<p><strong>Gönderi Yanıtları:</strong> %' . $post_replies_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-success" role="progressbar" style="width: ' . $post_replies_percent . '%" aria-valuenow="' . $post_replies_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
                                echo '</div>';
                                echo '</div>';
                                
                                echo '<div class="col-md-4">';
                                echo '<p><strong>Gönderi Durum Değişiklikleri:</strong> %' . $post_status_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-info" role="progressbar" style="width: ' . $post_status_percent . '%" aria-valuenow="' . $post_status_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
                                echo '</div>';
                                echo '</div>';
                                
                                echo '<div class="col-md-4">';
                                echo '<p><strong>Sistem Duyuruları:</strong> %' . $system_announcements_percent . '</p>';
                                echo '<div class="progress">';
                                echo '<div class="progress-bar bg-warning" role="progressbar" style="width: ' . $system_announcements_percent . '%" aria-valuenow="' . $system_announcements_percent . '" aria-valuemin="0" aria-valuemax="100"></div>';
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
        
        var filteredDistricts = allDistricts.filter(function(district) {
            return district.city_id === cityId;
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