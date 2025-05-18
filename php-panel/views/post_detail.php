<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz gönderi ID\'si';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=posts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=posts";</script>';
        exit;
    }
}

// Gönderi bilgilerini al
$post_id = $_GET['id'];
$post = getDataById('posts', $post_id);

if (!$post) {
    $_SESSION['message'] = 'Gönderi bulunamadı';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=posts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=posts";</script>';
        exit;
    }
}

// Gönderi sahibi bilgilerini al
$user = null;
if (isset($post['user_id'])) {
    $user = getDataById('users', $post['user_id']);
}

// Gönderi yorumlarını al
$comments_result = getData('comments', ['post_id' => 'eq.' . $post_id]);
$comments = $comments_result['data'];

// Gönderi kategori tipleri
$post_types = [
    'complaint' => ['name' => 'Şikayet', 'color' => 'danger', 'icon' => 'fa-exclamation-circle'],
    'suggestion' => ['name' => 'Öneri', 'color' => 'primary', 'icon' => 'fa-lightbulb'],
    'question' => ['name' => 'Soru', 'color' => 'warning', 'icon' => 'fa-question-circle'],
    'thanks' => ['name' => 'Teşekkür', 'color' => 'success', 'icon' => 'fa-heart']
];

// Gönderi tipi rengini belirle
$type_color = 'secondary';
$type_name = 'Gönderi';
$type_icon = 'fa-file-alt';

if (isset($post['type']) && isset($post_types[$post['type']])) {
    $type_color = $post_types[$post['type']]['color'];
    $type_name = $post_types[$post['type']]['name'];
    $type_icon = $post_types[$post['type']]['icon'];
}

// Gönderi çözülme durumu
$is_resolved = isset($post['is_resolved']) && $post['is_resolved'] === 'true';
$is_hidden = isset($post['is_hidden']) && $post['is_hidden'] === 'true';
$is_featured = isset($post['is_featured']) && $post['is_featured'] === 'true';
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Gönderi Detayı</h1>
    
    <div>
        <a href="index.php?page=post_edit&id=<?php echo $post_id; ?>" class="btn btn-warning me-2">
            <i class="fas fa-edit me-1"></i> Düzenle
        </a>
        <a href="index.php?page=posts" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Gönderilere Dön
        </a>
    </div>
</div>

<!-- Ana İçerik -->
<div class="row">
    <!-- Gönderi Detayları -->
    <div class="col-md-8">
        <div class="card mb-4">
            <div class="card-header d-flex justify-content-between align-items-center">
                <div>
                    <span class="badge bg-<?php echo $type_color; ?> me-2">
                        <i class="fas <?php echo $type_icon; ?> me-1"></i> 
                        <?php echo $type_name; ?>
                    </span>
                    <?php if ($is_resolved): ?>
                        <span class="badge bg-success">
                            <i class="fas fa-check-circle me-1"></i> Çözüldü
                        </span>
                    <?php else: ?>
                        <span class="badge bg-warning text-dark">
                            <i class="fas fa-clock me-1"></i> Beklemede
                        </span>
                    <?php endif; ?>
                    
                    <?php if ($is_hidden): ?>
                        <span class="badge bg-danger">
                            <i class="fas fa-eye-slash me-1"></i> Gizli
                        </span>
                    <?php endif; ?>
                    
                    <?php if ($is_featured): ?>
                        <span class="badge bg-info">
                            <i class="fas fa-star me-1"></i> Öne Çıkarıldı
                        </span>
                    <?php endif; ?>
                </div>
                <small class="text-muted">
                    <?php echo isset($post['created_at']) ? formatDate($post['created_at']) : ''; ?>
                </small>
            </div>
            <div class="card-body">
                <h4 class="card-title"><?php echo escape($post['title'] ?? ''); ?></h4>
                <p class="card-text"><?php echo nl2br(escape($post['description'] ?? '')); ?></p>
                
                <!-- Konum Bilgisi -->
                <?php if (isset($post['city']) || isset($post['district'])): ?>
                <div class="mb-3">
                    <h6 class="mb-2">Konum</h6>
                    <p class="mb-0">
                        <?php if (isset($post['city']) && !empty($post['city'])): ?>
                            <span class="badge bg-secondary me-2">
                                <i class="fas fa-city me-1"></i> <?php echo escape($post['city']); ?>
                            </span>
                        <?php endif; ?>
                        
                        <?php if (isset($post['district']) && !empty($post['district'])): ?>
                            <span class="badge bg-secondary">
                                <i class="fas fa-map-marker-alt me-1"></i> <?php echo escape($post['district']); ?>
                            </span>
                        <?php endif; ?>
                    </p>
                </div>
                <?php endif; ?>
                
                <!-- Medya Görselleri -->
                <?php if (isset($post['media_url']) && !empty($post['media_url'])): ?>
                <div class="mb-3">
                    <h6 class="mb-2">Medya</h6>
                    <?php if (isset($post['is_video']) && $post['is_video'] === 'true'): ?>
                        <div class="ratio ratio-16x9">
                            <video src="<?php echo escape($post['media_url']); ?>" controls class="rounded"></video>
                        </div>
                    <?php else: ?>
                        <img src="<?php echo escape($post['media_url']); ?>" alt="Gönderi Görseli" class="img-fluid rounded">
                    <?php endif; ?>
                </div>
                <?php endif; ?>
                
                <!-- Birden fazla medya görseli -->
                <?php if (isset($post['media_urls']) && !empty($post['media_urls'])): 
                    $media_urls = is_array($post['media_urls']) ? $post['media_urls'] : json_decode($post['media_urls'], true);
                    if (!empty($media_urls)):
                ?>
                <div class="mb-4">
                    <h6 class="mb-2">Ek Görseller</h6>
                    <div class="row">
                        <?php foreach ($media_urls as $index => $url): ?>
                            <div class="col-md-3 col-sm-6 mb-3">
                                <a href="<?php echo escape($url); ?>" target="_blank">
                                    <img src="<?php echo escape($url); ?>" alt="Gönderi Görseli <?php echo $index + 1; ?>" class="img-fluid rounded">
                                </a>
                            </div>
                        <?php endforeach; ?>
                    </div>
                </div>
                <?php 
                    endif;
                endif; 
                ?>
                
                <!-- İstatistikler -->
                <div class="mt-4 d-flex">
                    <div class="me-4">
                        <i class="fas fa-heart text-danger"></i>
                        <span><?php echo isset($post['like_count']) ? $post['like_count'] : 0; ?> Beğeni</span>
                    </div>
                    <div>
                        <i class="fas fa-comment text-primary"></i>
                        <span><?php echo isset($post['comment_count']) ? $post['comment_count'] : 0; ?> Yorum</span>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex justify-content-between">
                <!-- Durum Değiştirme Butonları -->
                <div>
                    <?php if (!$is_resolved): ?>
                    <a href="index.php?page=posts&resolve=<?php echo $post_id; ?>&action=mark" class="btn btn-sm btn-success me-2">
                        <i class="fas fa-check-circle me-1"></i> Çözüldü İşaretle
                    </a>
                    <?php else: ?>
                    <a href="index.php?page=posts&resolve=<?php echo $post_id; ?>&action=unmark" class="btn btn-sm btn-warning me-2">
                        <i class="fas fa-times-circle me-1"></i> Çözülmedi İşaretle
                    </a>
                    <?php endif; ?>
                </div>
                
                <!-- Diğer Butonlar -->
                <div>
                    <?php if (!$is_hidden): ?>
                    <a href="index.php?page=posts&visibility=<?php echo $post_id; ?>&action=hide" class="btn btn-sm btn-danger me-2">
                        <i class="fas fa-eye-slash me-1"></i> Gizle
                    </a>
                    <?php else: ?>
                    <a href="index.php?page=posts&visibility=<?php echo $post_id; ?>&action=show" class="btn btn-sm btn-info me-2">
                        <i class="fas fa-eye me-1"></i> Göster
                    </a>
                    <?php endif; ?>
                    
                    <?php if (!$is_featured): ?>
                    <a href="index.php?page=posts&feature=<?php echo $post_id; ?>&action=add" class="btn btn-sm btn-primary me-2">
                        <i class="fas fa-star me-1"></i> Öne Çıkar
                    </a>
                    <?php else: ?>
                    <a href="index.php?page=posts&feature=<?php echo $post_id; ?>&action=remove" class="btn btn-sm btn-secondary me-2">
                        <i class="fas fa-star-half-alt me-1"></i> Öne Çıkarmayı Kaldır
                    </a>
                    <?php endif; ?>
                    
                    <a href="javascript:void(0);" onclick="if(confirm('Bu gönderiyi silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=posts&delete=<?php echo $post_id; ?>';" class="btn btn-sm btn-danger">
                        <i class="fas fa-trash me-1"></i> Sil
                    </a>
                </div>
            </div>
        </div>
        
        <!-- Yorumlar Kartı -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-comments me-1"></i>
                Yorumlar (<?php echo count($comments); ?>)
            </div>
            <div class="card-body">
                <?php if (empty($comments)): ?>
                    <p class="text-center text-muted">Bu gönderiye henüz yorum yapılmamış.</p>
                <?php else: ?>
                    <?php foreach ($comments as $comment): 
                        // Yorum sahibi bilgilerini bul
                        $comment_user = null;
                        if (isset($comment['user_id'])) {
                            foreach ($users_result['data'] as $u) {
                                if ($u['id'] === $comment['user_id']) {
                                    $comment_user = $u;
                                    break;
                                }
                            }
                        }
                    ?>
                    <div class="card mb-3">
                        <div class="card-body">
                            <div class="d-flex mb-3">
                                <div class="flex-shrink-0">
                                    <?php if (isset($comment_user['profile_image_url']) && !empty($comment_user['profile_image_url'])): ?>
                                        <img src="<?php echo escape($comment_user['profile_image_url']); ?>" alt="<?php echo isset($comment_user['username']) ? escape($comment_user['username']) : 'Kullanıcı'; ?>" class="rounded-circle" width="40" height="40">
                                    <?php else: ?>
                                        <div class="bg-secondary text-white rounded-circle d-flex align-items-center justify-content-center" style="width: 40px; height: 40px;">
                                            <i class="fas fa-user"></i>
                                        </div>
                                    <?php endif; ?>
                                </div>
                                <div class="flex-grow-1 ms-3">
                                    <h6 class="mb-0">
                                        <?php echo isset($comment_user['username']) ? escape($comment_user['username']) : 'Bilinmeyen Kullanıcı'; ?>
                                    </h6>
                                    <small class="text-muted">
                                        <?php echo isset($comment['created_at']) ? formatDate($comment['created_at']) : ''; ?>
                                    </small>
                                </div>
                                <?php if (isset($comment['is_hidden']) && $comment['is_hidden'] === 'true'): ?>
                                    <span class="badge bg-danger ms-2">Gizli</span>
                                <?php endif; ?>
                            </div>
                            
                            <p class="card-text"><?php echo nl2br(escape($comment['content'] ?? '')); ?></p>
                            
                            <div class="d-flex justify-content-end">
                                <?php if (isset($comment['is_hidden']) && $comment['is_hidden'] === 'true'): ?>
                                    <a href="index.php?page=comments&visibility=<?php echo $comment['id']; ?>&action=show" class="btn btn-sm btn-info me-2">
                                        <i class="fas fa-eye me-1"></i> Göster
                                    </a>
                                <?php else: ?>
                                    <a href="index.php?page=comments&visibility=<?php echo $comment['id']; ?>&action=hide" class="btn btn-sm btn-danger me-2">
                                        <i class="fas fa-eye-slash me-1"></i> Gizle
                                    </a>
                                <?php endif; ?>
                                <a href="javascript:void(0);" onclick="if(confirm('Bu yorumu silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=comments&delete=<?php echo $comment['id']; ?>';" class="btn btn-sm btn-danger">
                                    <i class="fas fa-trash me-1"></i> Sil
                                </a>
                            </div>
                        </div>
                    </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
        </div>
    </div>
    
    <!-- Yan Panel -->
    <div class="col-md-4">
        <!-- Kullanıcı Bilgileri Kartı -->
        <?php if ($user): ?>
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-user me-1"></i>
                Gönderi Sahibi
            </div>
            <div class="card-body">
                <div class="d-flex align-items-center mb-3">
                    <?php if (isset($user['profile_image_url']) && !empty($user['profile_image_url'])): ?>
                        <img src="<?php echo escape($user['profile_image_url']); ?>" alt="<?php echo escape($user['username']); ?>" class="rounded-circle me-3" width="64" height="64">
                    <?php else: ?>
                        <div class="bg-secondary text-white rounded-circle d-flex align-items-center justify-content-center me-3" style="width: 64px; height: 64px;">
                            <i class="fas fa-user fa-2x"></i>
                        </div>
                    <?php endif; ?>
                    
                    <div>
                        <h5 class="mb-1"><?php echo escape($user['username']); ?></h5>
                        <p class="mb-0 text-muted">
                            <small>Üyelik: <?php echo isset($user['created_at']) ? formatDate($user['created_at'], 'd.m.Y') : ''; ?></small>
                        </p>
                    </div>
                </div>
                
                <?php if (isset($user['email']) && !empty($user['email'])): ?>
                <div class="mb-2">
                    <strong><i class="fas fa-envelope me-1"></i> Email:</strong>
                    <a href="mailto:<?php echo escape($user['email']); ?>"><?php echo escape($user['email']); ?></a>
                </div>
                <?php endif; ?>
                
                <?php if (isset($user['phone_number']) && !empty($user['phone_number'])): ?>
                <div class="mb-2">
                    <strong><i class="fas fa-phone me-1"></i> Telefon:</strong>
                    <span><?php echo escape($user['phone_number']); ?></span>
                </div>
                <?php endif; ?>
                
                <?php if (isset($user['city']) || isset($user['district'])): ?>
                <div class="mb-2">
                    <strong><i class="fas fa-map-marker-alt me-1"></i> Konum:</strong>
                    <span>
                        <?php 
                        $location = [];
                        if (isset($user['district']) && !empty($user['district'])) {
                            $location[] = escape($user['district']);
                        }
                        if (isset($user['city']) && !empty($user['city'])) {
                            $location[] = escape($user['city']);
                        }
                        echo implode(', ', $location);
                        ?>
                    </span>
                </div>
                <?php endif; ?>
                
                <?php if (isset($user['role']) && !empty($user['role'])): ?>
                <div class="mb-3">
                    <strong><i class="fas fa-user-tag me-1"></i> Rol:</strong>
                    <span class="badge bg-<?php echo $user['role'] === 'admin' ? 'danger' : 'primary'; ?>">
                        <?php echo $user['role'] === 'admin' ? 'Yönetici' : 'Kullanıcı'; ?>
                    </span>
                </div>
                <?php endif; ?>
                
                <div class="mt-3">
                    <a href="index.php?page=users&id=<?php echo $user['id']; ?>" class="btn btn-sm btn-primary">
                        <i class="fas fa-user me-1"></i> Kullanıcı Detaylarını Gör
                    </a>
                </div>
            </div>
        </div>
        <?php endif; ?>
        
        <!-- İstatistikler Kartı -->
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-chart-pie me-1"></i>
                İstatistikler
            </div>
            <div class="card-body">
                <ul class="list-group list-group-flush">
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Beğeni Sayısı
                        <span class="badge bg-primary rounded-pill"><?php echo isset($post['like_count']) ? $post['like_count'] : 0; ?></span>
                    </li>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Yorum Sayısı
                        <span class="badge bg-primary rounded-pill"><?php echo isset($post['comment_count']) ? $post['comment_count'] : 0; ?></span>
                    </li>
                    <?php if (isset($post['monthly_featured_count'])): ?>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Aylık Öne Çıkarılma
                        <span class="badge bg-info rounded-pill"><?php echo $post['monthly_featured_count']; ?></span>
                    </li>
                    <?php endif; ?>
                    <?php if (isset($post['featured_count'])): ?>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Toplam Öne Çıkarılma
                        <span class="badge bg-info rounded-pill"><?php echo $post['featured_count']; ?></span>
                    </li>
                    <?php endif; ?>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Oluşturulma Tarihi
                        <span class="badge bg-secondary"><?php echo isset($post['created_at']) ? formatDate($post['created_at'], 'd.m.Y') : '-'; ?></span>
                    </li>
                    <?php if (isset($post['updated_at']) && $post['updated_at'] !== $post['created_at']): ?>
                    <li class="list-group-item d-flex justify-content-between align-items-center">
                        Son Güncelleme
                        <span class="badge bg-secondary"><?php echo formatDate($post['updated_at'], 'd.m.Y'); ?></span>
                    </li>
                    <?php endif; ?>
                </ul>
            </div>
        </div>
    </div>
</div>