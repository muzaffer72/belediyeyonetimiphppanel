<?php
// Gelişmiş gönderiler yönetimi sayfası
require_once(__DIR__ . '/../includes/functions.php');

// Arama ve filtreleme parametreleri
$search = $_GET['search'] ?? '';
$filter_type = $_GET['type'] ?? '';
$filter_status = $_GET['status'] ?? '';
$filter_city = $_GET['city_id'] ?? '';
$filter_district = $_GET['district_id'] ?? '';
$filter_user = $_GET['user_id'] ?? '';
$filter_resolved = $_GET['resolved'] ?? '';
$filter_featured = $_GET['featured'] ?? '';
$filter_hidden = $_GET['hidden'] ?? '';
$filter_category = $_GET['category'] ?? '';
$date_from = $_GET['date_from'] ?? '';
$date_to = $_GET['date_to'] ?? '';
$sort_by = $_GET['sort_by'] ?? 'created_at';
$sort_order = $_GET['sort_order'] ?? 'desc';
$page = intval($_GET['page_num'] ?? 1);
$per_page = 20;

// Gönderi işlemleri
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    $post_id = $_POST['post_id'] ?? '';
    
    switch ($action) {
        case 'delete_post':
            // Gönderiyi güvenli şekilde sil (gizle)
            $update_result = updateData('posts', $post_id, [
                'is_hidden' => true,
                'status' => 'deleted',
                'updated_at' => date('Y-m-d H:i:s')
            ]);
            
            if (!$update_result['error']) {
                $_SESSION['message'] = 'Gönderi başarıyla silindi.';
                $_SESSION['message_type'] = 'success';
            } else {
                $_SESSION['message'] = 'Hata: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
                $_SESSION['message_type'] = 'danger';
            }
            break;
            
        case 'toggle_featured':
            $post_result = getDataById('posts', $post_id);
            if (!$post_result['error'] && $post_result['data']) {
                $current_featured = $post_result['data']['is_featured'] ?? false;
                $new_featured = !$current_featured;
                
                $update_result = updateData('posts', $post_id, [
                    'is_featured' => $new_featured,
                    'updated_at' => date('Y-m-d H:i:s')
                ]);
                
                if (!$update_result['error']) {
                    $_SESSION['message'] = $new_featured ? 'Gönderi öne çıkarıldı.' : 'Gönderi öne çıkarma kaldırıldı.';
                    $_SESSION['message_type'] = 'success';
                } else {
                    $_SESSION['message'] = 'Hata: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
                    $_SESSION['message_type'] = 'danger';
                }
            }
            break;
            
        case 'toggle_hidden':
            $post_result = getDataById('posts', $post_id);
            if (!$post_result['error'] && $post_result['data']) {
                $current_hidden = $post_result['data']['is_hidden'] ?? false;
                $new_hidden = !$current_hidden;
                
                $update_result = updateData('posts', $post_id, [
                    'is_hidden' => $new_hidden,
                    'updated_at' => date('Y-m-d H:i:s')
                ]);
                
                if (!$update_result['error']) {
                    $_SESSION['message'] = $new_hidden ? 'Gönderi gizlendi.' : 'Gönderi görünür yapıldı.';
                    $_SESSION['message_type'] = 'success';
                } else {
                    $_SESSION['message'] = 'Hata: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
                    $_SESSION['message_type'] = 'danger';
                }
            }
            break;
            
        case 'update_status':
            $new_status = $_POST['new_status'] ?? '';
            $update_result = updateData('posts', $post_id, [
                'status' => $new_status,
                'is_resolved' => in_array($new_status, ['solved', 'completed']),
                'updated_at' => date('Y-m-d H:i:s')
            ]);
            
            if (!$update_result['error']) {
                $_SESSION['message'] = 'Gönderi durumu güncellendi.';
                $_SESSION['message_type'] = 'success';
            } else {
                $_SESSION['message'] = 'Hata: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
                $_SESSION['message_type'] = 'danger';
            }
            break;
            
        case 'delete_comment':
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
            break;
            
        case 'block_user':
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
    
    redirect('index.php?page=posts');
}

// Filtreleme için veri çekme
$cities_result = getData('cities', ['order' => 'name']);
$cities = $cities_result['data'] ?? [];

$districts_result = getData('districts', ['order' => 'name']);
$districts = $districts_result['data'] ?? [];

// Gönderileri filtreli şekilde getir
$posts_filters = [];
$where_conditions = [];

// Arama
if ($search) {
    $where_conditions[] = "(title.ilike.*{$search}* or description.ilike.*{$search}*)";
}

// Tür filtresi
if ($filter_type) {
    $posts_filters['type'] = 'eq.' . $filter_type;
}

// Durum filtresi
if ($filter_status) {
    $posts_filters['status'] = 'eq.' . $filter_status;
}

// Şehir filtresi
if ($filter_city) {
    $posts_filters['city_id'] = 'eq.' . $filter_city;
}

// İlçe filtresi
if ($filter_district) {
    $posts_filters['district_id'] = 'eq.' . $filter_district;
}

// Kullanıcı filtresi
if ($filter_user) {
    $posts_filters['user_id'] = 'eq.' . $filter_user;
}

// Çözüldü filtresi
if ($filter_resolved !== '') {
    $posts_filters['is_resolved'] = 'eq.' . ($filter_resolved === 'true' ? 'true' : 'false');
}

// Öne çıkarılan filtresi
if ($filter_featured !== '') {
    $posts_filters['is_featured'] = 'eq.' . ($filter_featured === 'true' ? 'true' : 'false');
}

// Gizli filtresi
if ($filter_hidden !== '') {
    $posts_filters['is_hidden'] = 'eq.' . ($filter_hidden === 'true' ? 'true' : 'false');
}

// Kategori filtresi
if ($filter_category) {
    $posts_filters['category'] = 'eq.' . $filter_category;
}

// Tarih filtresi
if ($date_from) {
    $posts_filters['created_at'] = 'gte.' . $date_from;
}
if ($date_to) {
    $posts_filters['created_at'] = 'lte.' . $date_to . ' 23:59:59';
}

// Sıralama
$posts_filters['order'] = $sort_by . '.' . $sort_order;
$posts_filters['limit'] = $per_page;
$posts_filters['offset'] = ($page - 1) * $per_page;

// Arama koşullarını ekle
if (!empty($where_conditions)) {
    $posts_filters['or'] = '(' . implode(',', $where_conditions) . ')';
}

$posts_result = getData('posts', $posts_filters);
$posts = $posts_result['data'] ?? [];

// Toplam sayfa sayısını hesapla
$total_posts_result = getData('posts', array_merge($posts_filters, ['select' => 'count']));
$total_posts = $total_posts_result['data'][0]['count'] ?? 0;
$total_pages = ceil($total_posts / $per_page);

// İstatistikler
$stats_result = getData('posts', ['select' => 'count,type,status,is_resolved,is_featured']);
$all_posts = $stats_result['data'] ?? [];

$total_count = count($all_posts);
$complaint_count = count(array_filter($all_posts, fn($p) => ($p['type'] ?? '') === 'complaint'));
$unresolved_count = count(array_filter($all_posts, fn($p) => !($p['is_resolved'] ?? false)));
$featured_count = count(array_filter($all_posts, fn($p) => ($p['is_featured'] ?? false)));

// Gönderi tipleri
$post_types = [
    'complaint' => ['name' => 'Şikayet', 'color' => 'danger', 'icon' => 'fas fa-exclamation-triangle'],
    'suggestion' => ['name' => 'Öneri', 'color' => 'primary', 'icon' => 'fas fa-lightbulb'],
    'question' => ['name' => 'Soru', 'color' => 'warning', 'icon' => 'fas fa-question-circle'],
    'thanks' => ['name' => 'Teşekkür', 'color' => 'success', 'icon' => 'fas fa-heart'],
    'report' => ['name' => 'Rapor', 'color' => 'info', 'icon' => 'fas fa-file-alt'],
    'feedback' => ['name' => 'Geri Bildirim', 'color' => 'secondary', 'icon' => 'fas fa-comment-alt']
];

// Durum tipleri
$status_types = [
    'pending' => ['name' => 'Beklemede', 'color' => 'warning'],
    'in_progress' => ['name' => 'İşlemde', 'color' => 'info'],
    'solved' => ['name' => 'Çözüldü', 'color' => 'success'],
    'rejected' => ['name' => 'Reddedildi', 'color' => 'danger'],
    'completed' => ['name' => 'Tamamlandı', 'color' => 'primary'],
    'deleted' => ['name' => 'Silindi', 'color' => 'dark']
];

// Kategoriler
$categories = [
    'transportation' => 'Ulaşım',
    'environment' => 'Çevre',
    'infrastructure' => 'Altyapı',
    'health' => 'Sağlık',
    'education' => 'Eğitim',
    'social' => 'Sosyal',
    'other' => 'Diğer'
];
?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">📝 Gönderiler Yönetimi</h1>
    <div>
        <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#advancedFilters">
            <i class="fas fa-filter me-1"></i> Gelişmiş Filtreler
        </button>
        <a href="index.php?page=posts" class="btn btn-secondary">
            <i class="fas fa-refresh me-1"></i> Temizle
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

<!-- İstatistik Kartları -->
<div class="row mb-4">
    <div class="col-md-3">
        <div class="card bg-primary text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Toplam Gönderi</h5>
                        <h2 class="mb-0"><?php echo number_format($total_count); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-file-alt fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card bg-danger text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Şikayetler</h5>
                        <h2 class="mb-0"><?php echo number_format($complaint_count); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-exclamation-triangle fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card bg-warning text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Çözülmemiş</h5>
                        <h2 class="mb-0"><?php echo number_format($unresolved_count); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-clock fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card bg-success text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Öne Çıkan</h5>
                        <h2 class="mb-0"><?php echo number_format($featured_count); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-star fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Hızlı Arama -->
<div class="card mb-4">
    <div class="card-body">
        <form method="get" action="" class="row g-3">
            <input type="hidden" name="page" value="posts">
            
            <div class="col-md-6">
                <div class="input-group">
                    <input type="text" class="form-control" name="search" 
                           placeholder="Başlık veya içerikte ara..." 
                           value="<?php echo escape($search); ?>">
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-search me-1"></i> Ara
                    </button>
                </div>
            </div>
            
            <div class="col-md-2">
                <select class="form-select" name="type" onchange="this.form.submit()">
                    <option value="">Tüm Tipler</option>
                    <?php foreach ($post_types as $key => $type): ?>
                        <option value="<?php echo $key; ?>" <?php echo $filter_type === $key ? 'selected' : ''; ?>>
                            <?php echo $type['name']; ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            
            <div class="col-md-2">
                <select class="form-select" name="status" onchange="this.form.submit()">
                    <option value="">Tüm Durumlar</option>
                    <?php foreach ($status_types as $key => $status): ?>
                        <option value="<?php echo $key; ?>" <?php echo $filter_status === $key ? 'selected' : ''; ?>>
                            <?php echo $status['name']; ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            
            <div class="col-md-2">
                <select class="form-select" name="sort_by" onchange="this.form.submit()">
                    <option value="created_at" <?php echo $sort_by === 'created_at' ? 'selected' : ''; ?>>Tarihe Göre</option>
                    <option value="like_count" <?php echo $sort_by === 'like_count' ? 'selected' : ''; ?>>Beğeni Sayısı</option>
                    <option value="comment_count" <?php echo $sort_by === 'comment_count' ? 'selected' : ''; ?>>Yorum Sayısı</option>
                    <option value="title" <?php echo $sort_by === 'title' ? 'selected' : ''; ?>>Başlık</option>
                </select>
            </div>
        </form>
    </div>
</div>

<!-- Gönderiler Listesi -->
<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Gönderiler (<?php echo number_format($total_posts); ?> sonuç)</h5>
    </div>
    <div class="card-body p-0">
        <?php if (!empty($posts)): ?>
            <div class="table-responsive">
                <table class="table table-hover mb-0">
                    <thead class="table-light">
                        <tr>
                            <th>Gönderi</th>
                            <th>Kullanıcı</th>
                            <th>Konum</th>
                            <th>Durum</th>
                            <th>İstatistikler</th>
                            <th>Tarih</th>
                            <th>İşlemler</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($posts as $post): ?>
                            <?php
                            // Kullanıcı bilgisini getir
                            $user = null;
                            if ($post['user_id']) {
                                $user_result = getDataById('users', $post['user_id']);
                                $user = $user_result['data'] ?? null;
                            }
                            
                            // Şehir ve ilçe bilgisini getir
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
                            
                            $post_type = $post_types[$post['type']] ?? ['name' => 'Bilinmiyor', 'color' => 'secondary', 'icon' => 'fas fa-question'];
                            $post_status = $status_types[$post['status']] ?? ['name' => 'Bilinmiyor', 'color' => 'secondary'];
                            ?>
                            <tr class="<?php echo ($post['is_hidden'] ?? false) ? 'table-secondary' : ''; ?>">
                                <td>
                                    <div class="d-flex align-items-start">
                                        <div class="flex-grow-1">
                                            <div class="d-flex align-items-center mb-1">
                                                <i class="<?php echo $post_type['icon']; ?> text-<?php echo $post_type['color']; ?> me-2"></i>
                                                <strong><?php echo escape($post['title']); ?></strong>
                                                
                                                <?php if ($post['is_featured'] ?? false): ?>
                                                    <span class="badge bg-warning text-dark ms-2">
                                                        <i class="fas fa-star"></i> Öne Çıkan
                                                    </span>
                                                <?php endif; ?>
                                                
                                                <?php if ($post['is_hidden'] ?? false): ?>
                                                    <span class="badge bg-dark ms-2">Gizli</span>
                                                <?php endif; ?>
                                            </div>
                                            <p class="mb-1 text-muted small">
                                                <?php echo escape(substr($post['description'] ?? '', 0, 100)); ?>
                                                <?php if (strlen($post['description'] ?? '') > 100): ?>...<?php endif; ?>
                                            </p>
                                            <div class="d-flex align-items-center">
                                                <span class="badge bg-<?php echo $post_type['color']; ?> me-2">
                                                    <?php echo $post_type['name']; ?>
                                                </span>
                                                <?php if ($post['category']): ?>
                                                    <span class="badge bg-secondary me-2">
                                                        <?php echo $categories[$post['category']] ?? $post['category']; ?>
                                                    </span>
                                                <?php endif; ?>
                                            </div>
                                        </div>
                                    </div>
                                </td>
                                <td>
                                    <?php if ($user): ?>
                                        <div class="d-flex align-items-center">
                                            <?php if ($user['profile_image_url']): ?>
                                                <img src="<?php echo escape($user['profile_image_url']); ?>" 
                                                     class="rounded-circle me-2" width="32" height="32">
                                            <?php else: ?>
                                                <div class="bg-secondary rounded-circle me-2 d-flex align-items-center justify-content-center" 
                                                     style="width: 32px; height: 32px; font-size: 14px; color: white;">
                                                    <?php echo strtoupper(substr($user['display_name'] ?? $user['username'] ?? 'U', 0, 1)); ?>
                                                </div>
                                            <?php endif; ?>
                                            <div>
                                                <div class="fw-semibold"><?php echo escape($user['display_name'] ?? $user['username'] ?? 'Bilinmiyor'); ?></div>
                                                <small class="text-muted"><?php echo escape($user['email'] ?? ''); ?></small>
                                            </div>
                                        </div>
                                    <?php else: ?>
                                        <span class="text-muted">Kullanıcı bulunamadı</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <div>
                                        <?php if ($city_name): ?>
                                            <div class="fw-semibold"><?php echo escape($city_name); ?></div>
                                        <?php endif; ?>
                                        <?php if ($district_name): ?>
                                            <small class="text-muted"><?php echo escape($district_name); ?></small>
                                        <?php endif; ?>
                                        <?php if (!$city_name && !$district_name): ?>
                                            <span class="text-muted">Belirtilmemiş</span>
                                        <?php endif; ?>
                                    </div>
                                </td>
                                <td>
                                    <span class="badge bg-<?php echo $post_status['color']; ?>">
                                        <?php echo $post_status['name']; ?>
                                    </span>
                                    <?php if ($post['is_resolved'] ?? false): ?>
                                        <br><small class="text-success">
                                            <i class="fas fa-check-circle"></i> Çözüldü
                                        </small>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <div class="d-flex flex-column">
                                        <span class="badge bg-primary mb-1">
                                            <i class="fas fa-heart"></i> <?php echo number_format($post['like_count'] ?? 0); ?>
                                        </span>
                                        <span class="badge bg-info">
                                            <i class="fas fa-comment"></i> <?php echo number_format($post['comment_count'] ?? 0); ?>
                                        </span>
                                    </div>
                                </td>
                                <td>
                                    <div><?php echo date('d.m.Y', strtotime($post['created_at'])); ?></div>
                                    <small class="text-muted"><?php echo date('H:i', strtotime($post['created_at'])); ?></small>
                                </td>
                                <td>
                                    <div class="btn-group">
                                        <button type="button" class="btn btn-sm btn-outline-primary dropdown-toggle" 
                                                data-bs-toggle="dropdown">
                                            İşlemler
                                        </button>
                                        <ul class="dropdown-menu">
                                            <li>
                                                <a class="dropdown-item" href="index.php?page=post_detail&id=<?php echo $post['id']; ?>">
                                                    <i class="fas fa-eye me-1"></i> Detayları Görüntüle
                                                </a>
                                            </li>
                                            <li><hr class="dropdown-divider"></li>
                                            <li>
                                                <button class="dropdown-item" onclick="toggleFeatured('<?php echo $post['id']; ?>')">
                                                    <i class="fas fa-star me-1"></i> 
                                                    <?php echo ($post['is_featured'] ?? false) ? 'Öne Çıkarmayı Kaldır' : 'Öne Çıkar'; ?>
                                                </button>
                                            </li>
                                            <li>
                                                <button class="dropdown-item" onclick="toggleHidden('<?php echo $post['id']; ?>')">
                                                    <i class="fas fa-eye<?php echo ($post['is_hidden'] ?? false) ? '' : '-slash'; ?> me-1"></i>
                                                    <?php echo ($post['is_hidden'] ?? false) ? 'Görünür Yap' : 'Gizle'; ?>
                                                </button>
                                            </li>
                                            <li>
                                                <button class="dropdown-item" onclick="changeStatus('<?php echo $post['id']; ?>')">
                                                    <i class="fas fa-edit me-1"></i> Durumu Değiştir
                                                </button>
                                            </li>
                                            <li><hr class="dropdown-divider"></li>
                                            <?php if ($user): ?>
                                                <li>
                                                    <button class="dropdown-item text-warning" onclick="blockUser('<?php echo $user['id']; ?>', '<?php echo escape($user['display_name'] ?? $user['username']); ?>')">
                                                        <i class="fas fa-ban me-1"></i> Kullanıcıyı Engelle
                                                    </button>
                                                </li>
                                            <?php endif; ?>
                                            <li>
                                                <button class="dropdown-item text-danger" onclick="deletePost('<?php echo $post['id']; ?>', '<?php echo escape($post['title']); ?>')">
                                                    <i class="fas fa-trash me-1"></i> Gönderiyi Sil
                                                </button>
                                            </li>
                                        </ul>
                                    </div>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
            
            <!-- Sayfalama -->
            <?php if ($total_pages > 1): ?>
                <div class="card-footer">
                    <nav>
                        <ul class="pagination justify-content-center mb-0">
                            <?php if ($page > 1): ?>
                                <li class="page-item">
                                    <a class="page-link" href="?page=posts&page_num=<?php echo $page - 1; ?>&<?php echo http_build_query($_GET); ?>">
                                        <i class="fas fa-chevron-left"></i>
                                    </a>
                                </li>
                            <?php endif; ?>
                            
                            <?php for ($i = max(1, $page - 2); $i <= min($total_pages, $page + 2); $i++): ?>
                                <li class="page-item <?php echo $i === $page ? 'active' : ''; ?>">
                                    <a class="page-link" href="?page=posts&page_num=<?php echo $i; ?>&<?php echo http_build_query($_GET); ?>">
                                        <?php echo $i; ?>
                                    </a>
                                </li>
                            <?php endfor; ?>
                            
                            <?php if ($page < $total_pages): ?>
                                <li class="page-item">
                                    <a class="page-link" href="?page=posts&page_num=<?php echo $page + 1; ?>&<?php echo http_build_query($_GET); ?>">
                                        <i class="fas fa-chevron-right"></i>
                                    </a>
                                </li>
                            <?php endif; ?>
                        </ul>
                    </nav>
                    
                    <div class="text-center mt-2">
                        <small class="text-muted">
                            Sayfa <?php echo $page; ?> / <?php echo $total_pages; ?> 
                            (Toplam <?php echo number_format($total_posts); ?> gönderi)
                        </small>
                    </div>
                </div>
            <?php endif; ?>
            
        <?php else: ?>
            <div class="text-center py-5">
                <i class="fas fa-inbox fa-4x text-muted mb-3"></i>
                <h5>Gönderi bulunamadı</h5>
                <p class="text-muted">Arama kriterlerinize uygun gönderi bulunamadı.</p>
                <a href="index.php?page=posts" class="btn btn-primary">Tüm Gönderileri Görüntüle</a>
            </div>
        <?php endif; ?>
    </div>
</div>

<!-- Gelişmiş Filtreler Modal -->
<div class="modal fade" id="advancedFilters" tabindex="-1">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">🔍 Gelişmiş Filtreler</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <form method="get" action="">
                <input type="hidden" name="page" value="posts">
                
                <div class="modal-body">
                    <div class="row">
                        <div class="col-md-6">
                            <label class="form-label">Şehir</label>
                            <select class="form-select" name="city_id" onchange="loadDistrictsForFilter(this.value)">
                                <option value="">Tüm Şehirler</option>
                                <?php foreach ($cities as $city): ?>
                                    <option value="<?php echo $city['id']; ?>" <?php echo $filter_city === $city['id'] ? 'selected' : ''; ?>>
                                        <?php echo escape($city['name']); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        
                        <div class="col-md-6">
                            <label class="form-label">İlçe</label>
                            <select class="form-select" name="district_id" id="district_filter">
                                <option value="">Tüm İlçeler</option>
                                <?php foreach ($districts as $district): ?>
                                    <?php if (!$filter_city || $district['city_id'] === $filter_city): ?>
                                        <option value="<?php echo $district['id']; ?>" <?php echo $filter_district === $district['id'] ? 'selected' : ''; ?>>
                                            <?php echo escape($district['name']); ?>
                                        </option>
                                    <?php endif; ?>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mt-3">
                        <div class="col-md-4">
                            <label class="form-label">Kategori</label>
                            <select class="form-select" name="category">
                                <option value="">Tüm Kategoriler</option>
                                <?php foreach ($categories as $key => $category): ?>
                                    <option value="<?php echo $key; ?>" <?php echo $filter_category === $key ? 'selected' : ''; ?>>
                                        <?php echo $category; ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        
                        <div class="col-md-4">
                            <label class="form-label">Çözüldü Durumu</label>
                            <select class="form-select" name="resolved">
                                <option value="">Hepsi</option>
                                <option value="true" <?php echo $filter_resolved === 'true' ? 'selected' : ''; ?>>Çözüldü</option>
                                <option value="false" <?php echo $filter_resolved === 'false' ? 'selected' : ''; ?>>Çözülmedi</option>
                            </select>
                        </div>
                        
                        <div class="col-md-4">
                            <label class="form-label">Öne Çıkarma</label>
                            <select class="form-select" name="featured">
                                <option value="">Hepsi</option>
                                <option value="true" <?php echo $filter_featured === 'true' ? 'selected' : ''; ?>>Öne Çıkan</option>
                                <option value="false" <?php echo $filter_featured === 'false' ? 'selected' : ''; ?>>Normal</option>
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mt-3">
                        <div class="col-md-6">
                            <label class="form-label">Başlangıç Tarihi</label>
                            <input type="date" class="form-control" name="date_from" value="<?php echo $date_from; ?>">
                        </div>
                        
                        <div class="col-md-6">
                            <label class="form-label">Bitiş Tarihi</label>
                            <input type="date" class="form-control" name="date_to" value="<?php echo $date_to; ?>">
                        </div>
                    </div>
                </div>
                
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <a href="index.php?page=posts" class="btn btn-outline-warning">Temizle</a>
                    <button type="submit" class="btn btn-primary">Filtrele</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Gizli Form -->
<form id="hiddenForm" method="post" style="display: none;">
    <input type="hidden" name="action" id="hiddenAction">
    <input type="hidden" name="post_id" id="hiddenPostId">
    <input type="hidden" name="user_id" id="hiddenUserId">
    <input type="hidden" name="comment_id" id="hiddenCommentId">
    <input type="hidden" name="new_status" id="hiddenNewStatus">
</form>

<script>
function toggleFeatured(postId) {
    document.getElementById('hiddenAction').value = 'toggle_featured';
    document.getElementById('hiddenPostId').value = postId;
    document.getElementById('hiddenForm').submit();
}

function toggleHidden(postId) {
    document.getElementById('hiddenAction').value = 'toggle_hidden';
    document.getElementById('hiddenPostId').value = postId;
    document.getElementById('hiddenForm').submit();
}

function deletePost(postId, title) {
    if (confirm('Bu gönderiyi silmek istediğinizden emin misiniz?\n\n"' + title + '"')) {
        document.getElementById('hiddenAction').value = 'delete_post';
        document.getElementById('hiddenPostId').value = postId;
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

function changeStatus(postId) {
    const status = prompt('Yeni durumu seçin:\n' +
        '• pending (Beklemede)\n' +
        '• in_progress (İşlemde)\n' +
        '• solved (Çözüldü)\n' +
        '• rejected (Reddedildi)\n' +
        '• completed (Tamamlandı)');
    
    if (status && ['pending', 'in_progress', 'solved', 'rejected', 'completed'].includes(status)) {
        document.getElementById('hiddenAction').value = 'update_status';
        document.getElementById('hiddenPostId').value = postId;
        document.getElementById('hiddenNewStatus').value = status;
        document.getElementById('hiddenForm').submit();
    }
}

function loadDistrictsForFilter(cityId) {
    const districtSelect = document.getElementById('district_filter');
    
    // Tüm ilçeleri gizle
    Array.from(districtSelect.options).forEach(option => {
        if (option.value !== '') {
            option.style.display = 'none';
        }
    });
    
    // Seçili şehre ait ilçeleri göster
    if (cityId) {
        Array.from(districtSelect.options).forEach(option => {
            if (option.dataset.cityId === cityId) {
                option.style.display = 'block';
            }
        });
    } else {
        // Hiç şehir seçili değilse tüm ilçeleri göster
        Array.from(districtSelect.options).forEach(option => {
            option.style.display = 'block';
        });
    }
    
    districtSelect.value = '';
}
</script>