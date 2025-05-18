<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');
// Yorumları al
$comments_result = getData('comments');
$comments = $comments_result['data'];

// İlişkili verileri al
$posts_result = getData('posts');
$posts = $posts_result['data'];

$users_result = getData('users');
$users = $users_result['data'];

// Yorumu gizle/göster
if (isset($_GET['toggle']) && !empty($_GET['toggle'])) {
    $comment_id = $_GET['toggle'];
    
    // Mevcut durumu bul
    $is_hidden = false;
    foreach ($comments as $comment) {
        if ($comment['id'] === $comment_id) {
            $is_hidden = isset($comment['is_hidden']) && $comment['is_hidden'] === 'true';
            break;
        }
    }
    
    // Durumu tersine çevir
    $update_data = [
        'is_hidden' => $is_hidden ? 'false' : 'true',
        'updated_at' => date('Y-m-d H:i:s')
    ];
    
    $response = updateData('comments', $comment_id, $update_data);
    
    if (!$response['error']) {
        $_SESSION['message'] = $is_hidden ? 'Yorum görünür yapıldı' : 'Yorum gizlendi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Yorum durumu güncellenirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=comments');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=comments";</script>';
        exit;
    }
}

// Yorumu sil
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $comment_id = $_GET['delete'];
    
    // İlgili yorumu bul ve gönderi ID'sini al (post comment_count güncellemesi için)
    $post_id = null;
    foreach ($comments as $comment) {
        if ($comment['id'] === $comment_id) {
            $post_id = $comment['post_id'];
            break;
        }
    }
    
    // Yorumu sil
    $response = deleteData('comments', $comment_id);
    
    if (!$response['error'] && $post_id) {
        // Gönderi yorum sayısını güncelle
        $post = null;
        foreach ($posts as $p) {
            if ($p['id'] === $post_id) {
                $post = $p;
                break;
            }
        }
        
        if ($post && isset($post['comment_count'])) {
            $new_count = max(0, intval($post['comment_count']) - 1);
            
            $update_data = [
                'comment_count' => $new_count,
                'updated_at' => date('Y-m-d H:i:s')
            ];
            
            updateData('posts', $post_id, $update_data);
        }
        
        $_SESSION['message'] = 'Yorum başarıyla silindi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Yorum silinirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=comments');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=comments";</script>';
        exit;
    }
}

// Yorum düzenleme formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_comment'])) {
    $comment_id = $_POST['comment_id'] ?? '';
    $content = trim($_POST['content'] ?? '');
    $is_hidden = isset($_POST['is_hidden']) ? 'true' : 'false';
    
    // Basit doğrulama
    $errors = [];
    if (empty($content)) {
        $errors[] = 'Yorum içeriği gereklidir';
    }
    
    // Hata yoksa yorumu güncelle
    if (empty($errors)) {
        $update_data = [
            'content' => $content,
            'is_hidden' => $is_hidden,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        $response = updateData('comments', $comment_id, $update_data);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Yorum başarıyla güncellendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile
            if (!headers_sent()) {
        header('Location: index.php?page=comments');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=comments";</script>';
        exit;
    }
        } else {
            $_SESSION['message'] = 'Yorum güncellenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// Yorum detayları için ID kontrolü
$edit_comment = null;
if (isset($_GET['edit']) && !empty($_GET['edit'])) {
    $comment_id = $_GET['edit'];
    
    // Yorumları tara ve ID'ye göre yorum detaylarını bul
    foreach ($comments as $comment) {
        if ($comment['id'] === $comment_id) {
            $edit_comment = $comment;
            break;
        }
    }
}

// Filtreleme parametreleri
$post_id_filter = isset($_GET['post_id']) ? $_GET['post_id'] : '';
$user_id_filter = isset($_GET['user_id']) ? $_GET['user_id'] : '';
$hidden_filter = isset($_GET['hidden']) ? $_GET['hidden'] : '';

// Filtreleri uygula
$filtered_comments = $comments;

if (!empty($post_id_filter)) {
    $filtered_comments = array_filter($filtered_comments, function($comment) use ($post_id_filter) {
        return $comment['post_id'] === $post_id_filter;
    });
}

if (!empty($user_id_filter)) {
    $filtered_comments = array_filter($filtered_comments, function($comment) use ($user_id_filter) {
        return $comment['user_id'] === $user_id_filter;
    });
}

if ($hidden_filter !== '') {
    $is_hidden_filter = $hidden_filter === 'true';
    $filtered_comments = array_filter($filtered_comments, function($comment) use ($is_hidden_filter) {
        $is_hidden = isset($comment['is_hidden']) && $comment['is_hidden'] === 'true';
        return $is_hidden === $is_hidden_filter;
    });
}

// Tarih sıralama (en yeni en üstte)
usort($filtered_comments, function($a, $b) {
    return strtotime($b['created_at'] ?? 0) - strtotime($a['created_at'] ?? 0);
});
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
    <h1 class="h3">Yorumlar Yönetimi</h1>
    
    <div>
        <a href="index.php?page=comments" class="btn btn-outline-secondary me-2 <?php echo empty($post_id_filter) && empty($user_id_filter) && $hidden_filter === '' ? 'd-none' : ''; ?>">
            <i class="fas fa-times me-1"></i> Filtreleri Temizle
        </a>
        
        <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#filterCommentsModal">
            <i class="fas fa-filter me-1"></i> Filtrele
        </button>
    </div>
</div>

<!-- Özet Kartları -->
<div class="row mb-4">
    <?php
    // Toplam yorum sayısı
    $total_comments = count($comments);
    
    // Gizlenmiş yorum sayısı
    $hidden_comments = count(array_filter($comments, function($c) {
        return isset($c['is_hidden']) && $c['is_hidden'] === 'true';
    }));
    
    // Bugün eklenen yorum sayısı
    $today = date('Y-m-d');
    $today_comments = count(array_filter($comments, function($c) use ($today) {
        return isset($c['created_at']) && substr($c['created_at'], 0, 10) === $today;
    }));
    
    // Benzersiz kullanıcı sayısı
    $unique_users = [];
    foreach ($comments as $comment) {
        if (isset($comment['user_id']) && !in_array($comment['user_id'], $unique_users)) {
            $unique_users[] = $comment['user_id'];
        }
    }
    $unique_user_count = count($unique_users);
    ?>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-primary text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $total_comments; ?></div>
                        <div>Toplam Yorum</div>
                    </div>
                    <div>
                        <i class="fas fa-comments fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <a class="small text-white stretched-link" href="index.php?page=comments">Tümünü Görüntüle</a>
                <div class="small text-white"><i class="fas fa-angle-right"></i></div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-warning text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $hidden_comments; ?></div>
                        <div>Gizli Yorum</div>
                    </div>
                    <div>
                        <i class="fas fa-eye-slash fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <a class="small text-white stretched-link" href="index.php?page=comments&hidden=true">Gizli Yorumları Görüntüle</a>
                <div class="small text-white"><i class="fas fa-angle-right"></i></div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-success text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $today_comments; ?></div>
                        <div>Bugün Eklenen</div>
                    </div>
                    <div>
                        <i class="fas fa-calendar-day fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <a class="small text-white stretched-link" href="#">Bugünkü Yorumları Görüntüle</a>
                <div class="small text-white"><i class="fas fa-angle-right"></i></div>
            </div>
        </div>
    </div>
    
    <div class="col-xl-3 col-md-6">
        <div class="card bg-info text-white mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <div class="h4 mb-0"><?php echo $unique_user_count; ?></div>
                        <div>Benzersiz Kullanıcı</div>
                    </div>
                    <div>
                        <i class="fas fa-users fa-3x opacity-50"></i>
                    </div>
                </div>
            </div>
            <div class="card-footer d-flex align-items-center justify-content-between">
                <span class="small text-white stretched-link">Yorum Yapan Kullanıcılar</span>
                <div class="small text-white"><i class="fas fa-info-circle"></i></div>
            </div>
        </div>
    </div>
</div>

<!-- Yorum Düzenleme Kartı (Edit modu açıksa) -->
<?php if($edit_comment): ?>
<div class="card mb-4">
    <div class="card-header bg-warning text-dark">
        <i class="fas fa-edit me-1"></i>
        Yorum Düzenle
    </div>
    <div class="card-body">
        <?php
        // Kullanıcı bilgilerini bul
        $user_name = 'Bilinmeyen Kullanıcı';
        $user_image = '';
        foreach ($users as $user) {
            if ($user['id'] === $edit_comment['user_id']) {
                $user_name = $user['username'];
                $user_image = $user['profile_image_url'];
                break;
            }
        }
        
        // Gönderi bilgilerini bul
        $post_title = 'Silinmiş Gönderi';
        foreach ($posts as $post) {
            if ($post['id'] === $edit_comment['post_id']) {
                $post_title = $post['title'];
                break;
            }
        }
        ?>
        
        <div class="mb-3">
            <div class="d-flex align-items-center">
                <?php if(!empty($user_image)): ?>
                    <img src="<?php echo $user_image; ?>" class="rounded-circle me-2" width="40" height="40" alt="Profil">
                <?php else: ?>
                    <i class="fas fa-user-circle fa-2x me-2"></i>
                <?php endif; ?>
                <div>
                    <div><strong><?php echo escape($user_name); ?></strong></div>
                    <div class="text-muted small">
                        <?php if(isset($edit_comment['created_at'])): ?>
                            <?php echo formatDate($edit_comment['created_at'], 'd.m.Y H:i'); ?>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="mb-3">
            <div class="card">
                <div class="card-header bg-light">
                    <strong>Yorum Yapılan Gönderi:</strong> <?php echo escape($post_title); ?>
                </div>
            </div>
        </div>
        
        <form method="post" action="index.php?page=comments">
            <input type="hidden" name="comment_id" value="<?php echo $edit_comment['id']; ?>">
            
            <div class="mb-3">
                <label for="content" class="form-label">Yorum İçeriği <span class="text-danger">*</span></label>
                <textarea class="form-control" id="content" name="content" rows="4" required><?php echo $edit_comment['content']; ?></textarea>
            </div>
            
            <div class="mb-3">
                <div class="form-check form-switch">
                    <input class="form-check-input" type="checkbox" id="is_hidden" name="is_hidden" <?php echo (isset($edit_comment['is_hidden']) && $edit_comment['is_hidden'] === 'true') ? 'checked' : ''; ?>>
                    <label class="form-check-label" for="is_hidden">Yorumu Gizle</label>
                </div>
            </div>
            
            <div class="d-flex justify-content-between">
                <a href="index.php?page=comments" class="btn btn-secondary">İptal</a>
                <button type="submit" name="update_comment" class="btn btn-primary">Güncelle</button>
            </div>
        </form>
    </div>
</div>
<?php endif; ?>

<!-- Yorumlar Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-comments me-1"></i>
        Yorumlar Listesi
        <?php if(!empty($post_id_filter) || !empty($user_id_filter) || $hidden_filter !== ''): ?>
            <span class="badge bg-info ms-2">Filtrelenmiş Liste</span>
        <?php endif; ?>
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-striped table-hover">
                <thead>
                    <tr>
                        <th>Kullanıcı</th>
                        <th>Gönderi</th>
                        <th>Yorum</th>
                        <th>Tarih</th>
                        <th>Durum</th>
                        <th style="width: 150px;">İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if(empty($filtered_comments)): ?>
                        <tr>
                            <td colspan="6" class="text-center">Yorum bulunamadı.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($filtered_comments as $comment): ?>
                            <?php
                            // Kullanıcı bilgilerini bul
                            $user_name = 'Bilinmeyen Kullanıcı';
                            $user_image = '';
                            foreach ($users as $user) {
                                if ($user['id'] === $comment['user_id']) {
                                    $user_name = $user['username'];
                                    $user_image = $user['profile_image_url'];
                                    break;
                                }
                            }
                            
                            // Gönderi bilgilerini bul
                            $post_title = 'Silinmiş Gönderi';
                            $post_link = '#';
                            foreach ($posts as $post) {
                                if ($post['id'] === $comment['post_id']) {
                                    $post_title = $post['title'];
                                    $post_link = 'index.php?page=post_detail&id=' . $post['id'];
                                    break;
                                }
                            }
                            
                            // Yorum içeriği önizleme
                            $content_preview = isset($comment['content']) ? mb_substr($comment['content'], 0, 100) . (mb_strlen($comment['content']) > 100 ? '...' : '') : '';
                            
                            // Yorum durumu
                            $is_hidden = isset($comment['is_hidden']) && $comment['is_hidden'] === 'true';
                            ?>
                            <tr <?php echo $is_hidden ? 'class="table-secondary"' : ''; ?>>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <?php if(!empty($user_image)): ?>
                                            <img src="<?php echo $user_image; ?>" class="rounded-circle me-2" width="32" height="32" alt="Profil">
                                        <?php else: ?>
                                            <i class="fas fa-user-circle fa-2x me-2"></i>
                                        <?php endif; ?>
                                        <a href="index.php?page=comments&user_id=<?php echo $comment['user_id']; ?>" class="text-decoration-none">
                                            <?php echo escape($user_name); ?>
                                        </a>
                                    </div>
                                </td>
                                <td>
                                    <a href="<?php echo $post_link; ?>" class="text-decoration-none">
                                        <?php echo escape($post_title); ?>
                                    </a>
                                    <div>
                                        <a href="index.php?page=comments&post_id=<?php echo $comment['post_id']; ?>" class="badge bg-info text-decoration-none">
                                            <i class="fas fa-filter me-1"></i> Bu Gönderinin Yorumları
                                        </a>
                                    </div>
                                </td>
                                <td><?php echo escape($content_preview); ?></td>
                                <td>
                                    <?php if(isset($comment['created_at'])): ?>
                                        <div>Oluşturma: <?php echo formatDate($comment['created_at'], 'd.m.Y H:i'); ?></div>
                                    <?php endif; ?>
                                    <?php if(isset($comment['updated_at']) && $comment['updated_at'] !== $comment['created_at']): ?>
                                        <div>Güncelleme: <?php echo formatDate($comment['updated_at'], 'd.m.Y H:i'); ?></div>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <span class="badge bg-<?php echo $is_hidden ? 'secondary' : 'success'; ?>">
                                        <?php echo $is_hidden ? 'Gizli' : 'Görünür'; ?>
                                    </span>
                                </td>
                                <td>
                                    <div class="btn-group btn-group-sm">
                                        <a href="index.php?page=comments&edit=<?php echo $comment['id']; ?>" class="btn btn-warning" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <a href="index.php?page=comments&toggle=<?php echo $comment['id']; ?>" class="btn btn-<?php echo $is_hidden ? 'success' : 'secondary'; ?>" title="<?php echo $is_hidden ? 'Görünür Yap' : 'Gizle'; ?>">
                                            <i class="fas <?php echo $is_hidden ? 'fa-eye' : 'fa-eye-slash'; ?>"></i>
                                        </a>
                                        <a href="javascript:void(0);" class="btn btn-danger" 
                                           onclick="if(confirm('Bu yorumu silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=comments&delete=<?php echo $comment['id']; ?>';" 
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
<div class="modal fade" id="filterCommentsModal" tabindex="-1" aria-labelledby="filterCommentsModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="filterCommentsModalLabel">Yorumları Filtrele</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="get" action="index.php">
                    <input type="hidden" name="page" value="comments">
                    
                    <div class="mb-3">
                        <label for="post_id" class="form-label">Gönderi</label>
                        <select class="form-select" id="post_id" name="post_id">
                            <option value="">Tümü</option>
                            <?php foreach($posts as $post): ?>
                                <option value="<?php echo $post['id']; ?>" <?php echo $post_id_filter === $post['id'] ? 'selected' : ''; ?>>
                                    <?php echo $post['title']; ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="user_id" class="form-label">Kullanıcı</label>
                        <select class="form-select" id="user_id" name="user_id">
                            <option value="">Tümü</option>
                            <?php foreach($users as $user): ?>
                                <option value="<?php echo $user['id']; ?>" <?php echo $user_id_filter === $user['id'] ? 'selected' : ''; ?>>
                                    <?php echo $user['username']; ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="hidden" class="form-label">Durum</label>
                        <select class="form-select" id="hidden" name="hidden">
                            <option value="">Tümü</option>
                            <option value="true" <?php echo $hidden_filter === 'true' ? 'selected' : ''; ?>>Gizli Yorumlar</option>
                            <option value="false" <?php echo $hidden_filter === 'false' ? 'selected' : ''; ?>>Görünür Yorumlar</option>
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