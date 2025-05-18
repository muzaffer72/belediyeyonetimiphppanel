<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz ilçe ID\'si';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=districts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=districts";</script>';
        exit;
    }
}

// İlçe bilgilerini al
$district_id = $_GET['id'];
$district = getDataById('districts', $district_id);

if (!$district) {
    $_SESSION['message'] = 'İlçe bulunamadı';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=districts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=districts";</script>';
        exit;
    }
}

// Bağlı olduğu şehri bul
$city = null;
if (isset($district['city_id'])) {
    $city = getDataById('cities', $district['city_id']);
}

// Gönderi verilerini al
$posts_result = getData('posts', ['district' => 'eq.' . $district['name']]);
$posts = $posts_result['data'];

// Belediye duyurularını al
$announcements_result = getData('municipality_announcements', ['municipality_id' => 'eq.' . $district_id]);
$announcements = $announcements_result['data'];
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3"><?php echo escape($district['name']); ?> İlçesi Detayları</h1>
    
    <div>
        <a href="index.php?page=district_edit&id=<?php echo $district_id; ?>" class="btn btn-warning me-2">
            <i class="fas fa-edit me-1"></i> Düzenle
        </a>
        <a href="index.php?page=districts" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> İlçelere Dön
        </a>
    </div>
</div>

<?php if(isset($district['cover_image_url']) && !empty($district['cover_image_url'])): ?>
<div class="card mb-4">
    <div class="card-body p-0">
        <img src="<?php echo escape($district['cover_image_url']); ?>" alt="<?php echo escape($district['name']); ?> Kapak" class="img-fluid w-100" style="max-height: 300px; object-fit: cover;">
    </div>
</div>
<?php endif; ?>

<div class="row">
    <!-- İlçe Bilgileri Kartı -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex align-items-center">
                    <?php if(isset($district['logo_url']) && !empty($district['logo_url'])): ?>
                        <img src="<?php echo escape($district['logo_url']); ?>" alt="<?php echo escape($district['name']); ?> Logo" height="40" class="me-2">
                    <?php else: ?>
                        <i class="fas fa-map-marker-alt me-2"></i>
                    <?php endif; ?>
                    <h5 class="mb-0">İlçe Bilgileri</h5>
                </div>
            </div>
            <div class="card-body">
                <table class="table table-striped">
                    <tbody>
                        <tr>
                            <th style="width: 150px;">İlçe Adı:</th>
                            <td><?php echo escape($district['name'] ?? ''); ?></td>
                        </tr>
                        <tr>
                            <th>Bağlı Olduğu Şehir:</th>
                            <td>
                                <?php if ($city): ?>
                                    <a href="index.php?page=city_detail&id=<?php echo $city['id']; ?>">
                                        <?php echo escape($city['name']); ?>
                                    </a>
                                <?php else: ?>
                                    -
                                <?php endif; ?>
                            </td>
                        </tr>
                        <tr>
                            <th>Belediye Başkanı:</th>
                            <td><?php echo escape($district['mayor_name'] ?? ''); ?></td>
                        </tr>
                        <tr>
                            <th>Parti:</th>
                            <td>
                                <?php if(isset($district['mayor_party']) && !empty($district['mayor_party'])): ?>
                                    <span class="badge bg-primary"><?php echo escape($district['mayor_party']); ?></span>
                                <?php else: ?>
                                    -
                                <?php endif; ?>
                            </td>
                        </tr>
                        <tr>
                            <th>Nüfus:</th>
                            <td><?php echo isset($district['population']) ? number_format($district['population']) : '-'; ?></td>
                        </tr>
                        <tr>
                            <th>Web Sitesi:</th>
                            <td>
                                <?php if(isset($district['website']) && !empty($district['website'])): ?>
                                    <a href="<?php echo escape($district['website']); ?>" target="_blank">
                                        <?php echo escape($district['website']); ?>
                                        <i class="fas fa-external-link-alt ms-1 small"></i>
                                    </a>
                                <?php else: ?>
                                    -
                                <?php endif; ?>
                            </td>
                        </tr>
                        <tr>
                            <th>E-posta:</th>
                            <td>
                                <?php if(isset($district['email']) && !empty($district['email'])): ?>
                                    <a href="mailto:<?php echo escape($district['email']); ?>">
                                        <?php echo escape($district['email']); ?>
                                    </a>
                                <?php else: ?>
                                    -
                                <?php endif; ?>
                            </td>
                        </tr>
                        <tr>
                            <th>Telefon:</th>
                            <td><?php echo escape($district['phone'] ?? '-'); ?></td>
                        </tr>
                        <tr>
                            <th>Adres:</th>
                            <td><?php echo escape($district['address'] ?? '-'); ?></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    
    <!-- İstatistikler Kartı -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-chart-bar me-2"></i> İstatistikler</h5>
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-6 mb-3">
                        <div class="card bg-info text-white">
                            <div class="card-body">
                                <div class="d-flex justify-content-between align-items-center">
                                    <div>
                                        <h6 class="mb-0">Gönderiler</h6>
                                        <h2 class="mb-0"><?php echo count($posts); ?></h2>
                                    </div>
                                    <div>
                                        <i class="fas fa-newspaper fa-2x"></i>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-6 mb-3">
                        <div class="card bg-success text-white">
                            <div class="card-body">
                                <div class="d-flex justify-content-between align-items-center">
                                    <div>
                                        <h6 class="mb-0">Duyurular</h6>
                                        <h2 class="mb-0"><?php echo count($announcements); ?></h2>
                                    </div>
                                    <div>
                                        <i class="fas fa-bullhorn fa-2x"></i>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <?php
                // Gönderi tipleri istatistikleri
                $post_types = [
                    'complaint' => ['count' => 0, 'name' => 'Şikayet', 'color' => 'danger'],
                    'suggestion' => ['count' => 0, 'name' => 'Öneri', 'color' => 'primary'],
                    'question' => ['count' => 0, 'name' => 'Soru', 'color' => 'warning'],
                    'thanks' => ['count' => 0, 'name' => 'Teşekkür', 'color' => 'success'],
                ];
                
                foreach ($posts as $post) {
                    if (isset($post['type']) && isset($post_types[$post['type']])) {
                        $post_types[$post['type']]['count']++;
                    }
                }
                ?>
                
                <?php if (!empty($posts)): ?>
                <h6 class="mt-4 mb-3">Gönderi Tipleri</h6>
                <?php foreach ($post_types as $type => $data): ?>
                    <div class="mb-2">
                        <div class="d-flex justify-content-between mb-1">
                            <span><?php echo $data['name']; ?></span>
                            <span><?php echo $data['count']; ?></span>
                        </div>
                        <div class="progress" style="height: 10px;">
                            <div class="progress-bar bg-<?php echo $data['color']; ?>" role="progressbar" 
                                 style="width: <?php echo count($posts) > 0 ? ($data['count'] / count($posts)) * 100 : 0; ?>%" 
                                 aria-valuenow="<?php echo $data['count']; ?>" aria-valuemin="0" aria-valuemax="<?php echo count($posts); ?>"></div>
                        </div>
                    </div>
                <?php endforeach; ?>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <!-- Son Gönderiler Kartı -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex align-items-center justify-content-between">
                    <h5 class="mb-0"><i class="fas fa-newspaper me-2"></i> Son Gönderiler</h5>
                    <span class="badge bg-primary"><?php echo count($posts); ?> Gönderi</span>
                </div>
            </div>
            <div class="card-body">
                <?php if(empty($posts)): ?>
                    <p class="text-center text-muted">Bu ilçeye ait gönderi bulunmuyor.</p>
                <?php else: ?>
                    <div class="list-group">
                        <?php 
                        $limited_posts = array_slice($posts, 0, 5);
                        foreach($limited_posts as $post): 
                            $type_classes = [
                                'complaint' => 'text-danger',
                                'suggestion' => 'text-primary',
                                'question' => 'text-warning',
                                'thanks' => 'text-success'
                            ];
                            $type_class = isset($post['type']) && isset($type_classes[$post['type']]) ? $type_classes[$post['type']] : 'text-secondary';
                        ?>
                            <a href="index.php?page=posts&id=<?php echo $post['id']; ?>" class="list-group-item list-group-item-action">
                                <div class="d-flex w-100 justify-content-between">
                                    <h6 class="mb-1"><?php echo escape(truncateText($post['title'] ?? '', 50)); ?></h6>
                                    <small class="<?php echo $type_class; ?>">
                                        <?php 
                                        if (isset($post['type'])) {
                                            switch($post['type']) {
                                                case 'complaint': echo 'Şikayet'; break;
                                                case 'suggestion': echo 'Öneri'; break;
                                                case 'question': echo 'Soru'; break;
                                                case 'thanks': echo 'Teşekkür'; break;
                                                default: echo ucfirst($post['type']); break;
                                            }
                                        }
                                        ?>
                                    </small>
                                </div>
                                <small class="text-muted">
                                    <?php echo isset($post['created_at']) ? formatDate($post['created_at']) : ''; ?>
                                </small>
                            </a>
                        <?php endforeach; ?>
                    </div>
                    
                    <?php if(count($posts) > 5): ?>
                        <div class="text-center mt-3">
                            <a href="index.php?page=posts&district=<?php echo urlencode($district['name']); ?>" class="btn btn-sm btn-outline-primary">
                                Tüm Gönderileri Görüntüle (<?php echo count($posts); ?>)
                            </a>
                        </div>
                    <?php endif; ?>
                <?php endif; ?>
            </div>
        </div>
    </div>
    
    <!-- Belediye Duyuruları Kartı -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex align-items-center justify-content-between">
                    <h5 class="mb-0"><i class="fas fa-bullhorn me-2"></i> Belediye Duyuruları</h5>
                    <span class="badge bg-primary"><?php echo count($announcements); ?> Duyuru</span>
                </div>
            </div>
            <div class="card-body">
                <?php if(empty($announcements)): ?>
                    <p class="text-center text-muted">Bu ilçeye ait duyuru bulunmuyor.</p>
                <?php else: ?>
                    <div class="list-group">
                        <?php 
                        $limited_announcements = array_slice($announcements, 0, 5);
                        foreach($limited_announcements as $announcement): 
                            $type_classes = [
                                'warning' => 'border-warning',
                                'info' => 'border-info',
                                'event' => 'border-success'
                            ];
                            $type_class = isset($announcement['announcement_type']) && isset($type_classes[$announcement['announcement_type']]) 
                                ? $type_classes[$announcement['announcement_type']] 
                                : 'border-secondary';
                        ?>
                            <div class="card mb-2 <?php echo $type_class; ?>">
                                <div class="card-body p-3">
                                    <h6 class="card-title"><?php echo escape(truncateText($announcement['title'] ?? '', 50)); ?></h6>
                                    <p class="card-text small"><?php echo escape(truncateText($announcement['content'] ?? '', 100)); ?></p>
                                    <div class="d-flex justify-content-between">
                                        <small class="text-muted">
                                            <?php echo isset($announcement['created_at']) ? formatDate($announcement['created_at']) : ''; ?>
                                        </small>
                                        <a href="index.php?page=announcements&id=<?php echo $announcement['id']; ?>" class="btn btn-sm btn-outline-primary">
                                            Detaylar
                                        </a>
                                    </div>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                    
                    <?php if(count($announcements) > 5): ?>
                        <div class="text-center mt-3">
                            <a href="index.php?page=announcements&municipality_id=<?php echo $district_id; ?>" class="btn btn-sm btn-outline-primary">
                                Tüm Duyuruları Görüntüle (<?php echo count($announcements); ?>)
                            </a>
                        </div>
                    <?php endif; ?>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>