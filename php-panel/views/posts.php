<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');
// Gönderi verilerini al
$posts_result = getData('posts');
$posts = $posts_result['data'];

// Şehir verilerini al (filtre için)
$cities_result = getData('cities');
$cities = $cities_result['data'];

// Kullanıcı verilerini al (filtre için)
$users_result = getData('users');
$users = $users_result['data'];

// Gönderi kategori tipleri
$post_types = [
    'complaint' => ['name' => 'Şikayet', 'color' => 'danger', 'icon' => 'fa-exclamation-circle'],
    'suggestion' => ['name' => 'Öneri', 'color' => 'primary', 'icon' => 'fa-lightbulb'],
    'question' => ['name' => 'Soru', 'color' => 'warning', 'icon' => 'fa-question-circle'],
    'thanks' => ['name' => 'Teşekkür', 'color' => 'success', 'icon' => 'fa-heart']
];

// Filtreleme
$filter_city = isset($_GET['city']) ? $_GET['city'] : '';
$filter_type = isset($_GET['type']) ? $_GET['type'] : '';
$filter_user = isset($_GET['user']) ? $_GET['user'] : '';
$filter_resolved = isset($_GET['resolved']) ? $_GET['resolved'] : '';

// Filtreleri uygula
$filtered_posts = $posts;
if (!empty($filter_city)) {
    $filtered_posts = array_filter($filtered_posts, function($post) use ($filter_city) {
        return isset($post['city']) && $post['city'] === $filter_city;
    });
}
if (!empty($filter_type)) {
    $filtered_posts = array_filter($filtered_posts, function($post) use ($filter_type) {
        return isset($post['type']) && $post['type'] === $filter_type;
    });
}
if (!empty($filter_user)) {
    $filtered_posts = array_filter($filtered_posts, function($post) use ($filter_user) {
        return isset($post['user_id']) && $post['user_id'] === $filter_user;
    });
}
if ($filter_resolved !== '') {
    $is_resolved = $filter_resolved === 'true';
    $filtered_posts = array_filter($filtered_posts, function($post) use ($is_resolved) {
        return isset($post['is_resolved']) && $post['is_resolved'] == $is_resolved;
    });
}

// Gönderiyi öne çıkar/kaldır
if (isset($_GET['feature']) && !empty($_GET['feature'])) {
    $post_id = $_GET['feature'];
    $admin_id = $_SESSION['user_id'] ?? 'admin-01';  // Varsayılan admin ID
    
    // Öne çıkarılmış mı kontrol et
    $is_featured = false;
    foreach ($posts as $post) {
        if ($post['id'] === $post_id && isset($post['is_featured']) && $post['is_featured']) {
            $is_featured = true;
            break;
        }
    }
    
    if ($is_featured) {
        // Öne çıkarma durumunu kaldır
        $update_data = [
            'is_featured' => false
        ];
        $response = updateData('posts', $post_id, $update_data);
        
        if (!$response['error']) {
            // Öne çıkarılanlar listesinden kaldır
            $featured_posts_result = getData('featured_posts');
            $featured_posts = $featured_posts_result['data'];
            
            foreach ($featured_posts as $fp) {
                if ($fp['post_id'] === $post_id) {
                    deleteData('featured_posts', $fp['id']);
                    break;
                }
            }
            
            $_SESSION['message'] = 'Gönderi öne çıkarılanlardan kaldırıldı';
            $_SESSION['message_type'] = 'success';
        } else {
            $_SESSION['message'] = 'Gönderi güncellenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        // Gönderiyi öne çıkar
        $update_data = [
            'is_featured' => true,
            'featured_count' => 1
        ];
        $response = updateData('posts', $post_id, $update_data);
        
        if (!$response['error']) {
            // Öne çıkarılanlar listesine ekle
            $featured_data = [
                'post_id' => $post_id,
                'user_id' => $admin_id,
                'created_at' => date('Y-m-d H:i:s')
            ];
            
            addData('featured_posts', $featured_data);
            
            $_SESSION['message'] = 'Gönderi başarıyla öne çıkarıldı';
            $_SESSION['message_type'] = 'success';
        } else {
            $_SESSION['message'] = 'Gönderi güncellenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    }
    
    // Sayfayı yeniden yönlendir
    safeRedirect('index.php?page=posts');
}

// Gönderiyi çözüldü/çözülmedi olarak işaretle
if (isset($_GET['resolve']) && !empty($_GET['resolve'])) {
    $post_id = $_GET['resolve'];
    $action = isset($_GET['action']) ? $_GET['action'] : 'toggle';
    
    // Mevcut durumu kontrol et
    $is_resolved = false;
    foreach ($posts as $post) {
        if ($post['id'] === $post_id) {
            $is_resolved = isset($post['is_resolved']) && $post['is_resolved'];
            break;
        }
    }
    
    // Durumu güncelle
    $new_status = $action === 'mark' ? true : ($action === 'unmark' ? false : !$is_resolved);
    
    $update_data = [
        'is_resolved' => $new_status
    ];
    
    $response = updateData('posts', $post_id, $update_data);
    
    if (!$response['error']) {
        $_SESSION['message'] = $new_status ? 'Gönderi çözüldü olarak işaretlendi' : 'Gönderi çözülmedi olarak işaretlendi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Gönderi güncellenirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    safeRedirect('index.php?page=posts');
}

// Gönderiyi gizle/göster
if (isset($_GET['visibility']) && !empty($_GET['visibility'])) {
    $post_id = $_GET['visibility'];
    $action = isset($_GET['action']) ? $_GET['action'] : 'toggle';
    
    // Mevcut durumu kontrol et
    $is_hidden = false;
    foreach ($posts as $post) {
        if ($post['id'] === $post_id) {
            $is_hidden = isset($post['is_hidden']) && $post['is_hidden'];
            break;
        }
    }
    
    // Durumu güncelle
    $new_status = $action === 'hide' ? true : ($action === 'show' ? false : !$is_hidden);
    
    $update_data = [
        'is_hidden' => $new_status
    ];
    
    $response = updateData('posts', $post_id, $update_data);
    
    if (!$response['error']) {
        $_SESSION['message'] = $new_status ? 'Gönderi gizlendi' : 'Gönderi görünür yapıldı';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Gönderi güncellenirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    safeRedirect('index.php?page=posts');
}

// Gönderiyi sil
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $post_id = $_GET['delete'];
    $response = deleteData('posts', $post_id);
    
    if (!$response['error']) {
        // İlişkili yorumları ve beğenileri de sil
        $comments_result = getData('comments');
        $comments = $comments_result['data'];
        foreach ($comments as $comment) {
            if ($comment['post_id'] === $post_id) {
                deleteData('comments', $comment['id']);
            }
        }
        
        $likes_result = getData('likes');
        $likes = $likes_result['data'];
        foreach ($likes as $like) {
            if ($like['post_id'] === $post_id) {
                deleteData('likes', $like['id']);
            }
        }
        
        $_SESSION['message'] = 'Gönderi ve ilişkili veriler başarıyla silindi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Gönderi silinirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Çıktı gönderilmeden önce yönlendirme
    if (!headers_sent()) {
        safeRedirect('index.php?page=posts');
    } else {
        echo '<script>window.location.href = "index.php?page=posts";</script>';
        exit;
    }
}
?>

<!-- İşlem Mesajları -->
<?php if(isset($_SESSION['message'])): ?>
<div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
    <?php echo $_SESSION['message']; ?>
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>
<?php 
    unset($_SESSION['message']);
    unset($_SESSION['message_type']);
endif; 
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Gönderiler Yönetimi</h1>
    
    <div>
        <a href="index.php?page=posts" class="btn btn-outline-secondary me-2 <?php echo empty($filter_city) && empty($filter_type) && empty($filter_user) && $filter_resolved === '' ? 'd-none' : ''; ?>">
            <i class="fas fa-times me-1"></i> Filtreleri Temizle
        </a>
        
        <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#filterPostsModal">
            <i class="fas fa-filter me-1"></i> Filtrele
        </button>
    </div>
</div>

<!-- Özet Kartları -->
<div class="row mb-4">
    <?php
    // Şikayet sayısı
    $complaint_count = count(array_filter($posts, function($p) {
        return isset($p['type']) && $p['type'] === 'complaint';
    }));
    
    // Çözülmemiş şikayet sayısı
    $unresolved_count = count(array_filter($posts, function($p) {
        return isset($p['type']) && $p['type'] === 'complaint' && 
              (!isset($p['is_resolved']) || !$p['is_resolved']);
    }));
    
    // Bugün eklenen gönderi sayısı
    $today = date('Y-m-d');
    $today_count = count(array_filter($posts, function($p) use ($today) {
        return isset($p['created_at']) && substr($p['created_at'], 0, 10) === $today;
    }));
    
    // Öne çıkarılan gönderi sayısı
    $featured_count = count(array_filter($posts, function($p) {
        return isset($p['is_featured']) && $p['is_featured'];
    }));
    ?>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-primary text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $complaint_count; ?></div>
                        <div>Toplam Şikayet</div>
                    </div>
                    <div>
                        <i class="fas fa-exclamation-circle fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <a class="small text-white stretched-link" href="index.php?page=posts&type=complaint">Detayları Görüntüle</a>
                <div class="small text-white"><i class="fas fa-angle-right"></i></div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-warning text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $unresolved_count; ?></div>
                        <div>Çözülmemiş Şikayet</div>
                    </div>
                    <div>
                        <i class="fas fa-clock fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <a class="small text-white stretched-link" href="index.php?page=posts&type=complaint&resolved=false">Detayları Görüntüle</a>
                <div class="small text-white"><i class="fas fa-angle-right"></i></div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-success text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $today_count; ?></div>
                        <div>Bugün Eklenen</div>
                    </div>
                    <div>
                        <i class="fas fa-calendar-day fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <a class="small text-white stretched-link" href="#">Detayları Görüntüle</a>
                <div class="small text-white"><i class="fas fa-angle-right"></i></div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-info text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $featured_count; ?></div>
                        <div>Öne Çıkarılan</div>
                    </div>
                    <div>
                        <i class="fas fa-star fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <a class="small text-white stretched-link" href="index.php?page=featured_posts">Detayları Görüntüle</a>
                <div class="small text-white"><i class="fas fa-angle-right"></i></div>
            </div>
        </div>
    </div>
</div>

<!-- Gönderiler Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-newspaper me-1"></i>
        Gönderiler Listesi
        <?php if(!empty($filter_city) || !empty($filter_type) || !empty($filter_user) || $filter_resolved !== ''): ?>
            <span class="badge bg-info ms-2">Filtrelenmiş Liste</span>
        <?php endif; ?>
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-striped table-hover">
                <thead>
                    <tr>
                        <th>Başlık</th>
                        <th>Tip</th>
                        <th>Kullanıcı</th>
                        <th>Şehir/İlçe</th>
                        <th>Tarih</th>
                        <th>Durum</th>
                        <th>İstatistikler</th>
                        <th style="width: 180px;">İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if(empty($filtered_posts)): ?>
                        <tr>
                            <td colspan="8" class="text-center">Gönderi bulunamadı.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($filtered_posts as $post): ?>
                            <?php 
                            // Kullanıcı bilgilerini bul
                            $user_name = 'Bilinmiyor';
                            $user_image = '';
                            foreach($users as $user) {
                                if($user['id'] === $post['user_id']) {
                                    $user_name = $user['username'];
                                    $user_image = $user['profile_image_url'];
                                    break;
                                }
                            }
                            
                            // Post tipini belirle
                            $post_type = $post_types[$post['type']] ?? ['name' => ucfirst($post['type']), 'color' => 'secondary', 'icon' => 'fa-file-alt'];
                            
                            // Gönderi durumunu belirle
                            $is_resolved = isset($post['is_resolved']) && $post['is_resolved'];
                            $is_hidden = isset($post['is_hidden']) && $post['is_hidden'];
                            $is_featured = isset($post['is_featured']) && $post['is_featured'];
                            ?>
                            <tr <?php echo $is_hidden ? 'class="table-secondary"' : ''; ?>>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <?php if($is_featured): ?>
                                            <span class="badge bg-warning me-2" title="Öne Çıkarılmış"><i class="fas fa-star"></i></span>
                                        <?php endif; ?>
                                        <a href="index.php?page=post_detail&id=<?php echo $post['id']; ?>" class="text-decoration-none">
                                            <?php echo isset($post['title']) ? escape($post['title']) : 'Başlıksız Gönderi'; ?>
                                        </a>
                                    </div>
                                </td>
                                <td>
                                    <span class="badge bg-<?php echo $post_type['color']; ?>">
                                        <i class="fas <?php echo $post_type['icon']; ?> me-1"></i>
                                        <?php echo $post_type['name']; ?>
                                    </span>
                                </td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <?php if(!empty($user_image)): ?>
                                            <img src="<?php echo $user_image; ?>" class="rounded-circle me-2" width="24" height="24" alt="Profil">
                                        <?php else: ?>
                                            <i class="fas fa-user-circle me-2"></i>
                                        <?php endif; ?>
                                        <?php echo escape($user_name); ?>
                                    </div>
                                </td>
                                <td>
                                    <?php 
                                    $location = [];
                                    if(isset($post['city']) && !empty($post['city'])) {
                                        $location[] = $post['city'];
                                    }
                                    if(isset($post['district']) && !empty($post['district'])) {
                                        $location[] = $post['district'];
                                    }
                                    echo !empty($location) ? escape(implode(', ', $location)) : 'Belirtilmemiş';
                                    ?>
                                </td>
                                <td>
                                    <?php 
                                    if(isset($post['created_at'])) {
                                        echo formatDate($post['created_at'], 'd.m.Y H:i');
                                    }
                                    ?>
                                </td>
                                <td>
                                    <?php if($is_hidden): ?>
                                        <span class="badge bg-secondary">Gizlenmiş</span>
                                    <?php elseif($is_resolved): ?>
                                        <span class="badge bg-success">Çözüldü</span>
                                    <?php else: ?>
                                        <span class="badge bg-<?php echo $post['type'] === 'complaint' ? 'warning' : 'info'; ?>">
                                            <?php echo $post['type'] === 'complaint' ? 'Beklemede' : 'Aktif'; ?>
                                        </span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <div class="d-flex gap-2">
                                        <span class="badge bg-primary" title="Beğeni">
                                            <i class="fas fa-thumbs-up me-1"></i>
                                            <?php echo isset($post['like_count']) ? $post['like_count'] : 0; ?>
                                        </span>
                                        <span class="badge bg-info" title="Yorum">
                                            <i class="fas fa-comment me-1"></i>
                                            <?php echo isset($post['comment_count']) ? $post['comment_count'] : 0; ?>
                                        </span>
                                    </div>
                                </td>
                                <td>
                                    <div class="btn-group btn-group-sm">
                                        <a href="index.php?page=post_detail&id=<?php echo $post['id']; ?>" class="btn btn-info" title="Görüntüle">
                                            <i class="fas fa-eye"></i>
                                        </a>
                                        
                                        <!-- Çözüldü/Çözülmedi İşaretleme -->
                                        <?php if($post['type'] === 'complaint'): ?>
                                            <a href="index.php?page=posts&resolve=<?php echo $post['id']; ?>" class="btn btn-<?php echo $is_resolved ? 'warning' : 'success'; ?>" title="<?php echo $is_resolved ? 'Çözülmedi İşaretle' : 'Çözüldü İşaretle'; ?>">
                                                <i class="fas <?php echo $is_resolved ? 'fa-times-circle' : 'fa-check-circle'; ?>"></i>
                                            </a>
                                        <?php endif; ?>
                                        
                                        <!-- Gizle/Göster -->
                                        <a href="index.php?page=posts&visibility=<?php echo $post['id']; ?>" class="btn btn-<?php echo $is_hidden ? 'light' : 'dark'; ?>" title="<?php echo $is_hidden ? 'Göster' : 'Gizle'; ?>">
                                            <i class="fas <?php echo $is_hidden ? 'fa-eye' : 'fa-eye-slash'; ?>"></i>
                                        </a>
                                        
                                        <!-- Öne Çıkar/Kaldır -->
                                        <a href="index.php?page=posts&feature=<?php echo $post['id']; ?>" class="btn btn-<?php echo $is_featured ? 'secondary' : 'warning'; ?>" title="<?php echo $is_featured ? 'Öne Çıkarma' : 'Öne Çıkar'; ?>">
                                            <i class="fas <?php echo $is_featured ? 'fa-star-half-alt' : 'fa-star'; ?>"></i>
                                        </a>
                                        
                                        <!-- Sil -->
                                        <a href="javascript:void(0);" class="btn btn-danger" 
                                           onclick="if(confirm('Bu gönderiyi ve ilişkili tüm verileri silmek istediğinizden emin misiniz?\nBu işlem geri alınamaz!')) window.location.href='index.php?page=posts&delete=<?php echo $post['id']; ?>';" 
                                           title="Sil">
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
</div>

<!-- Filtreleme Modalı -->
<div class="modal fade" id="filterPostsModal" tabindex="-1" aria-labelledby="filterPostsModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="filterPostsModalLabel">Gönderileri Filtrele</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="get" action="index.php">
                    <input type="hidden" name="page" value="posts">
                    
                    <div class="mb-3">
                        <label for="filter_type" class="form-label">Gönderi Tipi</label>
                        <select class="form-select" id="filter_type" name="type">
                            <option value="">Tümü</option>
                            <?php foreach($post_types as $key => $type): ?>
                                <option value="<?php echo $key; ?>" <?php echo $filter_type === $key ? 'selected' : ''; ?>>
                                    <?php echo $type['name']; ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="filter_city" class="form-label">Şehir</label>
                        <select class="form-select" id="filter_city" name="city">
                            <option value="">Tümü</option>
                            <?php 
                            $city_names = [];
                            foreach($posts as $post) {
                                if(isset($post['city']) && !empty($post['city']) && !in_array($post['city'], $city_names)) {
                                    $city_names[] = $post['city'];
                                }
                            }
                            sort($city_names);
                            foreach($city_names as $city): 
                            ?>
                                <option value="<?php echo $city; ?>" <?php echo $filter_city === $city ? 'selected' : ''; ?>>
                                    <?php echo $city; ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="filter_user" class="form-label">Kullanıcı</label>
                        <select class="form-select" id="filter_user" name="user">
                            <option value="">Tümü</option>
                            <?php foreach($users as $user): ?>
                                <option value="<?php echo $user['id']; ?>" <?php echo $filter_user === $user['id'] ? 'selected' : ''; ?>>
                                    <?php echo $user['username']; ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="filter_resolved" class="form-label">Durum (Şikayetler İçin)</label>
                        <select class="form-select" id="filter_resolved" name="resolved">
                            <option value="">Tümü</option>
                            <option value="true" <?php echo $filter_resolved === 'true' ? 'selected' : ''; ?>>Çözüldü</option>
                            <option value="false" <?php echo $filter_resolved === 'false' ? 'selected' : ''; ?>>Beklemede</option>
                        </select>
                    </div>
                    
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                        <button type="submit" class="btn btn-primary">Filtrele</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>