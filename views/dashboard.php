<?php
// İstatistikleri al
$cities_result = getData('cities');
$cities = $cities_result['data'];
$cities_count = count($cities);

$users_result = getData('users');
$users = $users_result['data'];
$users_count = count($users);

$posts_result = getData('posts');
$posts = $posts_result['data'];
$posts_count = count($posts);

// Çözülmemiş şikayetler
$pending_complaints = 0;
foreach ($posts as $post) {
    if (isset($post['type']) && $post['type'] === 'complaint' && isset($post['is_resolved']) && !$post['is_resolved']) {
        $pending_complaints++;
    }
}

// Parti dağılımını hesapla
$party_distribution = [];
foreach ($cities as $city) {
    if (isset($city['mayor_party'])) {
        $party = $city['mayor_party'];
        if (!isset($party_distribution[$party])) {
            $party_distribution[$party] = [
                'count' => 0,
                'name' => $party,
                'logo' => isset($city['party_logo_url']) ? $city['party_logo_url'] : ''
            ];
        }
        $party_distribution[$party]['count']++;
    }
}

// Son aktiviteler
$activities = [];
if (!empty($posts)) {
    // En son gönderilerden aktiviteler oluştur
    for ($i = 0; $i < min(5, count($posts)); $i++) {
        $post = $posts[$i];
        $activities[] = [
            'id' => $post['id'],
            'user' => isset($post['username']) ? $post['username'] : 'Anonim',
            'action' => isset($post['type']) ? ($post['type'] === 'complaint' ? 'şikayet' : ($post['type'] === 'suggestion' ? 'öneri' : 'gönderi')) . ' ekledi' : 'gönderi ekledi',
            'target' => isset($post['title']) ? $post['title'] : '',
            'time' => isset($post['created_at']) ? formatDate($post['created_at']) : '-'
        ];
    }
}
?>

<!-- İstatistik Kartları -->
<div class="row mb-4">
    <div class="col-md-3">
        <div class="card bg-primary text-white h-100">
            <div class="card-body py-5">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="text-uppercase">Toplam Şehir</h6>
                        <h1 class="display-4"><?php echo $cities_count; ?></h1>
                    </div>
                    <i class="fas fa-city fa-3x opacity-50"></i>
                </div>
            </div>
            <div class="card-footer d-flex">
                <a href="index.php?page=cities" class="text-white text-decoration-none">
                    Detayları Görüntüle
                    <i class="fas fa-arrow-circle-right ms-2"></i>
                </a>
            </div>
        </div>
    </div>
    
    <div class="col-md-3">
        <div class="card bg-success text-white h-100">
            <div class="card-body py-5">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="text-uppercase">Aktif Kullanıcılar</h6>
                        <h1 class="display-4"><?php echo $users_count; ?></h1>
                    </div>
                    <i class="fas fa-users fa-3x opacity-50"></i>
                </div>
            </div>
            <div class="card-footer d-flex">
                <a href="index.php?page=users" class="text-white text-decoration-none">
                    Detayları Görüntüle
                    <i class="fas fa-arrow-circle-right ms-2"></i>
                </a>
            </div>
        </div>
    </div>
    
    <div class="col-md-3">
        <div class="card bg-info text-white h-100">
            <div class="card-body py-5">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="text-uppercase">Toplam Gönderiler</h6>
                        <h1 class="display-4"><?php echo $posts_count; ?></h1>
                    </div>
                    <i class="fas fa-clipboard-list fa-3x opacity-50"></i>
                </div>
            </div>
            <div class="card-footer d-flex">
                <a href="index.php?page=posts" class="text-white text-decoration-none">
                    Detayları Görüntüle
                    <i class="fas fa-arrow-circle-right ms-2"></i>
                </a>
            </div>
        </div>
    </div>
    
    <div class="col-md-3">
        <div class="card bg-warning text-white h-100">
            <div class="card-body py-5">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="text-uppercase">Bekleyen Şikayetler</h6>
                        <h1 class="display-4"><?php echo $pending_complaints; ?></h1>
                    </div>
                    <i class="fas fa-exclamation-triangle fa-3x opacity-50"></i>
                </div>
            </div>
            <div class="card-footer d-flex">
                <a href="index.php?page=posts" class="text-white text-decoration-none">
                    Detayları Görüntüle
                    <i class="fas fa-arrow-circle-right ms-2"></i>
                </a>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <!-- Son Aktiviteler -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-history me-1"></i>
                Son Aktiviteler
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-hover">
                        <thead>
                            <tr>
                                <th>Kullanıcı</th>
                                <th>İşlem</th>
                                <th>Hedef</th>
                                <th>Tarih</th>
                                <th></th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (empty($activities)): ?>
                                <tr>
                                    <td colspan="5" class="text-center">Henüz aktivite bulunmuyor.</td>
                                </tr>
                            <?php else: ?>
                                <?php foreach ($activities as $activity): ?>
                                    <tr>
                                        <td><?php echo escape($activity['user']); ?></td>
                                        <td><?php echo escape($activity['action']); ?></td>
                                        <td><?php echo escape($activity['target']); ?></td>
                                        <td><?php echo $activity['time']; ?></td>
                                        <td>
                                            <?php if (strpos($activity['action'], 'şikayet') !== false): ?>
                                                <span class="badge bg-danger">Şikayet</span>
                                            <?php elseif (strpos($activity['action'], 'öneri') !== false): ?>
                                                <span class="badge bg-success">Öneri</span>
                                            <?php else: ?>
                                                <span class="badge bg-info">Gönderi</span>
                                            <?php endif; ?>
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
    
    <!-- Parti Dağılımı -->
    <div class="col-md-6">
        <div class="card mb-4">
            <div class="card-header">
                <i class="fas fa-chart-pie me-1"></i>
                Şehirlerde Parti Dağılımı
            </div>
            <div class="card-body">
                <?php if (empty($party_distribution)): ?>
                    <p class="text-center">Parti dağılımı verisi bulunamadı.</p>
                <?php else: ?>
                    <div class="row">
                        <?php foreach ($party_distribution as $party): ?>
                            <div class="col-md-4 mb-3 text-center">
                                <div class="card">
                                    <div class="card-body">
                                        <?php if (!empty($party['logo'])): ?>
                                            <img src="<?php echo $party['logo']; ?>" alt="<?php echo $party['name']; ?> Logo" class="img-fluid mb-2" style="max-height: 50px;">
                                        <?php endif; ?>
                                        <h5 class="card-title"><?php echo $party['name']; ?></h5>
                                        <p class="card-text"><?php echo $party['count']; ?> Şehir</p>
                                    </div>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- Şehirler Listesi -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-city me-1"></i>
        Belediyeler Listesi
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-hover">
                <thead>
                    <tr>
                        <th>Logo</th>
                        <th>Şehir</th>
                        <th>Belediye Başkanı</th>
                        <th>Parti</th>
                        <th>Nüfus</th>
                        <th>Email</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($cities)): ?>
                        <tr>
                            <td colspan="7" class="text-center">Henüz şehir kaydı bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach ($cities as $city): ?>
                            <tr>
                                <td>
                                    <?php if (isset($city['logo_url']) && !empty($city['logo_url'])): ?>
                                        <img src="<?php echo $city['logo_url']; ?>" alt="<?php echo isset($city['name']) ? $city['name'] : ''; ?> Logo" width="50">
                                    <?php else: ?>
                                        <i class="fas fa-city fa-2x text-muted"></i>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($city['name']) ? escape($city['name']) : ''; ?></td>
                                <td><?php echo isset($city['mayor_name']) ? escape($city['mayor_name']) : ''; ?></td>
                                <td>
                                    <?php if (isset($city['mayor_party']) && !empty($city['mayor_party'])): ?>
                                        <span class="badge bg-primary"><?php echo escape($city['mayor_party']); ?></span>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($city['population']) ? escape($city['population']) : ''; ?></td>
                                <td><?php echo isset($city['email']) ? escape($city['email']) : ''; ?></td>
                                <td>
                                    <a href="index.php?page=city_detail&id=<?php echo $city['id']; ?>" class="btn btn-sm btn-info">
                                        <i class="fas fa-eye"></i>
                                    </a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>