<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Sadece belediye görevlisi erişimi kontrolü
if (!isLoggedIn() || !isset($_SESSION['is_official']) || !$_SESSION['is_official']) {
    redirect('index.php?page=official_login');
}

// Görevli bilgilerini al
$city_id = $_SESSION['city_id'] ?? null;
$district_id = $_SESSION['district_id'] ?? null;
$city_name = $_SESSION['city_name'] ?? 'Bilinmiyor';
$district_name = $_SESSION['district_name'] ?? 'Bilinmiyor';
$official_id = $_SESSION['official_id'] ?? '';

$success_message = '';
$error_message = '';

// Duyuru ID'si varsa detayları al
$announcement_id = isset($_GET['id']) ? $_GET['id'] : null;
$edit_mode = !empty($announcement_id);

if ($edit_mode) {
    $announcement_result = getData('announcements', [
        'select' => '*',
        'filters' => ['id' => 'eq.' . $announcement_id]
    ]);
    
    $announcement = !$announcement_result['error'] && !empty($announcement_result['data']) 
                  ? $announcement_result['data'][0] 
                  : null;
    
    // Bu duyurunun bu görevliye ait olup olmadığını kontrol et
    if ($announcement && $announcement['created_by'] !== $official_id) {
        $error_message = "Bu duyuruyu düzenleme yetkiniz yok.";
        $edit_mode = false;
        $announcement = null;
    }
}

// Duyuru silme işlemi
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $delete_id = $_GET['delete'];
    
    // Duyurunun bu görevliye ait olup olmadığını kontrol et
    $check_result = getData('announcements', [
        'select' => 'created_by',
        'filters' => ['id' => 'eq.' . $delete_id]
    ]);
    
    if (!$check_result['error'] && !empty($check_result['data']) && $check_result['data'][0]['created_by'] === $official_id) {
        $delete_result = deleteData('announcements', $delete_id);
        
        if (!$delete_result['error']) {
            $success_message = "Duyuru başarıyla silindi.";
        } else {
            $error_message = "Duyuru silinirken bir hata oluştu: " . ($delete_result['message'] ?? 'Bilinmeyen hata');
        }
    } else {
        $error_message = "Bu duyuruyu silme yetkiniz yok veya duyuru bulunamadı.";
    }
}

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $title = $_POST['title'] ?? '';
    $content = $_POST['content'] ?? '';
    $is_important = isset($_POST['is_important']) ? (bool)$_POST['is_important'] : false;
    $start_date = $_POST['start_date'] ?? date('Y-m-d');
    $end_date = $_POST['end_date'] ?? date('Y-m-d', strtotime('+7 days'));
    $status = $_POST['status'] ?? 'published';
    
    // Form doğrulama
    if (empty($title) || empty($content)) {
        $error_message = "Başlık ve içerik alanları zorunludur.";
    } else {
        if ($edit_mode) {
            // Mevcut duyuruyu güncelle
            $update_data = [
                'title' => $title,
                'content' => $content,
                'is_important' => $is_important,
                'start_date' => $start_date,
                'end_date' => $end_date,
                'status' => $status,
                'updated_at' => date('c')
            ];
            
            $update_result = updateData('announcements', $announcement_id, $update_data);
            
            if (!$update_result['error']) {
                $success_message = "Duyuru başarıyla güncellendi.";
                
                // Düzenleme formu için güncel verileri al
                $announcement_result = getData('announcements', [
                    'select' => '*',
                    'filters' => ['id' => 'eq.' . $announcement_id]
                ]);
                
                $announcement = !$announcement_result['error'] && !empty($announcement_result['data']) 
                              ? $announcement_result['data'][0] 
                              : null;
            } else {
                $error_message = "Duyuru güncellenirken bir hata oluştu: " . ($update_result['message'] ?? 'Bilinmeyen hata');
            }
        } else {
            // Yeni duyuru ekle
            $entity_type = $district_id ? 'district' : 'city';
            $entity_id = $district_id ?: $city_id;
            
            $announcement_data = [
                'title' => $title,
                'content' => $content,
                'entity_type' => $entity_type,
                'entity_id' => $entity_id,
                'is_important' => $is_important,
                'start_date' => $start_date,
                'end_date' => $end_date,
                'status' => $status,
                'created_by' => $official_id,
                'created_at' => date('c'),
                'updated_at' => date('c')
            ];
            
            $insert_result = addData('announcements', $announcement_data);
            
            if (!$insert_result['error']) {
                $success_message = "Duyuru başarıyla eklendi.";
                
                // Formu temizle
                $_POST = [];
            } else {
                $error_message = "Duyuru eklenirken bir hata oluştu: " . ($insert_result['message'] ?? 'Bilinmeyen hata');
            }
        }
    }
}

// Mevcut duyuruları listele
$entity_type = $district_id ? 'district' : 'city';
$entity_id = $district_id ?: $city_id;

$announcements_result = getData('announcements', [
    'select' => '*',
    'filters' => [
        'entity_type' => 'eq.' . $entity_type,
        'entity_id' => 'eq.' . $entity_id
    ],
    'order' => 'created_at.desc'
]);

$announcements = !$announcements_result['error'] ? $announcements_result['data'] : [];
?>

<!-- Başlık ve Butonlar -->
<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3 mb-0">
        <i class="fas fa-bullhorn me-2"></i> 
        <?php echo $district_id ? $district_name : $city_name; ?> Duyuruları
    </h1>
    
    <div>
        <?php if ($edit_mode): ?>
            <a href="index.php?page=official_announcements" class="btn btn-secondary me-2">
                <i class="fas fa-plus me-1"></i> Yeni Duyuru
            </a>
        <?php endif; ?>
        
        <a href="index.php?page=official_dashboard" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Panele Dön
        </a>
    </div>
</div>

<!-- Uyarı ve Bilgilendirme Mesajları -->
<?php if (!empty($success_message)): ?>
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        <?php echo $success_message; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
    </div>
<?php endif; ?>

<?php if (!empty($error_message)): ?>
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        <?php echo $error_message; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
    </div>
<?php endif; ?>

<!-- Duyuru Form Kartı -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-edit me-1"></i>
        <?php echo $edit_mode ? 'Duyuru Düzenle' : 'Yeni Duyuru Ekle'; ?>
    </div>
    <div class="card-body">
        <form method="post" action="">
            <div class="mb-3">
                <label for="title" class="form-label">Başlık <span class="text-danger">*</span></label>
                <input type="text" class="form-control" id="title" name="title" required
                       value="<?php echo htmlspecialchars($edit_mode ? $announcement['title'] : ($_POST['title'] ?? '')); ?>">
            </div>
            
            <div class="mb-3">
                <label for="content" class="form-label">İçerik <span class="text-danger">*</span></label>
                <textarea class="form-control" id="content" name="content" rows="6" required><?php echo htmlspecialchars($edit_mode ? $announcement['content'] : ($_POST['content'] ?? '')); ?></textarea>
            </div>
            
            <div class="row">
                <div class="col-md-6">
                    <div class="mb-3">
                        <label for="start_date" class="form-label">Başlangıç Tarihi</label>
                        <input type="date" class="form-control" id="start_date" name="start_date" 
                               value="<?php echo htmlspecialchars($edit_mode ? substr($announcement['start_date'], 0, 10) : ($_POST['start_date'] ?? date('Y-m-d'))); ?>">
                    </div>
                </div>
                
                <div class="col-md-6">
                    <div class="mb-3">
                        <label for="end_date" class="form-label">Bitiş Tarihi</label>
                        <input type="date" class="form-control" id="end_date" name="end_date" 
                               value="<?php echo htmlspecialchars($edit_mode ? substr($announcement['end_date'], 0, 10) : ($_POST['end_date'] ?? date('Y-m-d', strtotime('+7 days')))); ?>">
                    </div>
                </div>
            </div>
            
            <div class="row">
                <div class="col-md-6">
                    <div class="mb-3">
                        <label for="status" class="form-label">Durum</label>
                        <select class="form-select" id="status" name="status">
                            <option value="draft" <?php echo ($edit_mode && $announcement['status'] === 'draft') || (!$edit_mode && isset($_POST['status']) && $_POST['status'] === 'draft') ? 'selected' : ''; ?>>Taslak</option>
                            <option value="published" <?php echo ($edit_mode && $announcement['status'] === 'published') || (!$edit_mode && (!isset($_POST['status']) || $_POST['status'] === 'published')) ? 'selected' : ''; ?>>Yayında</option>
                            <option value="archived" <?php echo ($edit_mode && $announcement['status'] === 'archived') || (!$edit_mode && isset($_POST['status']) && $_POST['status'] === 'archived') ? 'selected' : ''; ?>>Arşivlenmiş</option>
                        </select>
                    </div>
                </div>
                
                <div class="col-md-6">
                    <div class="mb-3 form-check mt-4">
                        <input type="checkbox" class="form-check-input" id="is_important" name="is_important" value="1" 
                               <?php echo ($edit_mode && $announcement['is_important']) || (!$edit_mode && isset($_POST['is_important'])) ? 'checked' : ''; ?>>
                        <label class="form-check-label" for="is_important">Önemli Duyuru</label>
                        <div class="form-text">Önemli duyurular vatandaşlara bildirim olarak gönderilir ve uygulamada vurgulanır.</div>
                    </div>
                </div>
            </div>
            
            <div class="d-grid gap-2 d-md-flex justify-content-md-end">
                <button type="submit" class="btn btn-primary">
                    <i class="fas fa-save me-1"></i> <?php echo $edit_mode ? 'Değişiklikleri Kaydet' : 'Duyuru Ekle'; ?>
                </button>
            </div>
        </form>
    </div>
</div>

<!-- Duyuru Listesi -->
<div class="card">
    <div class="card-header">
        <i class="fas fa-list me-1"></i>
        Mevcut Duyurular
    </div>
    <div class="card-body">
        <?php if (empty($announcements)): ?>
            <div class="alert alert-info mb-0">
                Henüz duyuru eklenmemiş.
            </div>
        <?php else: ?>
            <div class="table-responsive">
                <table class="table table-striped table-hover data-table" id="announcements-table">
                    <thead>
                        <tr>
                            <th>Başlık</th>
                            <th>Durum</th>
                            <th>Önemli</th>
                            <th>Tarih Aralığı</th>
                            <th>Oluşturma Tarihi</th>
                            <th style="width: 140px;">İşlemler</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($announcements as $item): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($item['title']); ?></td>
                                <td>
                                    <?php
                                    $status_class = '';
                                    $status_text = '';
                                    
                                    switch ($item['status']) {
                                        case 'draft':
                                            $status_class = 'secondary';
                                            $status_text = 'Taslak';
                                            break;
                                        case 'published':
                                            $status_class = 'success';
                                            $status_text = 'Yayında';
                                            break;
                                        case 'archived':
                                            $status_class = 'dark';
                                            $status_text = 'Arşivlenmiş';
                                            break;
                                        default:
                                            $status_class = 'light';
                                            $status_text = $item['status'];
                                    }
                                    ?>
                                    <span class="badge bg-<?php echo $status_class; ?>"><?php echo $status_text; ?></span>
                                </td>
                                <td>
                                    <?php if ($item['is_important']): ?>
                                        <span class="badge bg-danger"><i class="fas fa-exclamation-circle me-1"></i> Önemli</span>
                                    <?php else: ?>
                                        <span class="badge bg-light text-dark">Standart</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <?php 
                                    $start_date = date('d.m.Y', strtotime($item['start_date']));
                                    $end_date = date('d.m.Y', strtotime($item['end_date']));
                                    echo $start_date . ' - ' . $end_date;
                                    ?>
                                </td>
                                <td><?php echo date('d.m.Y H:i', strtotime($item['created_at'])); ?></td>
                                <td>
                                    <div class="btn-group">
                                        <a href="index.php?page=official_announcements&id=<?php echo $item['id']; ?>" class="btn btn-sm btn-primary" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <button type="button" class="btn btn-sm btn-danger" title="Sil" 
                                                onclick="confirmDelete('<?php echo $item['id']; ?>', '<?php echo htmlspecialchars(addslashes($item['title'])); ?>')">
                                            <i class="fas fa-trash-alt"></i>
                                        </button>
                                        <button type="button" class="btn btn-sm btn-info" title="Önizle" data-bs-toggle="modal" data-bs-target="#previewModal" 
                                                data-title="<?php echo htmlspecialchars(addslashes($item['title'])); ?>" 
                                                data-content="<?php echo htmlspecialchars(addslashes($item['content'])); ?>">
                                            <i class="fas fa-eye"></i>
                                        </button>
                                    </div>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
    </div>
</div>

<!-- Önizleme Modalı -->
<div class="modal fade" id="previewModal" tabindex="-1" aria-labelledby="previewModalLabel" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="previewModalLabel">Duyuru Önizleme</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
            </div>
            <div class="modal-body">
                <h4 id="previewTitle"></h4>
                <hr>
                <div id="previewContent" class="mt-3"></div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Kapat</button>
            </div>
        </div>
    </div>
</div>

<script>
    // Duyuru silme işlemi onayı
    function confirmDelete(id, title) {
        if (confirm('"' + title + '" başlıklı duyuruyu silmek istediğinize emin misiniz?')) {
            window.location.href = "index.php?page=official_announcements&delete=" + id;
        }
    }
    
    // Önizleme modalı
    document.addEventListener('DOMContentLoaded', function() {
        var previewModal = document.getElementById('previewModal');
        if (previewModal) {
            previewModal.addEventListener('show.bs.modal', function(event) {
                var button = event.relatedTarget;
                var title = button.getAttribute('data-title');
                var content = button.getAttribute('data-content');
                
                var modalTitle = previewModal.querySelector('#previewTitle');
                var modalContent = previewModal.querySelector('#previewContent');
                
                modalTitle.textContent = title;
                
                // İçeriği HTML olarak göster (güvenli içerik olduğunu varsayıyoruz)
                modalContent.textContent = content;
            });
        }
    });
</script>