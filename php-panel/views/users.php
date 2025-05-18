<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');
// Kullanıcı verilerini al
$users_result = getData('users');
$users = $users_result['data'];

// Şehir verilerini al (dropdown için)
$cities_result = getData('cities');
$cities = $cities_result['data'];

// Yeni kullanıcı ekle formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['add_user'])) {
    // Form verilerini al
    $username = trim($_POST['username'] ?? '');
    $email = trim($_POST['email'] ?? '');
    $city = trim($_POST['city'] ?? '');
    $district = trim($_POST['district'] ?? '');
    $profile_image_url = trim($_POST['profile_image_url'] ?? '');
    $phone_number = trim($_POST['phone_number'] ?? '');
    $role = trim($_POST['role'] ?? 'user');
    
    // Basit doğrulama
    $errors = [];
    if (empty($username)) {
        $errors[] = 'Kullanıcı adı gereklidir';
    }
    if (empty($email)) {
        $errors[] = 'E-posta adresi gereklidir';
    }
    
    // E-posta formatı kontrol
    if (!empty($email) && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $errors[] = 'Geçerli bir e-posta adresi giriniz';
    }
    
    // Hata yoksa kullanıcıyı ekle
    if (empty($errors)) {
        $new_user = [
            'username' => $username,
            'email' => $email,
            'city' => $city,
            'district' => $district,
            'profile_image_url' => $profile_image_url,
            'phone_number' => $phone_number,
            'role' => $role,
            'created_at' => date('Y-m-d H:i:s')
        ];
        
        $response = addData('users', $new_user);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Kullanıcı başarıyla eklendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile (formun tekrar gönderilmesini önlemek için)
            if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
        } else {
            $_SESSION['message'] = 'Kullanıcı eklenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// Kullanıcı sil
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $user_id = $_GET['delete'];
    $response = deleteData('users', $user_id);
    
    if (!$response['error']) {
        $_SESSION['message'] = 'Kullanıcı başarıyla silindi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Kullanıcı silinirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
}

// Kullanıcı banla
if (isset($_GET['ban']) && !empty($_GET['ban'])) {
    $user_id = $_GET['ban'];
    
    // Ban formu gönderildiyse
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['submit_ban'])) {
        $reason = trim($_POST['reason'] ?? '');
        $ban_start = $_POST['ban_start'] ?? date('Y-m-d H:i:s');
        $ban_end = $_POST['ban_end'] ?? date('Y-m-d H:i:s', strtotime('+7 days'));
        $content_action = $_POST['content_action'] ?? 'none';
        
        $ban_data = [
            'user_id' => $user_id,
            'banned_by' => $_SESSION['user_id'] ?? 'admin-01',  // Varsayılan admin ID
            'reason' => $reason,
            'ban_start' => $ban_start,
            'ban_end' => $ban_end,
            'content_action' => $content_action,
            'is_active' => 'true',
            'created_at' => date('Y-m-d H:i:s')
        ];
        
        $response = addData('user_bans', $ban_data);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Kullanıcı başarıyla yasaklandı';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile
            if (!headers_sent()) {
        header('Location: index.php?page=users');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=users";</script>';
        exit;
    }
        } else {
            $_SESSION['message'] = 'Kullanıcı yasaklanırken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
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
    <h1 class="h3">Kullanıcı Yönetimi</h1>
    
    <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addUserModal">
        <i class="fas fa-user-plus me-1"></i> Yeni Kullanıcı Ekle
    </button>
</div>

<!-- Kullanıcılar Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-users me-1"></i>
        Kullanıcılar Listesi
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-striped table-hover">
                <thead>
                    <tr>
                        <th style="width: 60px;">Avatar</th>
                        <th>Kullanıcı Adı</th>
                        <th>E-posta</th>
                        <th>Rol</th>
                        <th>Şehir/İlçe</th>
                        <th>Telefon</th>
                        <th>Kayıt Tarihi</th>
                        <th style="width: 180px;">İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if(empty($users)): ?>
                        <tr>
                            <td colspan="8" class="text-center">Henüz kullanıcı kaydı bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($users as $user): ?>
                            <tr>
                                <td class="text-center">
                                    <?php if(isset($user['profile_image_url']) && !empty($user['profile_image_url'])): ?>
                                        <img src="<?php echo $user['profile_image_url']; ?>" alt="<?php echo isset($user['username']) ? $user['username'] : ''; ?> Avatar" width="40" height="40" class="rounded-circle">
                                    <?php else: ?>
                                        <i class="fas fa-user-circle fa-2x text-secondary"></i>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($user['username']) ? escape($user['username']) : ''; ?></td>
                                <td><?php echo isset($user['email']) ? escape($user['email']) : ''; ?></td>
                                <td>
                                    <?php 
                                    if(isset($user['role'])) {
                                        $role_class = 'secondary';
                                        $role_text = $user['role'];
                                        
                                        switch($user['role']) {
                                            case 'admin':
                                                $role_class = 'danger';
                                                $role_text = 'Yönetici';
                                                break;
                                            case 'moderator':
                                                $role_class = 'warning';
                                                $role_text = 'Moderatör';
                                                break;
                                            case 'user':
                                                $role_class = 'primary';
                                                $role_text = 'Kullanıcı';
                                                break;
                                        }
                                        
                                        echo '<span class="badge bg-' . $role_class . '">' . $role_text . '</span>';
                                    }
                                    ?>
                                </td>
                                <td>
                                    <?php 
                                    $location = [];
                                    if(isset($user['city']) && !empty($user['city'])) {
                                        $location[] = $user['city'];
                                    }
                                    if(isset($user['district']) && !empty($user['district'])) {
                                        $location[] = $user['district'];
                                    }
                                    echo !empty($location) ? escape(implode(', ', $location)) : '';
                                    ?>
                                </td>
                                <td><?php echo isset($user['phone_number']) ? escape($user['phone_number']) : ''; ?></td>
                                <td>
                                    <?php 
                                    if(isset($user['created_at'])) {
                                        echo formatDate($user['created_at'], 'd.m.Y H:i');
                                    }
                                    ?>
                                </td>
                                <td>
                                    <div class="btn-group btn-group-sm">
                                        <a href="index.php?page=user_detail&id=<?php echo $user['id']; ?>" class="btn btn-info" title="Görüntüle">
                                            <i class="fas fa-eye"></i>
                                        </a>
                                        <a href="index.php?page=user_edit&id=<?php echo $user['id']; ?>" class="btn btn-warning" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <a href="javascript:void(0);" class="btn btn-danger" 
                                           onclick="if(confirm('Bu kullanıcıyı silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=users&delete=<?php echo $user['id']; ?>';" 
                                           title="Sil">
                                            <i class="fas fa-trash"></i>
                                        </a>
                                        <a href="javascript:void(0);" class="btn btn-dark" 
                                           data-bs-toggle="modal" data-bs-target="#banUserModal" 
                                           data-user-id="<?php echo $user['id']; ?>"
                                           data-username="<?php echo $user['username']; ?>"
                                           title="Yasakla">
                                            <i class="fas fa-ban"></i>
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

<!-- Yeni Kullanıcı Ekle Modal -->
<div class="modal fade" id="addUserModal" tabindex="-1" aria-labelledby="addUserModalLabel" aria-hidden="true">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="addUserModalLabel">Yeni Kullanıcı Ekle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="post" action="index.php?page=users">
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="username" class="form-label">Kullanıcı Adı <span class="text-danger">*</span></label>
                            <input type="text" class="form-control" id="username" name="username" required>
                        </div>
                        <div class="col-md-6">
                            <label for="email" class="form-label">E-posta <span class="text-danger">*</span></label>
                            <input type="email" class="form-control" id="email" name="email" required>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="city" class="form-label">Şehir</label>
                            <select class="form-select" id="city" name="city">
                                <option value="">Seçiniz</option>
                                <?php foreach($cities as $city): ?>
                                    <option value="<?php echo $city['name']; ?>"><?php echo $city['name']; ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        <div class="col-md-6">
                            <label for="district" class="form-label">İlçe</label>
                            <input type="text" class="form-control" id="district" name="district">
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="phone_number" class="form-label">Telefon</label>
                            <input type="text" class="form-control" id="phone_number" name="phone_number">
                        </div>
                        <div class="col-md-6">
                            <label for="role" class="form-label">Rol</label>
                            <select class="form-select" id="role" name="role">
                                <option value="user">Kullanıcı</option>
                                <option value="moderator">Moderatör</option>
                                <option value="admin">Yönetici</option>
                            </select>
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label for="profile_image_url" class="form-label">Profil Resmi URL</label>
                        <input type="url" class="form-control" id="profile_image_url" name="profile_image_url">
                    </div>
                    
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                        <button type="submit" name="add_user" class="btn btn-primary">Kaydet</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- Kullanıcı Yasaklama Modal -->
<div class="modal fade" id="banUserModal" tabindex="-1" aria-labelledby="banUserModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header bg-dark text-white">
                <h5 class="modal-title" id="banUserModalLabel">Kullanıcı Yasakla</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <p>Bu işlem, kullanıcının platforma erişimini engelleyecektir.</p>
                <form method="post" id="banUserForm" action="index.php?page=users&ban=USER_ID">
                    <div class="mb-3">
                        <label for="reason" class="form-label">Yasaklama Sebebi</label>
                        <textarea class="form-control" id="reason" name="reason" rows="3"></textarea>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="ban_start" class="form-label">Başlangıç Tarihi</label>
                            <input type="datetime-local" class="form-control" id="ban_start" name="ban_start" value="<?php echo date('Y-m-d\TH:i'); ?>">
                        </div>
                        <div class="col-md-6">
                            <label for="ban_end" class="form-label">Bitiş Tarihi</label>
                            <input type="datetime-local" class="form-control" id="ban_end" name="ban_end" value="<?php echo date('Y-m-d\TH:i', strtotime('+7 days')); ?>">
                        </div>
                    </div>
                    
                    <div class="mb-3">
                        <label for="content_action" class="form-label">İçerik Yönetimi</label>
                        <select class="form-select" id="content_action" name="content_action">
                            <option value="none">İçeriklere Dokunma</option>
                            <option value="hide">İçerikleri Gizle</option>
                            <option value="delete">İçerikleri Sil</option>
                        </select>
                    </div>
                    
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                        <button type="submit" name="submit_ban" class="btn btn-danger">Yasakla</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>

<script>
// Ban modalı için kullanıcı ID'sini ayarla
document.addEventListener('DOMContentLoaded', function() {
    const banUserModal = document.getElementById('banUserModal');
    if (banUserModal) {
        banUserModal.addEventListener('show.bs.modal', function (event) {
            const button = event.relatedTarget;
            const userId = button.getAttribute('data-user-id');
            const username = button.getAttribute('data-username');
            
            const form = document.getElementById('banUserForm');
            form.action = `index.php?page=users&ban=${userId}`;
            
            const modalTitle = banUserModal.querySelector('.modal-title');
            modalTitle.textContent = `Kullanıcı Yasakla: ${username || 'Kullanıcı'}`;
        });
    }
});
</script>