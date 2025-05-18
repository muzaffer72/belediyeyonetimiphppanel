<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');

// URL parametrelerini al
$current_page = isset($_GET['p']) ? intval($_GET['p']) : 1;
$items_per_page = 10;
$offset = ($current_page - 1) * $items_per_page;

// Filtre parametrelerini al
$filter_role = isset($_GET['role']) ? $_GET['role'] : '';
$filter_ban_status = isset($_GET['ban_status']) ? $_GET['ban_status'] : '';
$filter_city = isset($_GET['city']) ? $_GET['city'] : '';
$filter_district = isset($_GET['district']) ? $_GET['district'] : '';
$search_query = isset($_GET['q']) ? $_GET['q'] : '';

// Filtre koşullarını oluştur
$filter_conditions = [];

if (!empty($filter_role)) {
    $filter_conditions['role'] = 'eq.' . $filter_role;
}

if (!empty($filter_city)) {
    $filter_conditions['city'] = 'eq.' . $filter_city;
}

if (!empty($filter_district)) {
    $filter_conditions['district'] = 'eq.' . $filter_district;
}

if (!empty($search_query)) {
    $filter_conditions['or'] = '(username.ilike.*' . $search_query . '*,email.ilike.*' . $search_query . '*)';
}

// Sayfalama için toplam kullanıcı sayısını al
$count_filter = $filter_conditions;
$count_filter['select'] = 'count';
$total_users_result = getData('users', $count_filter);
$total_users = is_numeric($total_users_result['data']) ? intval($total_users_result['data']) : 0;
$total_pages = ceil($total_users / $items_per_page);

// Sayfalama parametrelerini ekle
$filter_conditions['limit'] = $items_per_page;
$filter_conditions['offset'] = $offset;
$filter_conditions['order'] = 'created_at.desc';

// Kullanıcıları al
$users_result = getData('users', $filter_conditions);
$users = $users_result['data'] ?? [];

// Tüm aktif banları al (is_active true olanları ve süresi geçmemiş olanları)
$current_time = date('Y-m-d H:i:s');
$active_bans_result = getData('user_bans', [
    'is_active' => 'eq.true',
    'order' => 'created_at.desc' // En son ban kaydı en üstte olsun
]);
$active_bans = $active_bans_result['data'] ?? [];

// Ban bilgilerini kullanıcı ID'lerine göre düzenle
$ban_info_by_user_id = [];
foreach ($active_bans as $ban) {
    if (isset($ban['user_id']) && isset($ban['ban_end']) && strtotime($ban['ban_end']) > time()) {
        $ban_info_by_user_id[$ban['user_id']] = $ban;
    }
}

// Şehirleri ve ilçeleri al (filtre için)
$cities_result = getData('cities', ['order' => 'name.asc']);
$cities = $cities_result['data'] ?? [];

$districts_result = getData('districts', ['order' => 'name.asc']);
$districts = $districts_result['data'] ?? [];

// Kullanıcı banlama işlemi
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['ban_user'])) {
    $user_id = $_POST['user_id'];
    $ban_reason = $_POST['ban_reason'];
    $ban_duration = intval($_POST['ban_duration']);
    
    // Ban süresi hesapla
    $ban_start = date('Y-m-d H:i:s');
    $ban_end = date('Y-m-d H:i:s', strtotime("+{$ban_duration} days"));
    
    // Foreign key sorunu nedeniyle doğrudan SQL sorgusu kullanacağız
    // Mevcut tüm aktif banları önce deaktif edelim
    $deactivate_query = "UPDATE user_bans SET is_active = false WHERE user_id = '$user_id' AND is_active = true";
    $deactivate_result = executeRawSql($deactivate_query);
    
    // Şimdi yeni ban kaydını ekleyelim, banned_by alanını atlayarak (veritabanı default değeri kullanacak)
    $ban_reason_escaped = str_replace("'", "''", $ban_reason); // SQL injection önlemek
    $insert_query = "INSERT INTO user_bans (user_id, reason, ban_start, ban_end, is_active, created_at) 
                     VALUES ('$user_id', '$ban_reason_escaped', '$ban_start', '$ban_end', true, '$ban_start')";
    $sql_result = executeRawSql($insert_query);
    
    // Sonucu kontrol et
    if (!$sql_result['error']) {
        $_SESSION['message'] = 'Kullanıcı başarıyla banlandı.';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Kullanıcı banlanırken bir hata oluştu: ' . ($sql_result['error_message'] ?? 'Bilinmeyen hata');
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yenile
    if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
}

// Ban kaldırma işlemi
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['unban_user']) && isset($_POST['ban_id'])) {
    $ban_id = $_POST['ban_id'];
    
    // Ban durumunu güncelle
    $update_result = updateData('user_bans', $ban_id, ['is_active' => 'false']);
    
    if (!$update_result['error']) {
        $_SESSION['message'] = 'Kullanıcının banı başarıyla kaldırıldı.';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Ban kaldırılırken bir hata oluştu: ' . $update_result['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yenile
    if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
}

// Kullanıcı silme işlemi
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_user'])) {
    $user_id = $_POST['user_id'];
    
    // İlişkili verileri silmek için cascading delete kullanılmalı
    // Ancak şimdilik sadece kullanıcıyı siliyoruz
    $delete_result = deleteData('users', $user_id);
    
    if (!$delete_result['error']) {
        $_SESSION['message'] = 'Kullanıcı başarıyla silindi.';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Kullanıcı silinirken bir hata oluştu: ' . $delete_result['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yenile
    if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Kullanıcı Yönetimi</h1>
    
    <div>
        <!-- İleride kullanıcı ekleme butonu eklenebilir -->
    </div>
</div>

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

<!-- Filtreleme Kartı -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-filter me-1"></i> Kullanıcıları Filtrele
    </div>
    <div class="card-body">
        <form method="get" action="">
            <input type="hidden" name="page" value="users">
            
            <div class="row g-3">
                <div class="col-md-3">
                    <div class="form-floating">
                        <input type="text" class="form-control" id="searchQuery" name="q" value="<?php echo escape($search_query); ?>" placeholder="Kullanıcı adı veya e-posta">
                        <label for="searchQuery">Kullanıcı Adı veya E-posta</label>
                    </div>
                </div>
                
                <div class="col-md-2">
                    <div class="form-floating">
                        <select class="form-select" id="filterRole" name="role">
                            <option value="">Tümü</option>
                            <option value="user" <?php echo $filter_role === 'user' ? 'selected' : ''; ?>>Normal Kullanıcı</option>
                            <option value="moderator" <?php echo $filter_role === 'moderator' ? 'selected' : ''; ?>>Moderatör</option>
                            <option value="admin" <?php echo $filter_role === 'admin' ? 'selected' : ''; ?>>Yönetici</option>
                        </select>
                        <label for="filterRole">Kullanıcı Rolü</label>
                    </div>
                </div>
                
                <div class="col-md-2">
                    <div class="form-floating">
                        <select class="form-select" id="filterBanStatus" name="ban_status">
                            <option value="">Tümü</option>
                            <option value="banned" <?php echo $filter_ban_status === 'banned' ? 'selected' : ''; ?>>Banlı</option>
                            <option value="active" <?php echo $filter_ban_status === 'active' ? 'selected' : ''; ?>>Aktif</option>
                        </select>
                        <label for="filterBanStatus">Ban Durumu</label>
                    </div>
                </div>
                
                <div class="col-md-2">
                    <div class="form-floating">
                        <select class="form-select" id="filterCity" name="city">
                            <option value="">Tümü</option>
                            <?php foreach ($cities as $city): ?>
                                <option value="<?php echo escape($city['name']); ?>" <?php echo $filter_city === $city['name'] ? 'selected' : ''; ?>>
                                    <?php echo escape($city['name']); ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                        <label for="filterCity">Şehir</label>
                    </div>
                </div>
                
                <div class="col-md-2">
                    <div class="form-floating">
                        <select class="form-select" id="filterDistrict" name="district">
                            <option value="">Tümü</option>
                            <?php foreach ($districts as $district): ?>
                                <option value="<?php echo escape($district['name']); ?>" <?php echo $filter_district === $district['name'] ? 'selected' : ''; ?>>
                                    <?php echo escape($district['name']); ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                        <label for="filterDistrict">İlçe</label>
                    </div>
                </div>
                
                <div class="col-md-1 d-flex align-items-center">
                    <button type="submit" class="btn btn-primary w-100">Filtrele</button>
                </div>
            </div>
        </form>
    </div>
</div>

<!-- Kullanıcılar Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-users me-1"></i> Kullanıcılar
        <span class="badge bg-secondary ms-2"><?php echo $total_users; ?> kullanıcı</span>
    </div>
    <div class="card-body">
        <?php if (empty($users)): ?>
            <div class="alert alert-info">
                <i class="fas fa-info-circle me-1"></i> Herhangi bir kullanıcı bulunamadı.
            </div>
        <?php else: ?>
            <div class="table-responsive">
                <table class="table table-bordered table-striped table-hover" id="usersTable">
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Kullanıcı Adı</th>
                            <th>E-posta</th>
                            <th>Rol</th>
                            <th>Şehir/İlçe</th>
                            <th>Kayıt Tarihi</th>
                            <th>Durum</th>
                            <th>İşlemler</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($users as $user): ?>
                            <?php
                            // Kullanıcının ban durumunu kontrol et
                            $is_banned = false;
                            $active_ban = null;
                            
                            // Eğer kullanıcı ID'si ban listesinde varsa
                            if (isset($ban_info_by_user_id[$user['id']])) {
                                $active_ban = $ban_info_by_user_id[$user['id']];
                                // Doğrudan banlı olarak işaretle (zaten filtrelemiştik)
                                $is_banned = true;
                            }
                            
                            // Kullanıcı rolüne göre renk sınıfını belirle
                            $role_badge_class = 'bg-secondary';
                            if ($user['role'] === 'admin') {
                                $role_badge_class = 'bg-danger';
                            } else if ($user['role'] === 'moderator') {
                                $role_badge_class = 'bg-warning text-dark';
                            }
                            
                            // Rol adını belirle
                            $role_name = 'Normal Kullanıcı';
                            if ($user['role'] === 'admin') {
                                $role_name = 'Yönetici';
                            } else if ($user['role'] === 'moderator') {
                                $role_name = 'Moderatör';
                            }
                            ?>
                            <tr>
                                <td class="text-truncate" style="max-width: 100px;"><?php echo substr($user['id'], 0, 8) . '...'; ?></td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <?php if (isset($user['profile_image_url']) && !empty($user['profile_image_url'])): ?>
                                            <img src="<?php echo escape($user['profile_image_url']); ?>" alt="<?php echo escape($user['username']); ?>" class="rounded-circle me-2" style="width: 32px; height: 32px;">
                                        <?php else: ?>
                                            <div class="avatar bg-secondary text-white rounded-circle d-flex align-items-center justify-content-center me-2" style="width: 32px; height: 32px;">
                                                <i class="fas fa-user"></i>
                                            </div>
                                        <?php endif; ?>
                                        <?php echo escape($user['username']); ?>
                                    </div>
                                </td>
                                <td><?php echo escape($user['email'] ?? '-'); ?></td>
                                <td><span class="badge <?php echo $role_badge_class; ?>"><?php echo $role_name; ?></span></td>
                                <td>
                                    <?php
                                    $location = [];
                                    if (!empty($user['city'])) {
                                        $location[] = $user['city'];
                                    }
                                    if (!empty($user['district'])) {
                                        $location[] = $user['district'];
                                    }
                                    echo empty($location) ? '-' : escape(implode('/', $location));
                                    ?>
                                </td>
                                <td><?php echo isset($user['created_at']) ? date('d.m.Y', strtotime($user['created_at'])) : '-'; ?></td>
                                <td>
                                    <?php if ($is_banned): ?>
                                        <span class="badge bg-danger">
                                            <i class="fas fa-ban me-1"></i> Banlı
                                            <span class="d-none d-md-inline">
                                                (<?php echo date('d.m.Y', strtotime($active_ban['ban_end'])); ?>)
                                            </span>
                                        </span>
                                    <?php else: ?>
                                        <span class="badge bg-success">
                                            <i class="fas fa-check-circle me-1"></i> Aktif
                                        </span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <div class="dropdown">
                                        <button class="btn btn-sm btn-outline-secondary dropdown-toggle" type="button" id="dropdownMenuButton1" data-bs-toggle="dropdown" aria-expanded="false">
                                            İşlemler
                                        </button>
                                        <ul class="dropdown-menu" aria-labelledby="dropdownMenuButton1">
                                            <li>
                                                <a class="dropdown-item" href="index.php?page=user_edit&id=<?php echo $user['id']; ?>">
                                                    <i class="fas fa-user-edit me-1"></i> Düzenle
                                                </a>
                                            </li>
                                            <li>
                                                <a class="dropdown-item" href="index.php?page=posts&user_id=<?php echo $user['id']; ?>">
                                                    <i class="fas fa-clipboard-list me-1"></i> Gönderilerini Görüntüle
                                                </a>
                                            </li>
                                            <li>
                                                <a class="dropdown-item" href="index.php?page=comments&user_id=<?php echo $user['id']; ?>">
                                                    <i class="fas fa-comments me-1"></i> Yorumlarını Görüntüle
                                                </a>
                                            </li>
                                            <li><hr class="dropdown-divider"></li>
                                            <?php if ($is_banned): ?>
                                                <li>
                                                    <button class="dropdown-item" type="button" data-bs-toggle="modal" data-bs-target="#unbanModal" 
                                                            data-ban-id="<?php echo $active_ban['id']; ?>" 
                                                            data-username="<?php echo escape($user['username']); ?>">
                                                        <i class="fas fa-unlock me-1"></i> Banı Kaldır
                                                    </button>
                                                </li>
                                            <?php else: ?>
                                                <li>
                                                    <button class="dropdown-item" type="button" data-bs-toggle="modal" data-bs-target="#banModal" 
                                                            data-user-id="<?php echo $user['id']; ?>" 
                                                            data-username="<?php echo escape($user['username']); ?>">
                                                        <i class="fas fa-ban me-1"></i> Kullanıcıyı Banla
                                                    </button>
                                                </li>
                                            <?php endif; ?>
                                            <li>
                                                <button class="dropdown-item text-danger" type="button" data-bs-toggle="modal" data-bs-target="#deleteModal" 
                                                        data-user-id="<?php echo $user['id']; ?>" 
                                                        data-username="<?php echo escape($user['username']); ?>">
                                                    <i class="fas fa-trash-alt me-1"></i> Kullanıcıyı Sil
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
                <nav aria-label="Page navigation" class="mt-4">
                    <ul class="pagination justify-content-center">
                        <?php if ($current_page > 1): ?>
                            <li class="page-item">
                                <a class="page-link" href="index.php?page=users&p=<?php echo ($current_page - 1); ?>&role=<?php echo $filter_role; ?>&ban_status=<?php echo $filter_ban_status; ?>&city=<?php echo urlencode($filter_city); ?>&district=<?php echo urlencode($filter_district); ?>&q=<?php echo urlencode($search_query); ?>">
                                    <i class="fas fa-chevron-left"></i>
                                </a>
                            </li>
                        <?php else: ?>
                            <li class="page-item disabled">
                                <span class="page-link"><i class="fas fa-chevron-left"></i></span>
                            </li>
                        <?php endif; ?>
                        
                        <?php for ($i = 1; $i <= $total_pages; $i++): ?>
                            <?php if (abs($i - $current_page) <= 2 || $i == 1 || $i == $total_pages): ?>
                                <?php if (abs($i - $current_page) == 3 && ($i == 1 || $i == $total_pages)): ?>
                                    <li class="page-item disabled">
                                        <span class="page-link">...</span>
                                    </li>
                                <?php else: ?>
                                    <li class="page-item <?php echo ($i == $current_page) ? 'active' : ''; ?>">
                                        <a class="page-link" href="index.php?page=users&p=<?php echo $i; ?>&role=<?php echo $filter_role; ?>&ban_status=<?php echo $filter_ban_status; ?>&city=<?php echo urlencode($filter_city); ?>&district=<?php echo urlencode($filter_district); ?>&q=<?php echo urlencode($search_query); ?>">
                                            <?php echo $i; ?>
                                        </a>
                                    </li>
                                <?php endif; ?>
                            <?php endif; ?>
                        <?php endfor; ?>
                        
                        <?php if ($current_page < $total_pages): ?>
                            <li class="page-item">
                                <a class="page-link" href="index.php?page=users&p=<?php echo ($current_page + 1); ?>&role=<?php echo $filter_role; ?>&ban_status=<?php echo $filter_ban_status; ?>&city=<?php echo urlencode($filter_city); ?>&district=<?php echo urlencode($filter_district); ?>&q=<?php echo urlencode($search_query); ?>">
                                    <i class="fas fa-chevron-right"></i>
                                </a>
                            </li>
                        <?php else: ?>
                            <li class="page-item disabled">
                                <span class="page-link"><i class="fas fa-chevron-right"></i></span>
                            </li>
                        <?php endif; ?>
                    </ul>
                </nav>
            <?php endif; ?>
            
        <?php endif; ?>
    </div>
</div>

<!-- Ban Modal -->
<div class="modal fade" id="banModal" tabindex="-1" aria-labelledby="banModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="banModalLabel">Kullanıcıyı Banla</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <form method="post" action="">
                <div class="modal-body">
                    <input type="hidden" name="ban_user" value="1">
                    <input type="hidden" name="user_id" id="banUserId">
                    
                    <p>
                        <i class="fas fa-exclamation-triangle text-warning me-1"></i>
                        <span id="banUsername">Kullanıcı</span> adlı kullanıcıyı banlamak üzeresiniz.
                    </p>
                    
                    <div class="mb-3">
                        <label for="banReason" class="form-label">Ban Nedeni</label>
                        <textarea class="form-control" id="banReason" name="ban_reason" rows="3" required></textarea>
                    </div>
                    
                    <div class="mb-3">
                        <label for="banDuration" class="form-label">Ban Süresi (Gün)</label>
                        <select class="form-select" id="banDuration" name="ban_duration" required>
                            <option value="1">1 Gün</option>
                            <option value="3">3 Gün</option>
                            <option value="7" selected>7 Gün</option>
                            <option value="14">14 Gün</option>
                            <option value="30">30 Gün</option>
                            <option value="90">90 Gün</option>
                            <option value="365">1 Yıl</option>
                        </select>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <button type="submit" class="btn btn-danger">Kullanıcıyı Banla</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Unban Modal -->
<div class="modal fade" id="unbanModal" tabindex="-1" aria-labelledby="unbanModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="unbanModalLabel">Ban Kaldır</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <form method="post" action="">
                <div class="modal-body">
                    <input type="hidden" name="unban_user" value="1">
                    <input type="hidden" name="ban_id" id="unbanBanId">
                    
                    <p>
                        <i class="fas fa-exclamation-triangle text-warning me-1"></i>
                        <span id="unbanUsername">Kullanıcı</span> adlı kullanıcının banını kaldırmak üzeresiniz.
                    </p>
                    <p>Bu işlem, kullanıcının hesabını yeniden aktif hale getirecektir. Devam etmek istiyor musunuz?</p>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <button type="submit" class="btn btn-success">Banı Kaldır</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Delete Modal -->
<div class="modal fade" id="deleteModal" tabindex="-1" aria-labelledby="deleteModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="deleteModalLabel">Kullanıcıyı Sil</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <form method="post" action="">
                <div class="modal-body">
                    <input type="hidden" name="delete_user" value="1">
                    <input type="hidden" name="user_id" id="deleteUserId">
                    
                    <p>
                        <i class="fas fa-exclamation-triangle text-danger me-1"></i>
                        <strong id="deleteUsername">Kullanıcı</strong> adlı kullanıcıyı silmek üzeresiniz.
                    </p>
                    <p>Bu işlem geri alınamaz! Kullanıcının tüm verileri (gönderiler, yorumlar, vb.) silinecektir. Devam etmek istiyor musunuz?</p>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <button type="submit" class="btn btn-danger">Kullanıcıyı Sil</button>
                </div>
            </form>
        </div>
    </div>
</div>

<script>
// Ban Modal veri aktarımı
document.addEventListener('show.bs.modal', function (event) {
    // Ban Modal için
    if (event.target.id === 'banModal') {
        const button = event.relatedTarget;
        const userId = button.getAttribute('data-user-id');
        const username = button.getAttribute('data-username');
        
        document.getElementById('banUserId').value = userId;
        document.getElementById('banUsername').textContent = username;
    }
    
    // Unban Modal için
    if (event.target.id === 'unbanModal') {
        const button = event.relatedTarget;
        const banId = button.getAttribute('data-ban-id');
        const username = button.getAttribute('data-username');
        
        document.getElementById('unbanBanId').value = banId;
        document.getElementById('unbanUsername').textContent = username;
    }
    
    // Delete Modal için
    if (event.target.id === 'deleteModal') {
        const button = event.relatedTarget;
        const userId = button.getAttribute('data-user-id');
        const username = button.getAttribute('data-username');
        
        document.getElementById('deleteUserId').value = userId;
        document.getElementById('deleteUsername').textContent = username;
    }
});

// DataTables eklentisini etkinleştir
document.addEventListener('DOMContentLoaded', function() {
    if (typeof $.fn.DataTable !== 'undefined') {
        const table = $('#usersTable').DataTable({
            paging: false,
            ordering: true,
            info: false,
            searching: false,
            responsive: true,
            language: {
                emptyTable: "Veri bulunamadı",
                info: "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
                infoEmpty: "Gösterilecek veri bulunamadı",
                infoFiltered: "(_MAX_ kayıt içerisinden filtrelendi)",
                lengthMenu: "Sayfada _MENU_ kayıt göster",
                loadingRecords: "Yükleniyor...",
                processing: "İşleniyor...",
                search: "Ara:",
                zeroRecords: "Eşleşen kayıt bulunamadı",
                paginate: {
                    first: "İlk",
                    last: "Son",
                    next: "Sonraki",
                    previous: "Önceki"
                },
                aria: {
                    sortAscending: ": artan sütun sıralamasını aktifleştir",
                    sortDescending: ": azalan sütun sıralamasını aktifleştir"
                }
            }
        });
    }
});

// Şehir değiştiğinde ilçeleri güncelle
document.getElementById('filterCity').addEventListener('change', function() {
    const cityName = this.value;
    const districtSelect = document.getElementById('filterDistrict');
    
    // İlçe dropdown'ını temizle
    districtSelect.innerHTML = '<option value="">Tümü</option>';
    
    if (cityName) {
        // İlgili şehrin ilçelerini al
        fetch('index.php?page=api&action=get_districts_by_city&city=' + encodeURIComponent(cityName))
            .then(response => response.json())
            .then(data => {
                if (data && data.length > 0) {
                    // İlçeleri dropdown'a ekle
                    data.forEach(district => {
                        const option = document.createElement('option');
                        option.value = district.name;
                        option.textContent = district.name;
                        districtSelect.appendChild(option);
                    });
                }
            })
            .catch(error => console.error('İlçeler alınırken bir hata oluştu:', error));
    }
});
</script>