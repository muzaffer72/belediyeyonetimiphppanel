<?php
// Anket yönetimi sayfası
require_once(__DIR__ . '/../includes/functions.php');

// Anketleri getir
$polls_result = getData('polls', [
    'order' => 'created_at.desc'
]);
$polls = $polls_result['data'] ?? [];

// Anket silme işlemi
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $poll_id = $_GET['delete'];
    
    try {
        // Anketi pasif yap (silmek yerine)
        $update_result = updateData('polls', $poll_id, [
            'is_active' => false,
            'deleted_at' => date('Y-m-d H:i:s')
        ]);
        
        if (!$update_result['error']) {
            $_SESSION['message'] = 'Anket başarıyla devre dışı bırakıldı.';
            $_SESSION['message_type'] = 'success';
        } else {
            $_SESSION['message'] = 'İşlem sırasında hata oluştu: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
            $_SESSION['message_type'] = 'danger';
        }
    } catch (Exception $e) {
        $_SESSION['message'] = 'Hata: ' . $e->getMessage();
        $_SESSION['message_type'] = 'danger';
    }
    
    redirect('index.php?page=polls');
}

// Anket durumu değiştirme
if (isset($_GET['toggle']) && !empty($_GET['toggle'])) {
    $poll_id = $_GET['toggle'];
    $poll_result = getDataById('polls', $poll_id);
    
    if (!$poll_result['error'] && $poll_result['data']) {
        $current_status = $poll_result['data']['is_active'];
        $new_status = !$current_status;
        
        $update_result = updateData('polls', $poll_id, ['is_active' => $new_status]);
        
        if (!$update_result['error']) {
            $_SESSION['message'] = 'Anket durumu güncellendi.';
            $_SESSION['message_type'] = 'success';
        } else {
            $_SESSION['message'] = 'Güncelleme hatası: ' . $update_result['message'];
            $_SESSION['message_type'] = 'danger';
        }
    }
    
    redirect('index.php?page=polls');
}
?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">Anket Yönetimi</h1>
    <div>
        <a href="index.php?page=poll_statistics" class="btn btn-info me-2">
            <i class="fas fa-chart-bar me-1"></i> İstatistikler
        </a>
        <a href="index.php?page=poll_edit" class="btn btn-primary">
            <i class="fas fa-plus me-1"></i> Yeni Anket
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

<!-- Anket listesi -->
<div class="card">
    <div class="card-header">
        <h5 class="mb-0">Tüm Anketler</h5>
    </div>
    <div class="card-body">
        <?php if (empty($polls)): ?>
            <div class="text-center py-5">
                <i class="fas fa-poll fa-3x text-muted mb-3"></i>
                <h5>Henüz anket bulunmuyor</h5>
                <p class="text-muted">İlk anketinizi oluşturmak için butona tıklayın.</p>
                <a href="index.php?page=poll_edit" class="btn btn-primary">
                    <i class="fas fa-plus me-1"></i> Yeni Anket Oluştur
                </a>
            </div>
        <?php else: ?>
            <div class="table-responsive">
                <table class="table table-hover">
                    <thead>
                        <tr>
                            <th>Başlık</th>
                            <th>Seviye</th>
                            <th>Toplam Oy</th>
                            <th>Durum</th>
                            <th>Bitiş Tarihi</th>
                            <th>İşlemler</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($polls as $poll): ?>
                            <tr>
                                <td>
                                    <div>
                                        <strong><?php echo escape($poll['title']); ?></strong>
                                        <?php if (!empty($poll['mini_title'])): ?>
                                            <br><small class="text-muted"><?php echo escape($poll['mini_title']); ?></small>
                                        <?php endif; ?>
                                    </div>
                                </td>
                                <td>
                                    <?php
                                    $level_badges = [
                                        'country' => '<span class="badge bg-primary">Ülke</span>',
                                        'city' => '<span class="badge bg-info">Şehir</span>',
                                        'district' => '<span class="badge bg-warning">İlçe</span>'
                                    ];
                                    echo $level_badges[$poll['level']] ?? '<span class="badge bg-secondary">Genel</span>';
                                    ?>
                                </td>
                                <td>
                                    <span class="badge bg-success"><?php echo number_format($poll['total_votes'] ?? 0); ?></span>
                                </td>
                                <td>
                                    <?php if ($poll['is_active']): ?>
                                        <span class="badge bg-success">Aktif</span>
                                    <?php else: ?>
                                        <span class="badge bg-secondary">Pasif</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <?php echo date('d.m.Y H:i', strtotime($poll['end_date'])); ?>
                                </td>
                                <td>
                                    <div class="btn-group btn-group-sm" role="group">
                                        <a href="index.php?page=poll_detail&id=<?php echo $poll['id']; ?>" 
                                           class="btn btn-outline-info" title="Detay">
                                            <i class="fas fa-eye"></i>
                                        </a>
                                        <a href="index.php?page=poll_edit&id=<?php echo $poll['id']; ?>" 
                                           class="btn btn-outline-warning" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <a href="index.php?page=polls&toggle=<?php echo $poll['id']; ?>" 
                                           class="btn btn-outline-<?php echo $poll['is_active'] ? 'warning' : 'success'; ?>" 
                                           title="<?php echo $poll['is_active'] ? 'Pasifleştir' : 'Aktifleştir'; ?>">
                                            <i class="fas fa-<?php echo $poll['is_active'] ? 'pause' : 'play'; ?>"></i>
                                        </a>
                                        <button type="button" class="btn btn-outline-danger" 
                                                onclick="confirmDelete('<?php echo $poll['id']; ?>', '<?php echo escape($poll['title']); ?>')" 
                                                title="Sil">
                                            <i class="fas fa-trash"></i>
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

<script>
function confirmDelete(pollId, pollTitle) {
    if (confirm('Bu anketi silmek istediğinizden emin misiniz?\n\nAnket: ' + pollTitle)) {
        window.location.href = 'index.php?page=polls&delete=' + pollId;
    }
}
</script>