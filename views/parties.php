<?php
// Siyasi partiler verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'];

// Yeni parti ekle formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['add_party'])) {
    // Form verilerini al
    $name = trim($_POST['name'] ?? '');
    $logo_url = trim($_POST['logo_url'] ?? '');
    $score = trim($_POST['score'] ?? '0');
    
    // Basit doğrulama
    $errors = [];
    if (empty($name)) {
        $errors[] = 'Parti adı gereklidir';
    }
    
    // Skor geçerli bir sayı olmalı (0-10 arası)
    if (!empty($score) && (!is_numeric($score) || $score < 0 || $score > 10)) {
        $errors[] = 'Skor 0 ile 10 arasında bir sayı olmalıdır';
    }
    
    // Hata yoksa partiyi ekle
    if (empty($errors)) {
        $new_party = [
            'name' => $name,
            'logo_url' => $logo_url,
            'score' => $score,
            'created_at' => date('Y-m-d H:i:s'),
            'last_updated' => date('Y-m-d H:i:s')
        ];
        
        $response = addData('political_parties', $new_party);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Siyasi parti başarıyla eklendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile (formun tekrar gönderilmesini önlemek için)
            header('Location: index.php?page=parties');
            exit;
        } else {
            $_SESSION['message'] = 'Parti eklenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// Parti güncelleme formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_party'])) {
    $party_id = $_POST['party_id'] ?? '';
    $name = trim($_POST['name'] ?? '');
    $logo_url = trim($_POST['logo_url'] ?? '');
    $score = trim($_POST['score'] ?? '0');
    
    // Basit doğrulama
    $errors = [];
    if (empty($name)) {
        $errors[] = 'Parti adı gereklidir';
    }
    
    // Skor geçerli bir sayı olmalı (0-10 arası)
    if (!empty($score) && (!is_numeric($score) || $score < 0 || $score > 10)) {
        $errors[] = 'Skor 0 ile 10 arasında bir sayı olmalıdır';
    }
    
    // Hata yoksa partiyi güncelle
    if (empty($errors)) {
        $update_data = [
            'name' => $name,
            'logo_url' => $logo_url,
            'score' => $score,
            'last_updated' => date('Y-m-d H:i:s')
        ];
        
        $response = updateData('political_parties', $party_id, $update_data);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Siyasi parti başarıyla güncellendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile
            header('Location: index.php?page=parties');
            exit;
        } else {
            $_SESSION['message'] = 'Parti güncellenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// Parti sil
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $party_id = $_GET['delete'];
    $response = deleteData('political_parties', $party_id);
    
    if (!$response['error']) {
        $_SESSION['message'] = 'Siyasi parti başarıyla silindi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Parti silinirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    header('Location: index.php?page=parties');
    exit;
}

// Parti detayları için ID kontrolü
$edit_party = null;
if (isset($_GET['edit']) && !empty($_GET['edit'])) {
    $party_id = $_GET['edit'];
    
    // Partileri tara ve ID'ye göre parti detaylarını bul
    foreach ($parties as $party) {
        if ($party['id'] === $party_id) {
            $edit_party = $party;
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
    <h1 class="h3">Siyasi Partiler Yönetimi</h1>
    
    <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addPartyModal">
        <i class="fas fa-plus me-1"></i> Yeni Parti Ekle
    </button>
</div>

<!-- Partiler Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-flag me-1"></i>
        Siyasi Partiler Listesi
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-striped table-hover">
                <thead>
                    <tr>
                        <th style="width: 80px;">Logo</th>
                        <th>Parti Adı</th>
                        <th>Değerlendirme Puanı</th>
                        <th>Son Güncelleme</th>
                        <th style="width: 150px;">İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if(empty($parties)): ?>
                        <tr>
                            <td colspan="5" class="text-center">Henüz parti kaydı bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($parties as $party): ?>
                            <tr>
                                <td class="text-center">
                                    <?php if(isset($party['logo_url']) && !empty($party['logo_url'])): ?>
                                        <img src="<?php echo $party['logo_url']; ?>" alt="<?php echo isset($party['name']) ? $party['name'] : ''; ?> Logo" width="50" height="50" class="img-thumbnail">
                                    <?php else: ?>
                                        <i class="fas fa-flag fa-2x text-secondary"></i>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($party['name']) ? escape($party['name']) : ''; ?></td>
                                <td>
                                    <?php 
                                    if(isset($party['score']) && is_numeric($party['score'])) {
                                        $score = floatval($party['score']);
                                        $score_class = 'primary';
                                        
                                        if($score >= 7) {
                                            $score_class = 'success';
                                        } elseif($score >= 4) {
                                            $score_class = 'warning';
                                        } elseif($score > 0) {
                                            $score_class = 'danger';
                                        }
                                        
                                        echo '<div class="progress" title="' . $score . ' / 10">';
                                        echo '<div class="progress-bar bg-' . $score_class . '" role="progressbar" style="width: ' . ($score * 10) . '%">';
                                        echo $score . ' / 10';
                                        echo '</div>';
                                        echo '</div>';
                                    } else {
                                        echo 'Değerlendirilmemiş';
                                    }
                                    ?>
                                </td>
                                <td>
                                    <?php 
                                    if(isset($party['last_updated'])) {
                                        echo formatDate($party['last_updated'], 'd.m.Y H:i');
                                    } elseif(isset($party['created_at'])) {
                                        echo formatDate($party['created_at'], 'd.m.Y H:i');
                                    } else {
                                        echo '-';
                                    }
                                    ?>
                                </td>
                                <td>
                                    <div class="btn-group btn-group-sm">
                                        <a href="index.php?page=parties&edit=<?php echo $party['id']; ?>" class="btn btn-warning" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <a href="javascript:void(0);" class="btn btn-danger" 
                                           onclick="if(confirm('Bu siyasi partiyi silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=parties&delete=<?php echo $party['id']; ?>';" 
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

<!-- Parti Düzenleme Kartı (Edit modu açıksa) -->
<?php if($edit_party): ?>
<div class="card mb-4">
    <div class="card-header bg-warning text-dark">
        <i class="fas fa-edit me-1"></i>
        "<?php echo escape($edit_party['name']); ?>" Partisini Düzenle
    </div>
    <div class="card-body">
        <form method="post" action="index.php?page=parties">
            <input type="hidden" name="party_id" value="<?php echo $edit_party['id']; ?>">
            
            <div class="row mb-3">
                <div class="col-md-6">
                    <label for="name" class="form-label">Parti Adı <span class="text-danger">*</span></label>
                    <input type="text" class="form-control" id="name" name="name" value="<?php echo $edit_party['name']; ?>" required>
                </div>
                <div class="col-md-6">
                    <label for="score" class="form-label">Değerlendirme Puanı (0-10)</label>
                    <input type="number" class="form-control" id="score" name="score" min="0" max="10" step="0.1" value="<?php echo $edit_party['score'] ?? 0; ?>">
                </div>
            </div>
            
            <div class="mb-3">
                <label for="logo_url" class="form-label">Logo URL</label>
                <input type="url" class="form-control" id="logo_url" name="logo_url" value="<?php echo $edit_party['logo_url'] ?? ''; ?>">
                <?php if(isset($edit_party['logo_url']) && !empty($edit_party['logo_url'])): ?>
                    <div class="mt-2">
                        <img src="<?php echo $edit_party['logo_url']; ?>" alt="Logo Önizleme" class="img-thumbnail" style="max-height: 100px;">
                    </div>
                <?php endif; ?>
            </div>
            
            <div class="d-flex justify-content-between">
                <a href="index.php?page=parties" class="btn btn-secondary">İptal</a>
                <button type="submit" name="update_party" class="btn btn-primary">Güncelle</button>
            </div>
        </form>
    </div>
</div>
<?php endif; ?>

<!-- Yeni Parti Ekle Modal -->
<div class="modal fade" id="addPartyModal" tabindex="-1" aria-labelledby="addPartyModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="addPartyModalLabel">Yeni Siyasi Parti Ekle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="post" action="index.php?page=parties">
                    <div class="mb-3">
                        <label for="name" class="form-label">Parti Adı <span class="text-danger">*</span></label>
                        <input type="text" class="form-control" id="name" name="name" required>
                    </div>
                    
                    <div class="mb-3">
                        <label for="logo_url" class="form-label">Logo URL</label>
                        <input type="url" class="form-control" id="logo_url" name="logo_url">
                    </div>
                    
                    <div class="mb-3">
                        <label for="score" class="form-label">Değerlendirme Puanı (0-10)</label>
                        <input type="number" class="form-control" id="score" name="score" min="0" max="10" step="0.1" value="5.0">
                    </div>
                    
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                        <button type="submit" name="add_party" class="btn btn-primary">Kaydet</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>