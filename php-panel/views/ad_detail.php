<?php
// Gerekli dosyaları dahil et
require_once __DIR__ . '/../includes/functions.php';
require_once __DIR__ . '/../config/config.php';

// Yetki kontrolü
if (!isLoggedIn()) {
    header("Location: ../login.php");
    exit;
}

// Reklam ID'sini al
$ad_id = isset($_GET['id']) ? $_GET['id'] : null;

// Reklam ID'si yoksa listeye yönlendir
if (!$ad_id) {
    header("Location: ../index.php?page=ads");
    exit;
}

// Reklamı getir
$ad = getAdById($ad_id);

// Reklam bulunamadıysa hata göster
if (!$ad) {
    $_SESSION['error'] = "Reklam bulunamadı.";
    header("Location: ../index.php?page=ads");
    exit;
}

// Görüntülenme sayısını al
$views = getAdViewCount($ad_id);

// Tıklanma sayısını al
$clicks = getAdClickCount($ad_id);

// Şehir ve ilçe isimlerini al
$city_name = $ad['city'] ?? 'Tüm Türkiye';
$district_name = $ad['district'] ?? 'Tüm İlçeler';

// Üst başlık
$title = "Reklam Detayı: " . $ad['title'];
?>

<?php include_once __DIR__ . '/header.php'; ?>

<div class="container-fluid px-4">
    <h1 class="mt-4"><?php echo $title; ?></h1>
    
    <ol class="breadcrumb mb-4">
        <li class="breadcrumb-item"><a href="../index.php">Ana Sayfa</a></li>
        <li class="breadcrumb-item"><a href="../index.php?page=ads">Reklamlar</a></li>
        <li class="breadcrumb-item active">Reklam Detayı</li>
    </ol>
    
    <div class="row">
        <div class="col-xl-12">
            <!-- Üst Butonlar -->
            <div class="mb-4">
                <a href="../index.php?page=ad_edit&id=<?php echo $ad_id; ?>" class="btn btn-primary me-2">
                    <i class="fas fa-edit"></i> Düzenle
                </a>
                <a href="../index.php?page=ad_analytics&id=<?php echo $ad_id; ?>" class="btn btn-info me-2">
                    <i class="fas fa-chart-line"></i> Analitik
                </a>
                <button type="button" class="btn btn-danger" data-bs-toggle="modal" data-bs-target="#deleteModal">
                    <i class="fas fa-trash"></i> Sil
                </button>
            </div>
            
            <!-- Temel Bilgiler -->
            <div class="card mb-4">
                <div class="card-header">
                    <h5 class="mb-0"><i class="fas fa-info-circle me-2"></i>Temel Bilgiler</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-6">
                            <table class="table table-bordered">
                                <tr>
                                    <th style="width: 30%;">Başlık</th>
                                    <td><?php echo htmlspecialchars($ad['title']); ?></td>
                                </tr>
                                <tr>
                                    <th>Durum</th>
                                    <td>
                                        <?php
                                        $status_class = '';
                                        $status_text = '';
                                        
                                        switch ($ad['status']) {
                                            case 'active':
                                                $status_class = 'success';
                                                $status_text = 'Aktif';
                                                break;
                                            case 'paused':
                                                $status_class = 'warning';
                                                $status_text = 'Duraklatıldı';
                                                break;
                                            case 'ended':
                                                $status_class = 'danger';
                                                $status_text = 'Sonlandı';
                                                break;
                                            default:
                                                $status_class = 'secondary';
                                                $status_text = 'Bilinmiyor';
                                        }
                                        ?>
                                        <span class="badge bg-<?php echo $status_class; ?>"><?php echo $status_text; ?></span>
                                    </td>
                                </tr>
                                <tr>
                                    <th>Başlangıç Tarihi</th>
                                    <td><?php echo formatDate($ad['start_date']); ?></td>
                                </tr>
                                <tr>
                                    <th>Bitiş Tarihi</th>
                                    <td><?php echo formatDate($ad['end_date']); ?></td>
                                </tr>
                                <tr>
                                    <th>Oluşturma Tarihi</th>
                                    <td><?php echo formatDate($ad['created_at']); ?></td>
                                </tr>
                                <tr>
                                    <th>Son Güncelleme</th>
                                    <td><?php echo formatDate($ad['updated_at']); ?></td>
                                </tr>
                            </table>
                        </div>
                        <div class="col-md-6">
                            <table class="table table-bordered">
                                <tr>
                                    <th style="width: 30%;">Görüntülenme</th>
                                    <td><span class="badge bg-info"><?php echo number_format($views); ?></span></td>
                                </tr>
                                <tr>
                                    <th>Tıklanma</th>
                                    <td><span class="badge bg-primary"><?php echo number_format($clicks); ?></span></td>
                                </tr>
                                <tr>
                                    <th>CTR</th>
                                    <td>
                                        <?php 
                                        $ctr = ($views > 0) ? ($clicks / $views) * 100 : 0;
                                        echo number_format($ctr, 2) . '%';
                                        ?>
                                    </td>
                                </tr>
                                <tr>
                                    <th>Gösterim Alanı</th>
                                    <td>
                                        <?php
                                        switch ($ad['ad_display_scope']) {
                                            case 'herkes':
                                                echo 'Tüm Türkiye';
                                                break;
                                            case 'il':
                                                echo 'Sadece ' . htmlspecialchars($city_name);
                                                break;
                                            case 'ilce':
                                                echo 'Sadece ' . htmlspecialchars($district_name);
                                                break;
                                            case 'ililce':
                                                echo htmlspecialchars($city_name) . ' / ' . htmlspecialchars($district_name);
                                                break;
                                            default:
                                                echo 'Belirtilmemiş';
                                        }
                                        ?>
                                    </td>
                                </tr>
                                <tr>
                                    <th>Sabitlenmiş</th>
                                    <td>
                                        <?php echo ($ad['is_pinned'] == 1) ? '<span class="badge bg-success">Evet</span>' : '<span class="badge bg-secondary">Hayır</span>'; ?>
                                    </td>
                                </tr>
                                <tr>
                                    <th>Gösterim Konumu</th>
                                    <td>
                                        <?php echo ($ad['show_after_posts'] == 1) ? 'Gönderilerden Sonra' : 'Sayfa Başında'; ?>
                                    </td>
                                </tr>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- İçerik ve Görseller -->
            <div class="row">
                <div class="col-md-6">
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0"><i class="fas fa-file-alt me-2"></i>İçerik</h5>
                        </div>
                        <div class="card-body">
                            <p><?php echo nl2br(htmlspecialchars($ad['content'])); ?></p>
                        </div>
                    </div>
                    
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0"><i class="fas fa-link me-2"></i>Bağlantı Bilgileri</h5>
                        </div>
                        <div class="card-body">
                            <table class="table table-bordered">
                                <tr>
                                    <th style="width: 30%;">Bağlantı Tipi</th>
                                    <td>
                                        <?php
                                        if ($ad['link_type'] === 'url') {
                                            echo 'Web Sitesi URL';
                                        } elseif ($ad['link_type'] === 'phone') {
                                            echo 'Telefon Numarası';
                                        } else {
                                            echo 'Belirtilmemiş';
                                        }
                                        ?>
                                    </td>
                                </tr>
                                <?php if ($ad['link_type'] === 'url' && !empty($ad['link_url'])): ?>
                                <tr>
                                    <th>URL</th>
                                    <td>
                                        <a href="<?php echo htmlspecialchars($ad['link_url']); ?>" target="_blank">
                                            <?php echo htmlspecialchars($ad['link_url']); ?>
                                            <i class="fas fa-external-link-alt ms-1"></i>
                                        </a>
                                    </td>
                                </tr>
                                <?php elseif ($ad['link_type'] === 'phone' && !empty($ad['phone_number'])): ?>
                                <tr>
                                    <th>Telefon</th>
                                    <td>
                                        <a href="tel:<?php echo htmlspecialchars($ad['phone_number']); ?>">
                                            <?php echo htmlspecialchars($ad['phone_number']); ?>
                                            <i class="fas fa-phone ms-1"></i>
                                        </a>
                                    </td>
                                </tr>
                                <?php endif; ?>
                            </table>
                        </div>
                    </div>
                </div>
                
                <div class="col-md-6">
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0"><i class="fas fa-images me-2"></i>Görseller</h5>
                        </div>
                        <div class="card-body">
                            <?php if (!empty($ad['image_urls']) && is_array($ad['image_urls'])): ?>
                                <div class="row">
                                    <?php foreach ($ad['image_urls'] as $url): ?>
                                        <?php if (!empty($url)): ?>
                                            <div class="col-md-6 mb-3">
                                                <div class="card">
                                                    <img src="<?php echo htmlspecialchars($url); ?>" class="img-fluid" alt="Reklam görseli">
                                                    <div class="card-body p-2">
                                                        <a href="<?php echo htmlspecialchars($url); ?>" target="_blank" class="btn btn-sm btn-outline-primary w-100">
                                                            <i class="fas fa-external-link-alt"></i> Tam Boyut
                                                        </a>
                                                    </div>
                                                </div>
                                            </div>
                                        <?php endif; ?>
                                    <?php endforeach; ?>
                                </div>
                            <?php else: ?>
                                <div class="alert alert-info mb-0">
                                    <i class="fas fa-info-circle me-2"></i> Bu reklamda görsel bulunmuyor.
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Silme Modal -->
<div class="modal fade" id="deleteModal" tabindex="-1" aria-labelledby="deleteModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="deleteModalLabel">Reklamı Sil</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
            </div>
            <div class="modal-body">
                <p class="mb-0">Bu reklamı silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                <a href="../index.php?page=ad_delete&id=<?php echo $ad_id; ?>" class="btn btn-danger">Evet, Sil</a>
            </div>
        </div>
    </div>
</div>

<?php include_once __DIR__ . '/footer.php'; ?>