<?php
// Gerekli dosyaları dahil et
require_once __DIR__ . '/../includes/functions.php';
require_once __DIR__ . '/../config/config.php';

// Yetki kontrolü
if (!isLoggedIn()) {
    header("Location: ../login.php");
    exit;
}

// En etkileşimli kullanıcıları getir (gönderi ve yorum sayısına göre)
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
$offset = ($page - 1) * $limit;

// Sıralama seçeneği
$sort_by = isset($_GET['sort']) ? $_GET['sort'] : 'post_count';
$valid_sorts = ['post_count', 'comment_count', 'total_interactions', 'registration_date'];

if (!in_array($sort_by, $valid_sorts)) {
    $sort_by = 'total_interactions';
}

// Filtreleme
$filter = isset($_GET['filter']) ? $_GET['filter'] : '';

// Kullanıcıları getir
$params = [
    'select' => 'id, username, email, post_count, comment_count, total_interactions, created_at',
    'order' => $sort_by . '.desc',
    'limit' => $limit,
    'offset' => $offset
];

// Filtre ekle
if (!empty($filter)) {
    $params['filter'] = "username.ilike.%$filter% or email.ilike.%$filter%";
}

$users_result = getData('users', $params);
$users = $users_result['data'] ?? [];

// Toplam kullanıcı sayısını al
$total_users_result = getData('users', ['select' => 'count']);
$total_users = $total_users_result['data'][0]['count'] ?? 0;
$total_pages = ceil($total_users / $limit);

// Sayfa başlığı
$title = "En Etkileşimli Kullanıcılar";
?>

<?php include_once __DIR__ . '/header.php'; ?>

<div class="container-fluid px-4">
    <h1 class="mt-4"><?php echo $title; ?></h1>
    
    <ol class="breadcrumb mb-4">
        <li class="breadcrumb-item"><a href="../index.php">Ana Sayfa</a></li>
        <li class="breadcrumb-item active">En Etkileşimli Kullanıcılar</li>
    </ol>
    
    <div class="card mb-4">
        <div class="card-header d-flex justify-content-between align-items-center">
            <div>
                <i class="fas fa-users me-1"></i> Kullanıcı Listesi
            </div>
            <div class="d-flex">
                <form method="get" class="d-flex me-2">
                    <input type="text" name="filter" class="form-control form-control-sm me-2" placeholder="Kullanıcı adı veya e-posta..." value="<?php echo htmlspecialchars($filter); ?>">
                    <button type="submit" class="btn btn-sm btn-primary">
                        <i class="fas fa-search"></i> Ara
                    </button>
                </form>
                <div class="dropdown">
                    <button class="btn btn-sm btn-secondary dropdown-toggle" type="button" id="sortDropdown" data-bs-toggle="dropdown" aria-expanded="false">
                        <i class="fas fa-sort"></i> Sırala
                    </button>
                    <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="sortDropdown">
                        <li><a class="dropdown-item <?php echo $sort_by == 'post_count' ? 'active' : ''; ?>" href="?sort=post_count<?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>">Gönderi Sayısına Göre</a></li>
                        <li><a class="dropdown-item <?php echo $sort_by == 'comment_count' ? 'active' : ''; ?>" href="?sort=comment_count<?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>">Yorum Sayısına Göre</a></li>
                        <li><a class="dropdown-item <?php echo $sort_by == 'total_interactions' ? 'active' : ''; ?>" href="?sort=total_interactions<?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>">Toplam Etkileşime Göre</a></li>
                        <li><a class="dropdown-item <?php echo $sort_by == 'registration_date' ? 'active' : ''; ?>" href="?sort=registration_date<?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>">Kayıt Tarihine Göre</a></li>
                    </ul>
                </div>
            </div>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table class="table table-bordered table-striped table-hover align-middle">
                    <thead class="table-dark">
                        <tr>
                            <th class="text-center" style="width: 60px;">#</th>
                            <th>Kullanıcı Adı</th>
                            <th>E-posta</th>
                            <th class="text-center">Gönderi Sayısı</th>
                            <th class="text-center">Yorum Sayısı</th>
                            <th class="text-center">Toplam Etkileşim</th>
                            <th class="text-center">Kayıt Tarihi</th>
                            <th class="text-center" style="width: 100px;">İşlemler</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($users)): ?>
                        <tr>
                            <td colspan="8" class="text-center py-4">
                                <div class="alert alert-info mb-0">
                                    <?php echo !empty($filter) ? 'Arama kriterlerine uygun kullanıcı bulunamadı.' : 'Henüz kayıtlı kullanıcı bulunmuyor.'; ?>
                                </div>
                            </td>
                        </tr>
                        <?php else: ?>
                            <?php foreach ($users as $index => $user): ?>
                            <tr>
                                <td class="text-center"><?php echo $offset + $index + 1; ?></td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <div class="avatar me-2 bg-light rounded-circle text-center" style="width: 36px; height: 36px; line-height: 36px;">
                                            <i class="fas fa-user text-primary"></i>
                                        </div>
                                        <div>
                                            <div class="fw-bold"><?php echo htmlspecialchars($user['username']); ?></div>
                                            <div class="small text-muted">ID: <?php echo $user['id']; ?></div>
                                        </div>
                                    </div>
                                </td>
                                <td><?php echo htmlspecialchars($user['email']); ?></td>
                                <td class="text-center">
                                    <span class="badge bg-primary"><?php echo $user['post_count'] ?? 0; ?></span>
                                </td>
                                <td class="text-center">
                                    <span class="badge bg-info"><?php echo $user['comment_count'] ?? 0; ?></span>
                                </td>
                                <td class="text-center">
                                    <span class="badge bg-success"><?php echo $user['total_interactions'] ?? 0; ?></span>
                                </td>
                                <td class="text-center">
                                    <?php echo formatDate($user['created_at']); ?>
                                </td>
                                <td class="text-center">
                                    <div class="btn-group btn-group-sm">
                                        <a href="../index.php?page=user_detail&id=<?php echo $user['id']; ?>" class="btn btn-outline-primary" title="Detaylar">
                                            <i class="fas fa-eye"></i>
                                        </a>
                                        <a href="../index.php?page=user_posts&id=<?php echo $user['id']; ?>" class="btn btn-outline-info" title="Gönderiler">
                                            <i class="fas fa-file-alt"></i>
                                        </a>
                                    </div>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
            
            <?php if ($total_pages > 1): ?>
            <nav aria-label="Sayfalama">
                <ul class="pagination justify-content-center mt-4">
                    <?php if ($page > 1): ?>
                    <li class="page-item">
                        <a class="page-link" href="?page=1<?php echo !empty($sort_by) ? '&sort=' . $sort_by : ''; ?><?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>" aria-label="İlk">
                            <span aria-hidden="true">&laquo;&laquo;</span>
                        </a>
                    </li>
                    <li class="page-item">
                        <a class="page-link" href="?page=<?php echo $page - 1; ?><?php echo !empty($sort_by) ? '&sort=' . $sort_by : ''; ?><?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>" aria-label="Önceki">
                            <span aria-hidden="true">&laquo;</span>
                        </a>
                    </li>
                    <?php endif; ?>
                    
                    <?php
                    $start_page = max(1, $page - 2);
                    $end_page = min($total_pages, $page + 2);
                    
                    for ($i = $start_page; $i <= $end_page; $i++):
                    ?>
                    <li class="page-item <?php echo $i == $page ? 'active' : ''; ?>">
                        <a class="page-link" href="?page=<?php echo $i; ?><?php echo !empty($sort_by) ? '&sort=' . $sort_by : ''; ?><?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>">
                            <?php echo $i; ?>
                        </a>
                    </li>
                    <?php endfor; ?>
                    
                    <?php if ($page < $total_pages): ?>
                    <li class="page-item">
                        <a class="page-link" href="?page=<?php echo $page + 1; ?><?php echo !empty($sort_by) ? '&sort=' . $sort_by : ''; ?><?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>" aria-label="Sonraki">
                            <span aria-hidden="true">&raquo;</span>
                        </a>
                    </li>
                    <li class="page-item">
                        <a class="page-link" href="?page=<?php echo $total_pages; ?><?php echo !empty($sort_by) ? '&sort=' . $sort_by : ''; ?><?php echo !empty($filter) ? '&filter=' . urlencode($filter) : ''; ?>" aria-label="Son">
                            <span aria-hidden="true">&raquo;&raquo;</span>
                        </a>
                    </li>
                    <?php endif; ?>
                </ul>
            </nav>
            <?php endif; ?>
        </div>
        <div class="card-footer">
            <div class="d-flex justify-content-between align-items-center">
                <div>
                    Toplam <strong><?php echo $total_users; ?></strong> kullanıcı
                </div>
                <div>
                    Sayfa <strong><?php echo $page; ?></strong> / <strong><?php echo $total_pages; ?></strong>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once __DIR__ . '/footer.php'; ?>