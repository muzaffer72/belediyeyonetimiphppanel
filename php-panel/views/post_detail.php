<?php
// Gönderi detay sayfası
require_once(__DIR__ . '/../includes/functions.php');

// Kullanıcı yetki kontrolü
$user_type = $_SESSION['user_type'] ?? '';
$is_admin = $user_type === 'admin';
$is_moderator = $user_type === 'moderator';
$assigned_city_id = $_SESSION['assigned_city_id'] ?? null;

if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz gönderi ID';
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=posts');
}

$post_id = $_GET['id'];

// Gönderi bilgilerini getir
$post_result = getDataById('posts', $post_id);
if ($post_result['error'] || !$post_result['data']) {
    $_SESSION['message'] = 'Gönderi bulunamadı';
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=posts');
}

$post = $post_result['data'];

// İşlem kontrolleri
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    
    switch ($action) {
        case 'change_status':
            // Hem admin hem moderatör durum değiştirebilir
            if ($is_admin || $is_moderator) {
                $new_status = $_POST['new_status'] ?? '';
                $valid_statuses = ['pending', 'in_progress', 'solved', 'rejected', 'completed'];
                
                if (in_array($new_status, $valid_statuses)) {
                    $update_result = updateData('posts', $post_id, [
                        'status' => $new_status,
                        'updated_at' => date('Y-m-d H:i:s')
                    ]);
                    
                    if (!$update_result['error']) {
                        $_SESSION['message'] = 'Gönderi durumu güncellendi.';
                        $_SESSION['message_type'] = 'success';
                    } else {
                        $_SESSION['message'] = 'Hata: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
                        $_SESSION['message_type'] = 'danger';
                    }
                } else {
                    $_SESSION['message'] = 'Geçersiz durum seçimi.';
                    $_SESSION['message_type'] = 'danger';
                }
            }
            break;
            
        case 'add_comment':
            // Moderatör ve admin yorum ekleyebilir
            if ($is_admin || $is_moderator) {
                $comment_content = trim($_POST['comment_content'] ?? '');
                
                if (!empty($comment_content)) {
                    $comment_data = [
                        'post_id' => $post_id,
                        'user_id' => $_SESSION['user_id'],
                        'content' => $comment_content,
                        'created_at' => date('Y-m-d H:i:s'),
                        'updated_at' => date('Y-m-d H:i:s')
                    ];
                    
                    $add_result = addData('comments', $comment_data);
                    
                    if (!$add_result['error']) {
                        $_SESSION['message'] = 'Yorumunuz eklendi.';
                        $_SESSION['message_type'] = 'success';
                    } else {
                        $_SESSION['message'] = 'Yorum eklenirken hata: ' . ($add_result['message'] ?? 'Bilinmeyen hata');
                        $_SESSION['message_type'] = 'danger';
                    }
                }
            }
            break;
            
        case 'delete_comment':
            // Sadece admin yorum silebilir
            if ($is_admin) {
                $comment_id = $_POST['comment_id'] ?? '';
                $update_result = updateData('comments', $comment_id, [
                    'is_hidden' => true,
                    'updated_at' => date('Y-m-d H:i:s')
                ]);
                
                if (!$update_result['error']) {
                    $_SESSION['message'] = 'Yorum silindi.';
                    $_SESSION['message_type'] = 'success';
                } else {
                    $_SESSION['message'] = 'Hata: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
                    $_SESSION['message_type'] = 'danger';
                }
            }
            break;
            
        case 'block_user':
            // Sadece admin kullanıcı engelleyebilir
            if ($is_admin) {
                $user_id = $_POST['user_id'] ?? '';
                $update_result = updateData('users', $user_id, [
                    'is_blocked' => true,
                    'blocked_at' => date('Y-m-d H:i:s'),
                    'updated_at' => date('Y-m-d H:i:s')
                ]);
            
            if (!$update_result['error']) {
                $_SESSION['message'] = 'Kullanıcı engellendi.';
                $_SESSION['message_type'] = 'success';
            } else {
                $_SESSION['message'] = 'Hata: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
                $_SESSION['message_type'] = 'danger';
            }
            break;
    }
    
    redirect("index.php?page=post_detail&id={$post_id}");
}

// Kullanıcı bilgisini getir
$user = null;
if ($post['user_id']) {
    $user_result = getDataById('users', $post['user_id']);
    $user = $user_result['data'] ?? null;
}

// Şehir ve ilçe bilgilerini getir
$city_name = '';
$district_name = '';

if ($post['city_id']) {
    $city_result = getDataById('cities', $post['city_id']);
    $city_name = $city_result['data']['name'] ?? '';
}

if ($post['district_id']) {
    $district_result = getDataById('districts', $post['district_id']);
    $district_name = $district_result['data']['name'] ?? '';
}

// Yorumları getir
$comments_result = getData('comments', [
    'post_id' => 'eq.' . $post_id,
    'order' => 'created_at.desc'
]);
$comments = $comments_result['data'] ?? [];

// Beğenileri getir
$likes_result = getData('likes', [
    'post_id' => 'eq.' . $post_id,
    'order' => 'created_at.desc'
]);
$likes = $likes_result['data'] ?? [];

// Gönderi tipleri
$post_types = [
    'complaint' => ['name' => 'Şikayet', 'color' => 'danger', 'icon' => 'fas fa-exclamation-triangle'],
    'suggestion' => ['name' => 'Öneri', 'color' => 'primary', 'icon' => 'fas fa-lightbulb'],
    'question' => ['name' => 'Soru', 'color' => 'warning', 'icon' => 'fas fa-question-circle'],
    'thanks' => ['name' => 'Teşekkür', 'color' => 'success', 'icon' => 'fas fa-heart'],
    'report' => ['name' => 'Rapor', 'color' => 'info', 'icon' => 'fas fa-file-alt'],
    'feedback' => ['name' => 'Geri Bildirim', 'color' => 'secondary', 'icon' => 'fas fa-comment-alt']
];

$status_types = [
    'pending' => ['name' => 'Beklemede', 'color' => 'warning'],
    'in_progress' => ['name' => 'İşlemde', 'color' => 'info'],
    'solved' => ['name' => 'Çözüldü', 'color' => 'success'],
    'rejected' => ['name' => 'Reddedildi', 'color' => 'danger'],
    'completed' => ['name' => 'Tamamlandı', 'color' => 'primary'],
    'deleted' => ['name' => 'Silindi', 'color' => 'dark']
];

$post_type = $post_types[$post['type']] ?? ['name' => 'Bilinmiyor', 'color' => 'secondary', 'icon' => 'fas fa-question'];
$post_status = $status_types[$post['status']] ?? ['name' => 'Bilinmiyor', 'color' => 'secondary'];
?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">📄 Gönderi Detayı</h1>
    <div>
        <a href="index.php?page=posts" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Gönderilere Dön
        </a>
    </div>
</div>

<!-- Mesaj gösterimi -->
<?php if (isset($_SESSION['message'])): ?>
    <div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
        <?php echo $_SESSION['message']; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
    <?php unset($_SESSION['message'], $_SESSION['message_type']); ?>
<?php endif; ?>

<div class="row">
    <div class="col-md-8">
        <!-- Gönderi İçeriği -->
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex justify-content-between align-items-center">
                    <div class="d-flex align-items-center">
                        <i class="<?php echo $post_type['icon']; ?> text-<?php echo $post_type['color']; ?> me-2"></i>
                        <h5 class="mb-0"><?php echo escape($post['title']); ?></h5>
                    </div>
                    <div>
                        <?php if ($post['is_featured'] ?? false): ?>
                            <span class="badge bg-warning text-dark me-2">
                                <i class="fas fa-star"></i> Öne Çıkan
                            </span>
                        <?php endif; ?>
                        
                        <?php if ($post['is_hidden'] ?? false): ?>
                            <span class="badge bg-dark">Gizli</span>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
            <div class="card-body">
                <div class="mb-3">
                    <span class="badge bg-<?php echo $post_type['color']; ?> me-2">
                        <?php echo $post_type['name']; ?>
                    </span>
                    <span class="badge bg-<?php echo $post_status['color']; ?> me-2">
                        <?php echo $post_status['name']; ?>
                    </span>
                    <?php if ($post['is_resolved'] ?? false): ?>
                        <span class="badge bg-success">
                            <i class="fas fa-check-circle"></i> Çözüldü
                        </span>
                    <?php endif; ?>
                </div>
                
                <p class="lead"><?php echo nl2br(escape($post['description'] ?? '')); ?></p>
                
                <!-- Medya İçeriği -->
                <?php if ($post['media_url'] || $post['media_urls']): ?>
                    <div class="mt-4">
                        <h6>Ekli Medya</h6>
                        <?php if ($post['media_url']): ?>
                            <?php if ($post['is_video'] ?? false): ?>
                                <video controls class="img-fluid rounded" style="max-height: 400px;">
                                    <source src="<?php echo escape($post['media_url']); ?>" type="video/mp4">
                                    Tarayıcınız video etiketini desteklemiyor.
                                </video>
                            <?php else: ?>
                                <img src="<?php echo escape($post['media_url']); ?>" class="img-fluid rounded" style="max-height: 400px;">
                            <?php endif; ?>
                        <?php endif; ?>
                        
                        <?php if ($post['media_urls']): ?>
                            <?php 
                            $media_urls = is_string($post['media_urls']) ? json_decode($post['media_urls'], true) : $post['media_urls'];
                            $is_video_list = is_string($post['is_video_list']) ? json_decode($post['is_video_list'], true) : ($post['is_video_list'] ?? []);
                            ?>
                            <?php if (is_array($media_urls)): ?>
                                <div class="row g-3">
                                    <?php foreach ($media_urls as $index => $media_url): ?>
                                        <div class="col-md-6">
                                            <?php if (isset($is_video_list[$index]) && $is_video_list[$index]): ?>
                                                <video controls class="img-fluid rounded" style="max-height: 300px;">
                                                    <source src="<?php echo escape($media_url); ?>" type="video/mp4">
                                                    Tarayıcınız video etiketini desteklemiyor.
                                                </video>
                                            <?php else: ?>
                                                <img src="<?php echo escape($media_url); ?>" class="img-fluid rounded" style="max-height: 300px;">
                                            <?php endif; ?>
                                        </div>
                                    <?php endforeach; ?>
                                </div>
                            <?php endif; ?>
                        <?php endif; ?>
                    </div>
                <?php endif; ?>
                
                <!-- İstatistikler -->
                <div class="mt-4 d-flex align-items-center text-muted">
                    <span class="me-3">
                        <i class="fas fa-heart text-danger"></i> 
                        <?php echo number_format($post['like_count'] ?? 0); ?> beğeni
                    </span>
                    <span class="me-3">
                        <i class="fas fa-comment text-primary"></i> 
                        <?php echo number_format($post['comment_count'] ?? 0); ?> yorum
                    </span>
                    <span>
                        <i class="fas fa-calendar"></i> 
                        <?php echo date('d.m.Y H:i', strtotime($post['created_at'])); ?>
                    </span>
                </div>
            </div>
        </div>

        <!-- Yorumlar -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">💬 Yorumlar (<?php echo count($comments); ?>)</h5>
            </div>
            <div class="card-body">
                <?php if (!empty($comments)): ?>
                    <?php foreach ($comments as $comment): ?>
                        <?php
                        // Yorum sahibi kullanıcı bilgisini getir
                        $comment_user = null;
                        if ($comment['user_id']) {
                            $comment_user_result = getDataById('users', $comment['user_id']);
                            $comment_user = $comment_user_result['data'] ?? null;
                        }
                        ?>
                        <div class="border-bottom py-3 <?php echo ($comment['is_hidden'] ?? false) ? 'bg-light' : ''; ?>">
                            <div class="d-flex align-items-start">
                                <div class="me-3">
                                    <?php if ($comment_user && $comment_user['profile_image_url']): ?>
                                        <img src="<?php echo escape($comment_user['profile_image_url']); ?>" 
                                             class="rounded-circle" width="40" height="40">
                                    <?php else: ?>
                                        <div class="bg-secondary rounded-circle d-flex align-items-center justify-content-center" 
                                             style="width: 40px; height: 40px; color: white;">
                                            <?php echo strtoupper(substr($comment_user['display_name'] ?? $comment_user['username'] ?? 'U', 0, 1)); ?>
                                        </div>
                                    <?php endif; ?>
                                </div>
                                
                                <div class="flex-grow-1">
                                    <div class="d-flex justify-content-between align-items-start">
                                        <div>
                                            <h6 class="mb-1">
                                                <?php echo escape($comment_user['display_name'] ?? $comment_user['username'] ?? 'Anonim Kullanıcı'); ?>
                                                <?php if ($comment['is_hidden'] ?? false): ?>
                                                    <span class="badge bg-danger ms-2">Silindi</span>
                                                <?php endif; ?>
                                            </h6>
                                            <small class="text-muted">
                                                <?php echo date('d.m.Y H:i', strtotime($comment['created_at'])); ?>
                                            </small>
                                        </div>
                                        
                                        <?php if ($is_admin): ?>
                                        <div class="dropdown">
                                            <button class="btn btn-sm btn-outline-secondary dropdown-toggle" 
                                                    type="button" data-bs-toggle="dropdown">
                                                İşlemler
                                            </button>
                                            <ul class="dropdown-menu">
                                                <?php if (!($comment['is_hidden'] ?? false)): ?>
                                                    <li>
                                                        <button class="dropdown-item text-danger" 
                                                                onclick="deleteComment('<?php echo $comment['id']; ?>')">
                                                            <i class="fas fa-trash me-1"></i> Yorumu Sil
                                                        </button>
                                                    </li>
                                                <?php endif; ?>
                                                
                                                <?php if ($comment_user): ?>
                                                    <li>
                                                        <button class="dropdown-item text-warning" 
                                                                onclick="blockUser('<?php echo $comment_user['id']; ?>', '<?php echo escape($comment_user['display_name'] ?? $comment_user['username']); ?>')">
                                                            <i class="fas fa-ban me-1"></i> Kullanıcıyı Engelle
                                                        </button>
                                                    </li>
                                                <?php endif; ?>
                                            </ul>
                                        </div>
                                        <?php endif; ?>
                                    </div>
                                    
                                    <p class="mb-0 mt-2"><?php echo nl2br(escape($comment['content'])); ?></p>
                                </div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php else: ?>
                    <div class="text-center py-4">
                        <i class="fas fa-comment-slash fa-3x text-muted mb-3"></i>
                        <h6>Henüz yorum yapılmamış</h6>
                        <p class="text-muted">Bu gönderi için henüz yorum bulunmuyor.</p>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <div class="col-md-4">
        <!-- Kullanıcı Bilgileri -->
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">👤 Gönderi Sahibi</h5>
            </div>
            <div class="card-body">
                <?php if ($user): ?>
                    <div class="d-flex align-items-center mb-3">
                        <?php if ($user['profile_image_url']): ?>
                            <img src="<?php echo escape($user['profile_image_url']); ?>" 
                                 class="rounded-circle me-3" width="60" height="60">
                        <?php else: ?>
                            <div class="bg-secondary rounded-circle me-3 d-flex align-items-center justify-content-center" 
                                 style="width: 60px; height: 60px; font-size: 24px; color: white;">
                                <?php echo strtoupper(substr($user['display_name'] ?? $user['username'] ?? 'U', 0, 1)); ?>
                            </div>
                        <?php endif; ?>
                        
                        <div>
                            <h6 class="mb-1"><?php echo escape($user['display_name'] ?? $user['username'] ?? 'Bilinmiyor'); ?></h6>
                            <small class="text-muted"><?php echo escape($user['email'] ?? ''); ?></small>
                        </div>
                    </div>
                    
                    <table class="table table-sm">
                        <tr>
                            <th>Yaş:</th>
                            <td><?php echo escape($user['age'] ?? 'Belirtilmemiş'); ?></td>
                        </tr>
                        <tr>
                            <th>Cinsiyet:</th>
                            <td><?php echo escape($user['gender'] ?? 'Belirtilmemiş'); ?></td>
                        </tr>
                        <tr>
                            <th>Konum:</th>
                            <td>
                                <?php if ($user['city'] || $user['district']): ?>
                                    <?php echo escape($user['city'] ?? ''); ?>
                                    <?php if ($user['district']): ?>
                                        / <?php echo escape($user['district']); ?>
                                    <?php endif; ?>
                                <?php else: ?>
                                    Belirtilmemiş
                                <?php endif; ?>
                            </td>
                        </tr>
                        <tr>
                            <th>Katılım:</th>
                            <td><?php echo date('d.m.Y', strtotime($user['created_at'])); ?></td>
                        </tr>
                    </table>
                    
                    <div class="d-grid">
                        <button class="btn btn-warning" onclick="blockUser('<?php echo $user['id']; ?>', '<?php echo escape($user['display_name'] ?? $user['username']); ?>')">
                            <i class="fas fa-ban me-1"></i> Kullanıcıyı Engelle
                        </button>
                    </div>
                <?php else: ?>
                    <p class="text-muted">Kullanıcı bilgisi bulunamadı</p>
                <?php endif; ?>
            </div>
        </div>

        <!-- Gönderi Bilgileri -->
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">ℹ️ Gönderi Bilgileri</h5>
            </div>
            <div class="card-body">
                <table class="table table-sm">
                    <tr>
                        <th>ID:</th>
                        <td><code><?php echo escape($post_id); ?></code></td>
                    </tr>
                    <tr>
                        <th>Tür:</th>
                        <td><?php echo $post_type['name']; ?></td>
                    </tr>
                    <tr>
                        <th>Durum:</th>
                        <td><?php echo $post_status['name']; ?></td>
                    </tr>
                    <tr>
                        <th>Kategori:</th>
                        <td>
                            <?php 
                            $categories = [
                                'transportation' => 'Ulaşım',
                                'environment' => 'Çevre',
                                'infrastructure' => 'Altyapı',
                                'health' => 'Sağlık',
                                'education' => 'Eğitim',
                                'social' => 'Sosyal',
                                'other' => 'Diğer'
                            ];
                            echo $categories[$post['category']] ?? ($post['category'] ?? 'Belirtilmemiş');
                            ?>
                        </td>
                    </tr>
                    <tr>
                        <th>Konum:</th>
                        <td>
                            <?php if ($city_name || $district_name): ?>
                                <?php echo escape($city_name); ?>
                                <?php if ($district_name): ?>
                                    / <?php echo escape($district_name); ?>
                                <?php endif; ?>
                            <?php else: ?>
                                Belirtilmemiş
                            <?php endif; ?>
                        </td>
                    </tr>
                    <tr>
                        <th>Oluşturulma:</th>
                        <td><?php echo date('d.m.Y H:i', strtotime($post['created_at'])); ?></td>
                    </tr>
                    <tr>
                        <th>Güncellenme:</th>
                        <td><?php echo $post['updated_at'] ? date('d.m.Y H:i', strtotime($post['updated_at'])) : '-'; ?></td>
                    </tr>
                </table>
            </div>
        </div>

        <!-- Durum Değişikliği - Moderatör ve Admin için -->
        <?php if ($is_admin || $is_moderator): ?>
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">⚙️ Gönderi Durumu</h5>
            </div>
            <div class="card-body">
                <form method="post" class="d-flex gap-2">
                    <input type="hidden" name="action" value="change_status">
                    <select name="new_status" class="form-select" required>
                        <option value="">Yeni durumu seçin</option>
                        <option value="pending" <?php echo ($post['status'] ?? '') === 'pending' ? 'selected' : ''; ?>>Beklemede</option>
                        <option value="in_progress" <?php echo ($post['status'] ?? '') === 'in_progress' ? 'selected' : ''; ?>>İşlemde</option>
                        <option value="solved" <?php echo ($post['status'] ?? '') === 'solved' ? 'selected' : ''; ?>>Çözüldü</option>
                        <option value="rejected" <?php echo ($post['status'] ?? '') === 'rejected' ? 'selected' : ''; ?>>Reddedildi</option>
                        <option value="completed" <?php echo ($post['status'] ?? '') === 'completed' ? 'selected' : ''; ?>>Tamamlandı</option>
                    </select>
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-save"></i> Güncelle
                    </button>
                </form>
            </div>
        </div>
        <?php endif; ?>

        <!-- Yorum Ekleme - Moderatör ve Admin için -->
        <?php if ($is_admin || $is_moderator): ?>
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">💬 Yanıt Ver</h5>
            </div>
            <div class="card-body">
                <form method="post">
                    <input type="hidden" name="action" value="add_comment">
                    <div class="mb-3">
                        <textarea name="comment_content" class="form-control" rows="3" 
                                  placeholder="Gönderiye yanıt yazın..." required></textarea>
                    </div>
                    <button type="submit" class="btn btn-success">
                        <i class="fas fa-reply"></i> Yanıt Ver
                    </button>
                </form>
            </div>
        </div>
        <?php endif; ?>

        <!-- Beğeniler -->
        <div class="card"
            <div class="card-header">
                <h5 class="mb-0">❤️ Beğeniler (<?php echo count($likes); ?>)</h5>
            </div>
            <div class="card-body" style="max-height: 300px; overflow-y: auto;">
                <?php if (!empty($likes)): ?>
                    <?php foreach (array_slice($likes, 0, 20) as $like): ?>
                        <?php
                        $like_user = null;
                        if ($like['user_id']) {
                            $like_user_result = getDataById('users', $like['user_id']);
                            $like_user = $like_user_result['data'] ?? null;
                        }
                        ?>
                        <div class="d-flex align-items-center mb-2">
                            <?php if ($like_user && $like_user['profile_image_url']): ?>
                                <img src="<?php echo escape($like_user['profile_image_url']); ?>" 
                                     class="rounded-circle me-2" width="24" height="24">
                            <?php else: ?>
                                <div class="bg-secondary rounded-circle me-2 d-flex align-items-center justify-content-center" 
                                     style="width: 24px; height: 24px; font-size: 12px; color: white;">
                                    <?php echo strtoupper(substr($like_user['display_name'] ?? $like_user['username'] ?? 'U', 0, 1)); ?>
                                </div>
                            <?php endif; ?>
                            
                            <div class="flex-grow-1">
                                <small class="fw-semibold">
                                    <?php echo escape($like_user['display_name'] ?? $like_user['username'] ?? 'Anonim'); ?>
                                </small>
                                <br>
                                <small class="text-muted">
                                    <?php echo date('d.m.Y H:i', strtotime($like['created_at'])); ?>
                                </small>
                            </div>
                        </div>
                    <?php endforeach; ?>
                    
                    <?php if (count($likes) > 20): ?>
                        <small class="text-muted">Ve <?php echo count($likes) - 20; ?> kişi daha...</small>
                    <?php endif; ?>
                <?php else: ?>
                    <p class="text-muted text-center">Henüz beğeni yok</p>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- Gizli Form -->
<form id="hiddenForm" method="post" style="display: none;">
    <input type="hidden" name="action" id="hiddenAction">
    <input type="hidden" name="comment_id" id="hiddenCommentId">
    <input type="hidden" name="user_id" id="hiddenUserId">
</form>

<script>
function deleteComment(commentId) {
    if (confirm('Bu yorumu silmek istediğinizden emin misiniz?')) {
        document.getElementById('hiddenAction').value = 'delete_comment';
        document.getElementById('hiddenCommentId').value = commentId;
        document.getElementById('hiddenForm').submit();
    }
}

function blockUser(userId, userName) {
    if (confirm('Bu kullanıcıyı engellemek istediğinizden emin misiniz?\n\n' + userName)) {
        document.getElementById('hiddenAction').value = 'block_user';
        document.getElementById('hiddenUserId').value = userId;
        document.getElementById('hiddenForm').submit();
    }
}
</script>