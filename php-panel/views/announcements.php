<?php
// Belediye duyurularını al
$announcements_result = getData('municipality_announcements');
$announcements = $announcements_result['data'];

// Belediye listesini al (dropdown için)
$cities_result = getData('cities');
$cities = $cities_result['data'];

// Yeni duyuru ekle formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['add_announcement'])) {
    // Form verilerini al
    $municipality_id = trim($_POST['municipality_id'] ?? '');
    $title = trim($_POST['title'] ?? '');
    $content = trim($_POST['content'] ?? '');
    $image_url = trim($_POST['image_url'] ?? '');
    $is_active = isset($_POST['is_active']) ? 'true' : 'false';
    
    // Basit doğrulama
    $errors = [];
    if (empty($municipality_id)) {
        $errors[] = 'Belediye seçilmelidir';
    }
    if (empty($title)) {
        $errors[] = 'Başlık gereklidir';
    }
    if (empty($content)) {
        $errors[] = 'İçerik gereklidir';
    }
    
    // Hata yoksa duyuruyu ekle
    if (empty($errors)) {
        $new_announcement = [
            'municipality_id' => $municipality_id,
            'title' => $title,
            'content' => $content,
            'image_url' => $image_url,
            'is_active' => $is_active,
            'created_at' => date('Y-m-d H:i:s'),
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        $response = addData('municipality_announcements', $new_announcement);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Duyuru başarıyla eklendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile
            header('Location: index.php?page=announcements');
            exit;
        } else {
            $_SESSION['message'] = 'Duyuru eklenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// Duyuru güncelleme formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_announcement'])) {
    $announcement_id = $_POST['announcement_id'] ?? '';
    $municipality_id = trim($_POST['municipality_id'] ?? '');
    $title = trim($_POST['title'] ?? '');
    $content = trim($_POST['content'] ?? '');
    $image_url = trim($_POST['image_url'] ?? '');
    $is_active = isset($_POST['is_active']) ? 'true' : 'false';
    
    // Basit doğrulama
    $errors = [];
    if (empty($municipality_id)) {
        $errors[] = 'Belediye seçilmelidir';
    }
    if (empty($title)) {
        $errors[] = 'Başlık gereklidir';
    }
    if (empty($content)) {
        $errors[] = 'İçerik gereklidir';
    }
    
    // Hata yoksa duyuruyu güncelle
    if (empty($errors)) {
        $update_data = [
            'municipality_id' => $municipality_id,
            'title' => $title,
            'content' => $content,
            'image_url' => $image_url,
            'is_active' => $is_active,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        $response = updateData('municipality_announcements', $announcement_id, $update_data);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Duyuru başarıyla güncellendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile
            header('Location: index.php?page=announcements');
            exit;
        } else {
            $_SESSION['message'] = 'Duyuru güncellenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// Duyuru sil
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $announcement_id = $_GET['delete'];
    $response = deleteData('municipality_announcements', $announcement_id);
    
    if (!$response['error']) {
        $_SESSION['message'] = 'Duyuru başarıyla silindi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Duyuru silinirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    header('Location: index.php?page=announcements');
    exit;
}

// Duyuru durumunu değiştir (aktif/pasif)
if (isset($_GET['toggle']) && !empty($_GET['toggle'])) {
    $announcement_id = $_GET['toggle'];
    
    // Mevcut durumu bul
    $is_active = false;
    foreach ($announcements as $a) {
        if ($a['id'] === $announcement_id) {
            $is_active = isset($a['is_active']) && $a['is_active'] === 'true';
            break;
        }
    }
    
    // Durumu tersine çevir
    $update_data = [
        'is_active' => $is_active ? 'false' : 'true',
        'updated_at' => date('Y-m-d H:i:s')
    ];
    
    $response = updateData('municipality_announcements', $announcement_id, $update_data);
    
    if (!$response['error']) {
        $_SESSION['message'] = $is_active ? 'Duyuru pasif hale getirildi' : 'Duyuru aktif hale getirildi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Duyuru durumu güncellenirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    header('Location: index.php?page=announcements');
    exit;
}

// Duyuru detayları için ID kontrolü
$edit_announcement = null;
if (isset($_GET['edit']) && !empty($_GET['edit'])) {
    $announcement_id = $_GET['edit'];
    
    // Duyuruları tara ve ID'ye göre duyuru detaylarını bul
    foreach ($announcements as $announcement) {
        if ($announcement['id'] === $announcement_id) {
            $edit_announcement = $announcement;
            break;
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
    <h1 class="h3">Belediye Duyuruları Yönetimi</h1>
    
    <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addAnnouncementModal">
        <i class="fas fa-plus me-1"></i> Yeni Duyuru Ekle
    </button>
</div>

<!-- Duyurular Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-bullhorn me-1"></i>
        Belediye Duyuruları Listesi
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-striped table-hover">
                <thead>
                    <tr>
                        <th>Belediye</th>
                        <th>Başlık</th>
                        <th>İçerik Önizleme</th>
                        <th>Görsel</th>
                        <th>Durum</th>
                        <th>Tarih</th>
                        <th style="width: 150px;">İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if(empty($announcements)): ?>
                        <tr>
                            <td colspan="7" class="text-center">Henüz duyuru kaydı bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($announcements as $announcement): ?>
                            <?php 
                            // Belediye adını bul
                            $municipality_name = 'Bilinmeyen Belediye';
                            foreach($cities as $city) {
                                if($city['id'] === $announcement['municipality_id']) {
                                    $municipality_name = $city['name'] . ' Belediyesi';
                                    break;
                                }
                            }
                            
                            // İçerik önizleme (kısaltılmış)
                            $content_preview = isset($announcement['content']) ? mb_substr(strip_tags($announcement['content']), 0, 100) . (mb_strlen($announcement['content']) > 100 ? '...' : '') : '';
                            
                            // Durum
                            $is_active = isset($announcement['is_active']) && $announcement['is_active'] === 'true';
                            ?>
                            <tr>
                                <td><?php echo escape($municipality_name); ?></td>
                                <td><?php echo isset($announcement['title']) ? escape($announcement['title']) : ''; ?></td>
                                <td><?php echo escape($content_preview); ?></td>
                                <td class="text-center">
                                    <?php if(isset($announcement['image_url']) && !empty($announcement['image_url'])): ?>
                                        <img src="<?php echo $announcement['image_url']; ?>" alt="Duyuru Görseli" width="80" class="img-thumbnail">
                                    <?php else: ?>
                                        <span class="text-muted">Görsel yok</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <span class="badge bg-<?php echo $is_active ? 'success' : 'secondary'; ?>">
                                        <?php echo $is_active ? 'Aktif' : 'Pasif'; ?>
                                    </span>
                                </td>
                                <td>
                                    <?php if(isset($announcement['created_at'])): ?>
                                        <div>Oluşturma: <?php echo formatDate($announcement['created_at'], 'd.m.Y H:i'); ?></div>
                                    <?php endif; ?>
                                    <?php if(isset($announcement['updated_at'])): ?>
                                        <div>Güncelleme: <?php echo formatDate($announcement['updated_at'], 'd.m.Y H:i'); ?></div>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <div class="btn-group btn-group-sm">
                                        <a href="index.php?page=announcements&edit=<?php echo $announcement['id']; ?>" class="btn btn-warning" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <a href="index.php?page=announcements&toggle=<?php echo $announcement['id']; ?>" class="btn btn-<?php echo $is_active ? 'secondary' : 'success'; ?>" title="<?php echo $is_active ? 'Pasif Yap' : 'Aktif Yap'; ?>">
                                            <i class="fas <?php echo $is_active ? 'fa-toggle-off' : 'fa-toggle-on'; ?>"></i>
                                        </a>
                                        <a href="javascript:void(0);" class="btn btn-danger" 
                                           onclick="if(confirm('Bu duyuruyu silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=announcements&delete=<?php echo $announcement['id']; ?>';" 
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

<!-- Duyuru Düzenleme Kartı (Edit modu açıksa) -->
<?php if($edit_announcement): ?>
<div class="card mb-4">
    <div class="card-header bg-warning text-dark">
        <i class="fas fa-edit me-1"></i>
        Duyuru Düzenle: "<?php echo escape($edit_announcement['title']); ?>"
    </div>
    <div class="card-body">
        <form method="post" action="index.php?page=announcements">
            <input type="hidden" name="announcement_id" value="<?php echo $edit_announcement['id']; ?>">
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="municipality_id" class="form-label">Belediye <span class="text-danger">*</span></label>
                    <select class="form-select" id="municipality_id" name="municipality_id" required>
                        <option value="">Seçiniz</option>
                        <?php foreach($cities as $city): ?>
                            <option value="<?php echo $city['id']; ?>" <?php echo $edit_announcement['municipality_id'] === $city['id'] ? 'selected' : ''; ?>>
                                <?php echo $city['name']; ?> Belediyesi
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="col-md-6">
                    <label for="is_active" class="form-label">Durum</label>
                    <div class="form-check form-switch mt-2">
                        <input class="form-check-input" type="checkbox" id="is_active" name="is_active" <?php echo (isset($edit_announcement['is_active']) && $edit_announcement['is_active'] === 'true') ? 'checked' : ''; ?>>
                        <label class="form-check-label" for="is_active">Aktif</label>
                    </div>
                </div>
            </div>
            
            <div class="mb-3">
                <label for="title" class="form-label">Başlık <span class="text-danger">*</span></label>
                <input type="text" class="form-control" id="title" name="title" value="<?php echo $edit_announcement['title']; ?>" required>
            </div>
            
            <div class="mb-3">
                <label for="content" class="form-label">İçerik <span class="text-danger">*</span></label>
                <textarea class="form-control" id="content" name="content" rows="5" required><?php echo $edit_announcement['content']; ?></textarea>
            </div>
            
            <div class="mb-3">
                <label for="image_url" class="form-label">Görsel URL</label>
                <input type="url" class="form-control" id="image_url" name="image_url" value="<?php echo $edit_announcement['image_url'] ?? ''; ?>">
                <?php if(isset($edit_announcement['image_url']) && !empty($edit_announcement['image_url'])): ?>
                    <div class="mt-2">
                        <img src="<?php echo $edit_announcement['image_url']; ?>" alt="Görsel Önizleme" class="img-thumbnail" style="max-height: 150px;">
                    </div>
                <?php endif; ?>
            </div>
            
            <div class="d-flex justify-content-between">
                <a href="index.php?page=announcements" class="btn btn-secondary">İptal</a>
                <button type="submit" name="update_announcement" class="btn btn-primary">Güncelle</button>
            </div>
        </form>
    </div>
</div>
<?php endif; ?>

<!-- Yeni Duyuru Ekle Modal -->
<div class="modal fade" id="addAnnouncementModal" tabindex="-1" aria-labelledby="addAnnouncementModalLabel" aria-hidden="true">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="addAnnouncementModalLabel">Yeni Belediye Duyurusu Ekle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="post" action="index.php?page=announcements">
                    <div class="mb-3">
                        <label for="municipality_id" class="form-label">Belediye <span class="text-danger">*</span></label>
                        <select class="form-select" id="municipality_id" name="municipality_id" required>
                            <option value="">Seçiniz</option>
                            <?php foreach($cities as $city): ?>
                                <option value="<?php echo $city['id']; ?>"><?php echo $city['name']; ?> Belediyesi</option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="title" class="form-label">Başlık <span class="text-danger">*</span></label>
                        <input type="text" class="form-control" id="title" name="title" required>
                    </div>
                    
                    <div class="mb-3">
                        <label for="content" class="form-label">İçerik <span class="text-danger">*</span></label>
                        <textarea class="form-control" id="content" name="content" rows="5" required></textarea>
                    </div>
                    
                    <div class="mb-3">
                        <label for="image_url" class="form-label">Görsel URL</label>
                        <input type="url" class="form-control" id="image_url" name="image_url">
                    </div>
                    
                    <div class="mb-3">
                        <div class="form-check form-switch">
                            <input class="form-check-input" type="checkbox" id="is_active" name="is_active" checked>
                            <label class="form-check-label" for="is_active">Aktif</label>
                        </div>
                    </div>
                    
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                        <button type="submit" name="add_announcement" class="btn btn-primary">Kaydet</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>