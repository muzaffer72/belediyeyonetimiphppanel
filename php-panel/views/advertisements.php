<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// Yetki kontrolü - sadece admin erişebilir
$user_type = $_SESSION['user_type'] ?? '';
$is_admin = $user_type === 'admin';

if (!$is_admin) {
    $_SESSION['message'] = 'Bu sayfaya erişim yetkiniz yok. Sadece sistem yöneticileri reklam yönetimi yapabilir.';
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=dashboard');
}

// Sponsorlu reklamları al
$ads_result = getData('sponsored_ads', [
    'order' => 'created_at.desc'
]);
$ads = $ads_result['data'];

// Tüm reklam ID'lerini topla
$ad_ids = array_map(function($ad) {
    return $ad['id'];
}, $ads);

// Boş ad_ids array kontrolü
if (!empty($ad_ids)) {
    // Daha verimli şekilde, tüm reklam etkileşimlerini tek bir sorguda al
    $all_interactions_result = getData('ad_interactions', [
        'ad_id' => 'in.(' . implode(',', $ad_ids) . ')'
    ]);
    
    $all_interactions = $all_interactions_result['data'] ?? [];
    
    // Etkileşimleri reklam ID'sine ve tipine göre grupla
    $grouped_interactions = [];
    foreach ($all_interactions as $interaction) {
        $ad_id = $interaction['ad_id'];
        $type = $interaction['interaction_type'];
        
        if (!isset($grouped_interactions[$ad_id])) {
            $grouped_interactions[$ad_id] = [
                'impression' => 0,
                'click' => 0
            ];
        }
        
        if ($type === 'impression') {
            $grouped_interactions[$ad_id]['impression']++;
        } elseif ($type === 'click') {
            $grouped_interactions[$ad_id]['click']++;
        }
    }
    
    // Reklam verilerine etkileşim sayılarını ekle
    foreach ($ads as &$ad) {
        $ad_id = $ad['id'];
        
        if (isset($grouped_interactions[$ad_id])) {
            $ad['impressions'] = $grouped_interactions[$ad_id]['impression'];
            $ad['clicks'] = $grouped_interactions[$ad_id]['click'];
        } else {
            $ad['impressions'] = 0;
            $ad['clicks'] = 0;
        }
    }
    unset($ad);
} else {
    // Eğer hiç reklam yoksa, varsayılan değerleri atama
    foreach ($ads as &$ad) {
        $ad['impressions'] = 0;
        $ad['clicks'] = 0;
    }
    unset($ad);
}

// Aktif, bekleyen ve süresi dolmuş reklamları ayır
$active_ads = [];
$pending_ads = [];
$expired_ads = [];
$current_date = date('Y-m-d H:i:s');

foreach ($ads as $ad) {
    $start_date = strtotime($ad['start_date']);
    $end_date = strtotime($ad['end_date']);
    $now = strtotime($current_date);
    
    if ($now < $start_date) {
        $pending_ads[] = $ad; // Henüz başlamamış
    } elseif ($now > $end_date) {
        $expired_ads[] = $ad; // Süresi dolmuş
    } else {
        $active_ads[] = $ad; // Aktif
    }
}

// Reklam silme işlemini yönet
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $ad_id = $_GET['delete'];
    
    // Reklam ve reklam etkileşimlerini sil
    try {
        // Önce reklam etkileşimlerini sil
        $delete_interactions = deleteData('ad_interactions', null, ['ad_id' => 'eq.' . $ad_id]);
        
        // Sonra reklamı sil
        $delete_ad = deleteData('sponsored_ads', $ad_id);
        
        if (!$delete_ad['error']) {
            $_SESSION['message'] = 'Reklam başarıyla silindi.';
            $_SESSION['message_type'] = 'success';
        } else {
            $_SESSION['message'] = 'Reklam silinirken bir hata oluştu: ' . $delete_ad['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } catch (Exception $e) {
        $_SESSION['message'] = 'Reklam silinirken bir hata oluştu: ' . $e->getMessage();
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yenile
    safeRedirect('index.php?page=advertisements');
}

// Reklam durumu güncelleme
if (isset($_GET['status']) && !empty($_GET['status']) && isset($_GET['id']) && !empty($_GET['id'])) {
    $ad_id = $_GET['id'];
    $status = $_GET['status'];
    
    // Durumu güncelle
    try {
        $update_data = [
            'status' => $status,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        $update_result = updateData('sponsored_ads', $ad_id, $update_data);
        
        if (!$update_result['error']) {
            $_SESSION['message'] = 'Reklam durumu başarıyla güncellendi.';
            $_SESSION['message_type'] = 'success';
        } else {
            $_SESSION['message'] = 'Reklam durumu güncellenirken bir hata oluştu: ' . $update_result['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } catch (Exception $e) {
        $_SESSION['message'] = 'Reklam durumu güncellenirken bir hata oluştu: ' . $e->getMessage();
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yenile
    safeRedirect('index.php?page=advertisements');
}
?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">Sponsorlu Reklamlar</h1>
    
    <a href="index.php?page=ad_edit" class="btn btn-primary">
        <i class="fas fa-plus-circle me-1"></i> Yeni Reklam Ekle
    </a>
</div>

<!-- Mesaj gösterimi -->
<?php if (isset($_SESSION['message']) && isset($_SESSION['message_type'])): ?>
    <div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
        <?php echo $_SESSION['message']; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
    </div>
    <?php unset($_SESSION['message'], $_SESSION['message_type']); ?>
<?php endif; ?>

<!-- Tab menüsü -->
<ul class="nav nav-tabs mb-4" id="adsTab" role="tablist">
    <li class="nav-item" role="presentation">
        <button class="nav-link active" id="active-tab" data-bs-toggle="tab" data-bs-target="#active" type="button" role="tab" aria-controls="active" aria-selected="true">
            <i class="fas fa-check-circle me-1"></i> Aktif Reklamlar
            <span class="badge bg-primary ms-1"><?php echo count($active_ads); ?></span>
        </button>
    </li>
    <li class="nav-item" role="presentation">
        <button class="nav-link" id="pending-tab" data-bs-toggle="tab" data-bs-target="#pending" type="button" role="tab" aria-controls="pending" aria-selected="false">
            <i class="fas fa-clock me-1"></i> Bekleyen Reklamlar
            <span class="badge bg-warning text-dark ms-1"><?php echo count($pending_ads); ?></span>
        </button>
    </li>
    <li class="nav-item" role="presentation">
        <button class="nav-link" id="expired-tab" data-bs-toggle="tab" data-bs-target="#expired" type="button" role="tab" aria-controls="expired" aria-selected="false">
            <i class="fas fa-calendar-times me-1"></i> Süresi Dolmuş Reklamlar
            <span class="badge bg-secondary ms-1"><?php echo count($expired_ads); ?></span>
        </button>
    </li>
</ul>

<!-- Tab içeriği -->
<div class="tab-content" id="adsTabContent">
    <!-- Aktif Reklamlar -->
    <div class="tab-pane fade show active" id="active" role="tabpanel" aria-labelledby="active-tab">
        <div class="card">
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>Görsel</th>
                                <th>Başlık</th>
                                <th>Kapsam</th>
                                <th>Tarih Aralığı</th>
                                <th>Durum</th>
                                <th>Gösterim/Tıklama</th>
                                <th>İşlemler</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (empty($active_ads)): ?>
                                <tr>
                                    <td colspan="7" class="text-center">Aktif reklam bulunmamaktadır.</td>
                                </tr>
                            <?php else: ?>
                                <?php foreach ($active_ads as $ad): ?>
                                    <tr>
                                        <td>
                                            <?php if (!empty($ad['image_urls']) && is_array($ad['image_urls']) && !empty($ad['image_urls'][0])): ?>
                                                <img src="<?php echo escape($ad['image_urls'][0]); ?>" alt="Reklam Görseli" style="height: 50px; width: auto;" class="img-thumbnail">
                                            <?php else: ?>
                                                <div class="bg-light d-flex align-items-center justify-content-center" style="height: 50px; width: 50px;">
                                                    <i class="fas fa-image text-muted"></i>
                                                </div>
                                            <?php endif; ?>
                                        </td>
                                        <td><?php echo escape($ad['title']); ?></td>
                                        <td>
                                            <?php
                                            switch ($ad['ad_display_scope']) {
                                                case 'il':
                                                    echo '<span class="badge bg-primary">İl: ' . escape($ad['city'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'ilce':
                                                    echo '<span class="badge bg-info">İlçe: ' . escape($ad['district'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'ililce':
                                                    echo '<span class="badge bg-primary">İl: ' . escape($ad['city'] ?? 'Tümü') . '</span> ';
                                                    echo '<span class="badge bg-info">İlçe: ' . escape($ad['district'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'splash':
                                                    echo '<span class="badge bg-warning">Açılış Sayfası</span>';
                                                    break;
                                                default:
                                                    echo '<span class="badge bg-success">Tüm Kullanıcılar</span>';
                                            }
                                            ?>
                                        </td>
                                        <td>
                                            <?php
                                            $start_date = date('d.m.Y', strtotime($ad['start_date']));
                                            $end_date = date('d.m.Y', strtotime($ad['end_date']));
                                            echo $start_date . ' - ' . $end_date;
                                            ?>
                                        </td>
                                        <td>
                                            <?php if ($ad['status'] === 'active'): ?>
                                                <span class="badge bg-success">Aktif</span>
                                            <?php elseif ($ad['status'] === 'paused'): ?>
                                                <span class="badge bg-warning text-dark">Duraklatıldı</span>
                                            <?php else: ?>
                                                <span class="badge bg-secondary">Pasif</span>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <div class="d-flex flex-column">
                                                <small>
                                                    <i class="fas fa-eye me-1"></i> <?php echo isset($ad['impressions']) ? number_format($ad['impressions']) : '0'; ?>
                                                </small>
                                                <small>
                                                    <i class="fas fa-mouse-pointer me-1"></i> <?php echo isset($ad['clicks']) ? number_format($ad['clicks']) : '0'; ?>
                                                </small>
                                                <?php
                                                $impressions = isset($ad['impressions']) ? intval($ad['impressions']) : 0;
                                                $clicks = isset($ad['clicks']) ? intval($ad['clicks']) : 0;
                                                $ctr = $impressions > 0 ? ($clicks / $impressions) * 100 : 0;
                                                ?>
                                                <small>
                                                    <i class="fas fa-percentage me-1"></i> CTR: <?php echo number_format($ctr, 2); ?>%
                                                </small>
                                            </div>
                                        </td>
                                        <td>
                                            <div class="btn-group btn-group-sm">
                                                <a href="index.php?page=ad_detail&id=<?php echo $ad['id']; ?>" class="btn btn-info" title="Görüntüle">
                                                    <i class="fas fa-eye"></i>
                                                </a>
                                                <a href="index.php?page=ad_edit&id=<?php echo $ad['id']; ?>" class="btn btn-warning" title="Düzenle">
                                                    <i class="fas fa-edit"></i>
                                                </a>
                                                <a href="index.php?page=ad_analytics&id=<?php echo $ad['id']; ?>" class="btn btn-primary" title="Analitikler">
                                                    <i class="fas fa-chart-line"></i>
                                                </a>
                                                <?php if ($ad['status'] === 'active'): ?>
                                                <a href="index.php?page=advertisements&id=<?php echo $ad['id']; ?>&status=paused" class="btn btn-warning" title="Duraklat">
                                                    <i class="fas fa-pause"></i>
                                                </a>
                                                <?php else: ?>
                                                <a href="index.php?page=advertisements&id=<?php echo $ad['id']; ?>&status=active" class="btn btn-success" title="Aktifleştir">
                                                    <i class="fas fa-play"></i>
                                                </a>
                                                <?php endif; ?>
                                                <a href="javascript:void(0);" class="btn btn-danger" title="Sil" onclick="confirmDelete('<?php echo $ad['id']; ?>', '<?php echo escape($ad['title']); ?>')">
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
    </div>
    
    <!-- Bekleyen Reklamlar -->
    <div class="tab-pane fade" id="pending" role="tabpanel" aria-labelledby="pending-tab">
        <div class="card">
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>Görsel</th>
                                <th>Başlık</th>
                                <th>Kapsam</th>
                                <th>Başlangıç Tarihi</th>
                                <th>Durum</th>
                                <th>İşlemler</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (empty($pending_ads)): ?>
                                <tr>
                                    <td colspan="6" class="text-center">Bekleyen reklam bulunmamaktadır.</td>
                                </tr>
                            <?php else: ?>
                                <?php foreach ($pending_ads as $ad): ?>
                                    <tr>
                                        <td>
                                            <?php if (!empty($ad['image_urls']) && is_array($ad['image_urls']) && !empty($ad['image_urls'][0])): ?>
                                                <img src="<?php echo escape($ad['image_urls'][0]); ?>" alt="Reklam Görseli" style="height: 50px; width: auto;" class="img-thumbnail">
                                            <?php else: ?>
                                                <div class="bg-light d-flex align-items-center justify-content-center" style="height: 50px; width: 50px;">
                                                    <i class="fas fa-image text-muted"></i>
                                                </div>
                                            <?php endif; ?>
                                        </td>
                                        <td><?php echo escape($ad['title']); ?></td>
                                        <td>
                                            <?php
                                            switch ($ad['ad_display_scope']) {
                                                case 'il':
                                                    echo '<span class="badge bg-primary">İl: ' . escape($ad['city'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'ilce':
                                                    echo '<span class="badge bg-info">İlçe: ' . escape($ad['district'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'ililce':
                                                    echo '<span class="badge bg-primary">İl: ' . escape($ad['city'] ?? 'Tümü') . '</span> ';
                                                    echo '<span class="badge bg-info">İlçe: ' . escape($ad['district'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'splash':
                                                    echo '<span class="badge bg-warning">Açılış Sayfası</span>';
                                                    break;
                                                default:
                                                    echo '<span class="badge bg-success">Tüm Kullanıcılar</span>';
                                            }
                                            ?>
                                        </td>
                                        <td>
                                            <?php
                                            $start_date = date('d.m.Y', strtotime($ad['start_date']));
                                            echo $start_date;
                                            
                                            // Başlangıca ne kadar kaldığını hesapla
                                            $now = time();
                                            $start = strtotime($ad['start_date']);
                                            $diff = $start - $now;
                                            $days = floor($diff / (60 * 60 * 24));
                                            
                                            if ($days > 0) {
                                                echo ' <span class="badge bg-info">' . $days . ' gün sonra başlayacak</span>';
                                            } else {
                                                $hours = floor($diff / (60 * 60));
                                                echo ' <span class="badge bg-info">' . $hours . ' saat sonra başlayacak</span>';
                                            }
                                            ?>
                                        </td>
                                        <td>
                                            <?php if ($ad['status'] === 'active'): ?>
                                                <span class="badge bg-warning text-dark">Beklemede</span>
                                            <?php elseif ($ad['status'] === 'paused'): ?>
                                                <span class="badge bg-warning text-dark">Duraklatıldı</span>
                                            <?php else: ?>
                                                <span class="badge bg-secondary">Pasif</span>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <div class="btn-group btn-group-sm">
                                                <a href="index.php?page=ad_detail&id=<?php echo $ad['id']; ?>" class="btn btn-info" title="Görüntüle">
                                                    <i class="fas fa-eye"></i>
                                                </a>
                                                <a href="index.php?page=ad_edit&id=<?php echo $ad['id']; ?>" class="btn btn-warning" title="Düzenle">
                                                    <i class="fas fa-edit"></i>
                                                </a>
                                                <a href="javascript:void(0);" class="btn btn-danger" title="Sil" onclick="confirmDelete('<?php echo $ad['id']; ?>', '<?php echo escape($ad['title']); ?>')">
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
    </div>
    
    <!-- Süresi Dolmuş Reklamlar -->
    <div class="tab-pane fade" id="expired" role="tabpanel" aria-labelledby="expired-tab">
        <div class="card">
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>Görsel</th>
                                <th>Başlık</th>
                                <th>Kapsam</th>
                                <th>Tarih Aralığı</th>
                                <th>Gösterim/Tıklama</th>
                                <th>İşlemler</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (empty($expired_ads)): ?>
                                <tr>
                                    <td colspan="6" class="text-center">Süresi dolmuş reklam bulunmamaktadır.</td>
                                </tr>
                            <?php else: ?>
                                <?php foreach ($expired_ads as $ad): ?>
                                    <tr>
                                        <td>
                                            <?php if (!empty($ad['image_urls']) && is_array($ad['image_urls']) && !empty($ad['image_urls'][0])): ?>
                                                <img src="<?php echo escape($ad['image_urls'][0]); ?>" alt="Reklam Görseli" style="height: 50px; width: auto;" class="img-thumbnail">
                                            <?php else: ?>
                                                <div class="bg-light d-flex align-items-center justify-content-center" style="height: 50px; width: 50px;">
                                                    <i class="fas fa-image text-muted"></i>
                                                </div>
                                            <?php endif; ?>
                                        </td>
                                        <td><?php echo escape($ad['title']); ?></td>
                                        <td>
                                            <?php
                                            switch ($ad['ad_display_scope']) {
                                                case 'il':
                                                    echo '<span class="badge bg-primary">İl: ' . escape($ad['city'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'ilce':
                                                    echo '<span class="badge bg-info">İlçe: ' . escape($ad['district'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'ililce':
                                                    echo '<span class="badge bg-primary">İl: ' . escape($ad['city'] ?? 'Tümü') . '</span> ';
                                                    echo '<span class="badge bg-info">İlçe: ' . escape($ad['district'] ?? 'Tümü') . '</span>';
                                                    break;
                                                case 'splash':
                                                    echo '<span class="badge bg-warning">Açılış Sayfası</span>';
                                                    break;
                                                default:
                                                    echo '<span class="badge bg-success">Tüm Kullanıcılar</span>';
                                            }
                                            ?>
                                        </td>
                                        <td>
                                            <?php
                                            $start_date = date('d.m.Y', strtotime($ad['start_date']));
                                            $end_date = date('d.m.Y', strtotime($ad['end_date']));
                                            echo $start_date . ' - ' . $end_date . ' ';
                                            echo '<span class="badge bg-secondary">Süresi Dolmuş</span>';
                                            ?>
                                        </td>
                                        <td>
                                            <div class="d-flex flex-column">
                                                <small>
                                                    <i class="fas fa-eye me-1"></i> <?php echo isset($ad['impressions']) ? number_format($ad['impressions']) : '0'; ?>
                                                </small>
                                                <small>
                                                    <i class="fas fa-mouse-pointer me-1"></i> <?php echo isset($ad['clicks']) ? number_format($ad['clicks']) : '0'; ?>
                                                </small>
                                                <?php
                                                $impressions = isset($ad['impressions']) ? intval($ad['impressions']) : 0;
                                                $clicks = isset($ad['clicks']) ? intval($ad['clicks']) : 0;
                                                $ctr = $impressions > 0 ? ($clicks / $impressions) * 100 : 0;
                                                ?>
                                                <small>
                                                    <i class="fas fa-percentage me-1"></i> CTR: <?php echo number_format($ctr, 2); ?>%
                                                </small>
                                            </div>
                                        </td>
                                        <td>
                                            <div class="btn-group btn-group-sm">
                                                <a href="index.php?page=ad_detail&id=<?php echo $ad['id']; ?>" class="btn btn-info" title="Görüntüle">
                                                    <i class="fas fa-eye"></i>
                                                </a>
                                                <a href="index.php?page=ad_analytics&id=<?php echo $ad['id']; ?>" class="btn btn-primary" title="Analitikler">
                                                    <i class="fas fa-chart-line"></i>
                                                </a>
                                                <a href="index.php?page=ad_edit&id=<?php echo $ad['id']; ?>&clone=true" class="btn btn-success" title="Tekrar Kullan">
                                                    <i class="fas fa-copy"></i>
                                                </a>
                                                <a href="javascript:void(0);" class="btn btn-danger" title="Sil" onclick="confirmDelete('<?php echo $ad['id']; ?>', '<?php echo escape($ad['title']); ?>')">
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
    </div>
</div>

<!-- Silme Onay Modalı -->
<div class="modal fade" id="deleteModal" tabindex="-1" aria-labelledby="deleteModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="deleteModalLabel">Reklamı Sil</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
            </div>
            <div class="modal-body">
                <p id="deleteConfirmText">Bu reklamı silmek istediğinizden emin misiniz?</p>
                <p class="text-danger"><strong>Dikkat:</strong> Bu işlem geri alınamaz ve tüm reklam etkileşimleri de silinir.</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                <a href="#" id="confirmDeleteBtn" class="btn btn-danger">Sil</a>
            </div>
        </div>
    </div>
</div>

<script>
    // Silme onay fonksiyonu
    function confirmDelete(id, title) {
        document.getElementById('deleteConfirmText').innerText = `"${title}" başlıklı reklamı silmek istediğinizden emin misiniz?`;
        document.getElementById('confirmDeleteBtn').href = `index.php?page=advertisements&delete=${id}`;
        
        var deleteModal = new bootstrap.Modal(document.getElementById('deleteModal'));
        deleteModal.show();
    }
    
    // Sayfa yüklendiğinde
    document.addEventListener('DOMContentLoaded', function() {
        // URL'de belirtilen tabı aktif et
        const urlParams = new URLSearchParams(window.location.search);
        const activeTab = urlParams.get('tab');
        
        if (activeTab) {
            const tab = document.querySelector(`#${activeTab}-tab`);
            if (tab) {
                bootstrap.Tab.getOrCreateInstance(tab).show();
            }
        }
    });
</script>