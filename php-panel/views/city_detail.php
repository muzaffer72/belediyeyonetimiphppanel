<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz şehir ID\'si';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=cities');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cities";</script>';
        exit;
    }
}

// Şehir bilgilerini al
$city_id = $_GET['id'];
$city = getDataById('cities', $city_id);

if (!$city) {
    $_SESSION['message'] = 'Şehir bulunamadı';
    $_SESSION['message_type'] = 'danger';
    
    // Ana sayfaya yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=cities');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cities";</script>';
        exit;
    }
}

// İlçe verilerini al
$districts_result = getData('districts', ['city_id' => 'eq.' . $city_id]);
$districts = $districts_result['data'];

// Parti verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'];

// Gönderi verilerini al
$posts_result = getData('posts', ['city' => 'eq.' . $city['name']]);
$posts = $posts_result['data'];

// Belediye duyurularını al
$announcements_result = getData('municipality_announcements', ['municipality_id' => 'eq.' . $city_id]);
$announcements = $announcements_result['data'];
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3"><?php echo escape($city['name']); ?> Detayları</h1>
    
    <div>
        <a href="index.php?page=city_edit&id=<?php echo $city_id; ?>" class="btn btn-warning me-2">
            <i class="fas fa-edit me-1"></i> Düzenle
        </a>
        <a href="index.php?page=cities" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Şehirlere Dön
        </a>
    </div>
</div>

<?php if(isset($city['cover_image_url']) && !empty($city['cover_image_url'])): ?>
<div class="card mb-4">
    <div class="card-body p-0">
        <img src="<?php echo escape($city['cover_image_url']); ?>" alt="<?php echo escape($city['name']); ?> Kapak" class="img-fluid w-100" style="max-height: 300px; object-fit: cover;">
    </div>
</div>
<?php endif; ?>

<div class="row">
    <!-- Şehir Bilgileri Kartı -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex align-items-center">
                    <?php if(isset($city['logo_url']) && !empty($city['logo_url'])): ?>
                        <img src="<?php echo escape($city['logo_url']); ?>" alt="<?php echo escape($city['name']); ?> Logo" height="40" class="me-2">
                    <?php else: ?>
                        <i class="fas fa-city me-2"></i>
                    <?php endif; ?>
                    <h5 class="mb-0">Şehir Bilgileri</h5>
                </div>
            </div>
            <div class="card-body">
                <table class="table table-striped">
                    <tbody>
                        <tr>
                            <th style="width: 150px;">Şehir Adı:</th>
                            <td><?php echo escape($city['name'] ?? ''); ?></td>
                        </tr>
                        <tr>
                            <th>Belediye Başkanı:</th>
                            <td><?php echo escape($city['mayor_name'] ?? ''); ?></td>
                        </tr>
                        <tr>
                            <th>Parti:</th>
                            <td>
                                <?php if(isset($city['political_party_id']) && !empty($city['political_party_id'])): ?>
                                    <?php 
                                    // Parti bilgilerini getir
                                    $party_name = '-';
                                    foreach($parties as $party) {
                                        if($party['id'] == $city['political_party_id']) {
                                            $party_name = $party['name'];
                                            break;
                                        }
                                    }
                                    ?>
                                    <span class="badge bg-primary"><?php echo escape($party_name); ?></span>
                                <?php else: ?>
                                    -
                                <?php endif; ?>
                            </td>
                        </tr>
                        <tr>
                            <th>Nüfus:</th>
                            <td><?php echo isset($city['population']) ? number_format($city['population']) : '-'; ?></td>
                        </tr>
                        <tr>
                            <th>Web Sitesi:</th>
                            <td>
                                <?php if(isset($city['website']) && !empty($city['website'])): ?>
                                    <a href="<?php echo escape($city['website']); ?>" target="_blank">
                                        <?php echo escape($city['website']); ?>
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
                                <?php if(isset($city['email']) && !empty($city['email'])): ?>
                                    <a href="mailto:<?php echo escape($city['email']); ?>">
                                        <?php echo escape($city['email']); ?>
                                    </a>
                                <?php else: ?>
                                    -
                                <?php endif; ?>
                            </td>
                        </tr>
                        <tr>
                            <th>Telefon:</th>
                            <td><?php echo escape($city['phone'] ?? '-'); ?></td>
                        </tr>
                        <tr>
                            <th>Adres:</th>
                            <td><?php echo escape($city['address'] ?? '-'); ?></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    
    <!-- İlçeler Kartı -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex align-items-center justify-content-between">
                    <h5 class="mb-0"><i class="fas fa-map-marker-alt me-2"></i> İlçeler</h5>
                    <span class="badge bg-primary"><?php echo count($districts); ?> İlçe</span>
                </div>
            </div>
            <div class="card-body">
                <?php if(empty($districts)): ?>
                    <p class="text-center text-muted">Bu şehre ait ilçe kaydı bulunmuyor.</p>
                <?php else: ?>
                    <div class="table-responsive">
                        <table class="table table-striped">
                            <thead>
                                <tr>
                                    <th>İlçe Adı</th>
                                    <th>Nüfus</th>
                                    <th>İşlemler</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach($districts as $district): ?>
                                    <tr>
                                        <td><?php echo escape($district['name'] ?? ''); ?></td>
                                        <td><?php echo isset($district['population']) ? number_format($district['population']) : '-'; ?></td>
                                        <td>
                                            <a href="index.php?page=district_detail&id=<?php echo $district['id']; ?>" class="btn btn-sm btn-info">
                                                <i class="fas fa-eye"></i>
                                            </a>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                <?php endif; ?>
            </div>
            <div class="card-footer">
                <a href="index.php?page=districts" class="btn btn-primary btn-sm">
                    <i class="fas fa-list me-1"></i> Tüm İlçeleri Görüntüle
                </a>
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
                    <p class="text-center text-muted">Bu şehre ait gönderi bulunmuyor.</p>
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
                            <a href="index.php?page=posts&city=<?php echo urlencode($city['name']); ?>" class="btn btn-sm btn-outline-primary">
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
                    <p class="text-center text-muted">Bu şehre ait duyuru bulunmuyor.</p>
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
                            <a href="index.php?page=announcements&municipality_id=<?php echo $city_id; ?>" class="btn btn-sm btn-outline-primary">
                                Tüm Duyuruları Görüntüle (<?php echo count($announcements); ?>)
                            </a>
                        </div>
                    <?php endif; ?>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>