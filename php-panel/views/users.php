<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// Kullanıcı verileri
$users_result = getData('users');
$users = $users_result['data'] ?? [];

// Filtreleme parametreleri
$filter_username = isset($_GET['username']) ? $_GET['username'] : '';
$filter_city = isset($_GET['city']) ? $_GET['city'] : '';
$filter_role = isset($_GET['role']) ? $_GET['role'] : '';

// Filtreleme uygula
$filtered_users = $users;
if (!empty($filter_username) || !empty($filter_city) || !empty($filter_role)) {
    $filtered_users = array_filter($users, function($user) use ($filter_username, $filter_city, $filter_role) {
        $username_match = empty($filter_username) || (isset($user['username']) && stripos($user['username'], $filter_username) !== false);
        $city_match = empty($filter_city) || (isset($user['city']) && stripos($user['city'], $filter_city) !== false);
        $role_match = empty($filter_role) || (isset($user['role']) && $user['role'] === $filter_role);
        return $username_match && $city_match && $role_match;
    });
}

// Ban verileri
$bans_result = getData('user_bans');
$bans = $bans_result['data'] ?? [];

// Kullanıcı ID'lerine göre ban verileri
$user_bans = [];
foreach ($bans as $ban) {
    if (isset($ban['user_id'])) {
        $user_bans[$ban['user_id']] = $ban;
    }
}

// Kullanıcı silme
if (isset($_POST['delete_user']) && isset($_POST['user_id'])) {
    $user_id = $_POST['user_id'];
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

// Kullanıcı banlama
if (isset($_POST['ban_user']) && isset($_POST['user_id'])) {
    $user_id = $_POST['user_id'];
    $ban_reason = isset($_POST['ban_reason']) ? $_POST['ban_reason'] : '';
    $ban_duration = isset($_POST['ban_duration']) ? intval($_POST['ban_duration']) : 7; // Varsayılan 7 gün
    
    $ban_start = date('Y-m-d H:i:s');
    $ban_end = date('Y-m-d H:i:s', strtotime("+{$ban_duration} days"));
    
    $ban_data = [
        'user_id' => $user_id,
        'banned_by' => $_SESSION['admin_id'] ?? null,
        'reason' => $ban_reason,
        'ban_start' => $ban_start,
        'ban_end' => $ban_end,
        'content_action' => 'none', // Kullanıcının içeriklerine ne yapılacağı (none, hide, delete)
        'is_active' => 'true'
    ];
    
    $ban_result = addData('user_bans', $ban_data);
    
    if (!$ban_result['error']) {
        $_SESSION['message'] = 'Kullanıcı başarıyla banlandı.';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Kullanıcı banlanırken bir hata oluştu: ' . $ban_result['message'];
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

// Ban kaldırma
if (isset($_POST['unban_user']) && isset($_POST['ban_id'])) {
    $ban_id = $_POST['ban_id'];
    
    $ban_data = [
        'is_active' => 'false'
    ];
    
    $update_result = updateData('user_bans', $ban_id, $ban_data);
    
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

// Filtreleme ve arama formu
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Kullanıcı Yönetimi</h1>
    
    <div>
        <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#filterModal">
            <i class="fas fa-filter me-1"></i> Filtrele
        </button>
        
        <a href="index.php?page=dashboard" class="btn btn-secondary ms-2">
            <i class="fas fa-arrow-left me-1"></i> Panele Dön
        </a>
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

<!-- Kullanıcı Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-users me-1"></i> Tüm Kullanıcılar
        <?php if (!empty($filter_username) || !empty($filter_city) || !empty($filter_role)): ?>
            <span class="badge bg-info ms-2">Filtrelendi</span>
        <?php endif; ?>
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-hover" id="usersTable">
                <thead class="table-light">
                    <tr>
                        <th>ID</th>
                        <th>Profil</th>
                        <th>E-posta / Kullanıcı Adı</th>
                        <th>Şehir / İlçe</th>
                        <th>Rol</th>
                        <th>Kayıt Tarihi</th>
                        <th>Durum</th>
                        <th>İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($filtered_users)): ?>
                        <tr>
                            <td colspan="8" class="text-center">Kayıtlı kullanıcı bulunamadı.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach ($filtered_users as $user): ?>
                            <tr>
                                <td><?php echo substr($user['id'], 0, 8) . '...'; ?></td>
                                <td>
                                    <?php if (isset($user['profile_image_url']) && !empty($user['profile_image_url'])): ?>
                                        <img src="<?php echo escape($user['profile_image_url']); ?>" alt="<?php echo escape($user['username']); ?>" class="avatar rounded-circle" style="width: 40px; height: 40px;">
                                    <?php else: ?>
                                        <div class="avatar rounded-circle bg-secondary text-white d-flex align-items-center justify-content-center" style="width: 40px; height: 40px;">
                                            <i class="fas fa-user"></i>
                                        </div>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <strong><?php echo escape($user['username'] ?? 'Belirsiz'); ?></strong><br>
                                    <small class="text-muted"><?php echo escape($user['email'] ?? ''); ?></small>
                                </td>
                                <td>
                                    <?php if (isset($user['city']) && !empty($user['city'])): ?>
                                        <?php echo escape($user['city']); ?>
                                        <?php if (isset($user['district']) && !empty($user['district'])): ?>
                                            / <?php echo escape($user['district']); ?>
                                        <?php endif; ?>
                                    <?php else: ?>
                                        -
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <?php if (isset($user['role'])): ?>
                                        <?php if ($user['role'] === 'admin'): ?>
                                            <span class="badge bg-danger">Yönetici</span>
                                        <?php elseif ($user['role'] === 'moderator'): ?>
                                            <span class="badge bg-warning">Moderatör</span>
                                        <?php else: ?>
                                            <span class="badge bg-secondary">Kullanıcı</span>
                                        <?php endif; ?>
                                    <?php else: ?>
                                        <span class="badge bg-secondary">Kullanıcı</span>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($user['created_at']) ? date('d.m.Y H:i', strtotime($user['created_at'])) : '-'; ?></td>
                                <td>
                                    <?php
                                    // Kullanıcının ban durumunu kontrol et
                                    $is_banned = false;
                                    $active_ban = null;
                                    
                                    if (isset($user_bans[$user['id']])) {
                                        $ban = $user_bans[$user['id']];
                                        if ($ban['is_active'] === 'true' && strtotime($ban['ban_end']) > time()) {
                                            $is_banned = true;
                                            $active_ban = $ban;
                                        }
                                    }
                                    
                                    if ($is_banned):
                                    ?>
                                        <span class="badge bg-danger">Banlı</span>
                                        <small class="d-block text-muted"><?php echo date('d.m.Y', strtotime($active_ban['ban_end'])); ?>'e kadar</small>
                                    <?php else: ?>
                                        <span class="badge bg-success">Aktif</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <div class="dropdown">
                                        <button class="btn btn-sm btn-outline-secondary dropdown-toggle" type="button" id="dropdownMenuButton1" data-bs-toggle="dropdown" aria-expanded="false">
                                            İşlemler
                                        </button>
                                        <ul class="dropdown-menu" aria-labelledby="dropdownMenuButton1">
                                            <li>
                                                <a class="dropdown-item" href="javascript:void(0)" onclick="viewUserPosts('<?php echo $user['id']; ?>')">
                                                    <i class="fas fa-clipboard-list me-1"></i> Gönderilerini Görüntüle
                                                </a>
                                            </li>
                                            <li>
                                                <a class="dropdown-item" href="javascript:void(0)" onclick="viewUserComments('<?php echo $user['id']; ?>')">
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
                                                        <i class="fas fa-ban me-1"></i> Banla
                                                    </button>
                                                </li>
                                            <?php endif; ?>
                                            <li>
                                                <button class="dropdown-item text-danger" type="button" data-bs-toggle="modal" data-bs-target="#deleteModal" 
                                                        data-user-id="<?php echo $user['id']; ?>" 
                                                        data-username="<?php echo escape($user['username']); ?>">
                                                    <i class="fas fa-trash me-1"></i> Sil
                                                </button>
                                            </li>
                                        </ul>
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

<!-- Filtre Modal -->
<div class="modal fade" id="filterModal" tabindex="-1" aria-labelledby="filterModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <form action="index.php" method="get">
                <input type="hidden" name="page" value="users">
                
                <div class="modal-header">
                    <h5 class="modal-title" id="filterModalLabel">Kullanıcıları Filtrele</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
                </div>
                <div class="modal-body">
                    <div class="mb-3">
                        <label for="username" class="form-label">Kullanıcı Adı</label>
                        <input type="text" class="form-control" id="username" name="username" value="<?php echo escape($filter_username); ?>" placeholder="Kullanıcı adı ara...">
                    </div>
                    <div class="mb-3">
                        <label for="city" class="form-label">Şehir</label>
                        <input type="text" class="form-control" id="city" name="city" value="<?php echo escape($filter_city); ?>" placeholder="Şehir ara...">
                    </div>
                    <div class="mb-3">
                        <label for="role" class="form-label">Rol</label>
                        <select class="form-select" id="role" name="role">
                            <option value="">Tümü</option>
                            <option value="admin" <?php echo $filter_role === 'admin' ? 'selected' : ''; ?>>Yönetici</option>
                            <option value="moderator" <?php echo $filter_role === 'moderator' ? 'selected' : ''; ?>>Moderatör</option>
                            <option value="user" <?php echo $filter_role === 'user' ? 'selected' : ''; ?>>Kullanıcı</option>
                        </select>
                    </div>
                </div>
                <div class="modal-footer">
                    <a href="index.php?page=users" class="btn btn-secondary">Filtreleri Temizle</a>
                    <button type="submit" class="btn btn-primary">Filtrele</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Ban Modal -->
<div class="modal fade" id="banModal" tabindex="-1" aria-labelledby="banModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <form action="" method="post">
                <input type="hidden" name="user_id" id="banUserId">
                <input type="hidden" name="ban_user" value="1">
                
                <div class="modal-header">
                    <h5 class="modal-title" id="banModalLabel">Kullanıcıyı Banla</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
                </div>
                <div class="modal-body">
                    <p>
                        <span id="banUsername"></span> kullanıcısını banlamak istediğinize emin misiniz?
                    </p>
                    <div class="mb-3">
                        <label for="ban_reason" class="form-label">Ban Nedeni</label>
                        <textarea class="form-control" id="ban_reason" name="ban_reason" rows="3" placeholder="Ban nedeni..."></textarea>
                    </div>
                    <div class="mb-3">
                        <label for="ban_duration" class="form-label">Ban Süresi (Gün)</label>
                        <select class="form-select" id="ban_duration" name="ban_duration">
                            <option value="1">1 Gün</option>
                            <option value="3">3 Gün</option>
                            <option value="7" selected>7 Gün</option>
                            <option value="15">15 Gün</option>
                            <option value="30">30 Gün</option>
                            <option value="90">90 Gün</option>
                            <option value="365">1 Yıl</option>
                        </select>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <button type="submit" class="btn btn-danger">Banla</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Unban Modal -->
<div class="modal fade" id="unbanModal" tabindex="-1" aria-labelledby="unbanModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <form action="" method="post">
                <input type="hidden" name="ban_id" id="unbanBanId">
                <input type="hidden" name="unban_user" value="1">
                
                <div class="modal-header">
                    <h5 class="modal-title" id="unbanModalLabel">Ban Kaldır</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
                </div>
                <div class="modal-body">
                    <p>
                        <span id="unbanUsername"></span> kullanıcısının banını kaldırmak istediğinize emin misiniz?
                    </p>
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
            <form action="" method="post">
                <input type="hidden" name="user_id" id="deleteUserId">
                <input type="hidden" name="delete_user" value="1">
                
                <div class="modal-header">
                    <h5 class="modal-title" id="deleteModalLabel">Kullanıcıyı Sil</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
                </div>
                <div class="modal-body">
                    <div class="alert alert-danger">
                        <i class="fas fa-exclamation-triangle me-1"></i> Dikkat: Bu işlem geri alınamaz!
                    </div>
                    <p>
                        <span id="deleteUsername"></span> kullanıcısını silmek istediğinize emin misiniz?
                    </p>
                    <p>
                        Bu işlem sonucunda kullanıcının tüm verileri sistemden silinecektir. Bu işlemi geri alamazsınız.
                    </p>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <button type="submit" class="btn btn-danger">Evet, Sil</button>
                </div>
            </form>
        </div>
    </div>
</div>

<script>
// Ban Modalı
document.getElementById('banModal').addEventListener('show.bs.modal', function (event) {
    const button = event.relatedTarget;
    const userId = button.getAttribute('data-user-id');
    const username = button.getAttribute('data-username');
    
    document.getElementById('banUserId').value = userId;
    document.getElementById('banUsername').textContent = username;
});

// Unban Modalı
document.getElementById('unbanModal').addEventListener('show.bs.modal', function (event) {
    const button = event.relatedTarget;
    const banId = button.getAttribute('data-ban-id');
    const username = button.getAttribute('data-username');
    
    document.getElementById('unbanBanId').value = banId;
    document.getElementById('unbanUsername').textContent = username;
});

// Silme Modalı
document.getElementById('deleteModal').addEventListener('show.bs.modal', function (event) {
    const button = event.relatedTarget;
    const userId = button.getAttribute('data-user-id');
    const username = button.getAttribute('data-username');
    
    document.getElementById('deleteUserId').value = userId;
    document.getElementById('deleteUsername').textContent = username;
});

// Kullanıcı gönderilerini görüntüle
function viewUserPosts(userId) {
    window.location.href = 'index.php?page=posts&user_id=' + userId;
}

// Kullanıcı yorumlarını görüntüle
function viewUserComments(userId) {
    window.location.href = 'index.php?page=comments&user_id=' + userId;
}

// DataTables eklentisini etkinleştir
document.addEventListener('DOMContentLoaded', function() {
    if (typeof $.fn.DataTable !== 'undefined') {
        $('#usersTable').DataTable({
            language: {
                url: '//cdn.datatables.net/plug-ins/1.10.21/i18n/Turkish.json'
            },
            order: [[5, 'desc']]
        });
    }
});
</script>