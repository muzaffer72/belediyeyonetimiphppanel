<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');
// İstatistikleri al
$stats = getDashboardStats();

// Son aktiviteleri al
$activities = getRecentActivities(10);

// Gönderi kategorilerinin dağılımını al
$post_categories = getPostCategoriesDistribution();

// Siyasi parti dağılımını al
$party_distribution = getPoliticalPartyDistribution();
?>

<!-- İstatistik Kartları -->
<div class="row">
    <!-- Toplam Şehir Sayısı -->
    <div class="col-md-6 col-lg-3">
        <div class="stat-card primary">
            <div class="stat-card-icon">
                <i class="fas fa-city"></i>
            </div>
            <div class="stat-card-info">
                <div class="stat-card-value"><?php echo number_format($stats['total_cities']); ?></div>
                <div class="stat-card-label">Toplam Şehir</div>
            </div>
        </div>
    </div>
    
    <!-- Aktif Kullanıcı Sayısı -->
    <div class="col-md-6 col-lg-3">
        <div class="stat-card info">
            <div class="stat-card-icon">
                <i class="fas fa-users"></i>
            </div>
            <div class="stat-card-info">
                <div class="stat-card-value"><?php echo number_format($stats['active_users']); ?></div>
                <div class="stat-card-label">Aktif Kullanıcı</div>
            </div>
        </div>
    </div>
    
    <!-- Toplam Gönderi Sayısı -->
    <div class="col-md-6 col-lg-3">
        <div class="stat-card success">
            <div class="stat-card-icon">
                <i class="fas fa-newspaper"></i>
            </div>
            <div class="stat-card-info">
                <div class="stat-card-value"><?php echo number_format($stats['total_posts']); ?></div>
                <div class="stat-card-label">Toplam Gönderi</div>
            </div>
        </div>
    </div>
    
    <!-- Bekleyen Şikayet Sayısı -->
    <div class="col-md-6 col-lg-3">
        <div class="stat-card warning">
            <div class="stat-card-icon">
                <i class="fas fa-exclamation-circle"></i>
            </div>
            <div class="stat-card-info">
                <div class="stat-card-value"><?php echo number_format($stats['pending_complaints']); ?></div>
                <div class="stat-card-label">Bekleyen Şikayet</div>
            </div>
        </div>
    </div>
</div>

<!-- Ana Kartlar -->
<div class="row">
    <!-- Son Aktiviteler -->
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <span><i class="fas fa-history me-2"></i> Son Aktiviteler</span>
            </div>
            <div class="card-body p-0">
                <ul class="timeline">
                    <?php if (empty($activities)): ?>
                    <li class="p-3 text-center">Henüz aktivite bulunmuyor.</li>
                    <?php else: ?>
                    <?php foreach ($activities as $activity): ?>
                    <li class="timeline-item">
                        <div class="timeline-badge">
                            <?php if ($activity['type'] === 'post'): ?>
                            <i class="fas fa-newspaper"></i>
                            <?php else: ?>
                            <i class="fas fa-comment"></i>
                            <?php endif; ?>
                        </div>
                        <div class="timeline-content">
                            <div class="d-flex justify-content-between">
                                <h6 class="fw-bold mb-1"><?php echo escape($activity['username']); ?></h6>
                                <span class="timeline-date">
                                    <i class="fas fa-clock me-1"></i>
                                    <?php echo formatDate($activity['timestamp']); ?>
                                </span>
                            </div>
                            <p class="mb-0">
                                <strong><?php echo escape($activity['action']); ?>:</strong> 
                                <?php echo escape($activity['target']); ?>
                            </p>
                        </div>
                    </li>
                    <?php endforeach; ?>
                    <?php endif; ?>
                </ul>
            </div>
        </div>
    </div>
    
    <!-- Gönderi Kategorileri -->
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <span><i class="fas fa-chart-pie me-2"></i> Gönderi Kategorileri</span>
            </div>
            <div class="card-body">
                <?php if (empty($post_categories)): ?>
                <p class="text-center">Henüz veri bulunmuyor.</p>
                <?php else: ?>
                <div style="height: 250px; position: relative;">
                    <canvas id="postCategoriesChart"></canvas>
                </div>
                
                <div class="table-responsive mt-3">
                    <table class="table table-sm">
                        <thead>
                            <tr>
                                <th>Kategori</th>
                                <th>Sayı</th>
                                <th>Yüzde</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($post_categories as $category): ?>
                            <tr>
                                <td>
                                    <i class="fas <?php echo $category['icon']; ?>" style="color: <?php echo $category['color']; ?>"></i>
                                    <?php echo escape($category['name']); ?>
                                </td>
                                <td><?php echo $category['count']; ?></td>
                                <td><?php echo $category['percentage']; ?>%</td>
                            </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
                
                <script>
                    const postCategoriesData = <?php echo json_encode($post_categories); ?>;
                </script>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- Ek Kartlar -->
<div class="row">
    <!-- Siyasi Parti Dağılımı -->
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <span><i class="fas fa-flag me-2"></i> Siyasi Parti Dağılımı</span>
            </div>
            <div class="card-body">
                <?php if (empty($party_distribution)): ?>
                <p class="text-center">Henüz veri bulunmuyor.</p>
                <?php else: ?>
                <div style="height: 250px; position: relative;">
                    <canvas id="partyDistributionChart"></canvas>
                </div>
                
                <div class="table-responsive mt-3">
                    <table class="table table-sm">
                        <thead>
                            <tr>
                                <th>Parti</th>
                                <th>Şehir Sayısı</th>
                                <th>Yüzde</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($party_distribution as $party): ?>
                            <tr>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <?php if (!empty($party['logo'])): ?>
                                        <img src="<?php echo escape($party['logo']); ?>" alt="<?php echo escape($party['name']); ?>" class="me-2" style="width: 24px; height: 24px;">
                                        <?php else: ?>
                                        <span class="me-2" style="width: 24px; height: 24px; background-color: <?php echo $party['color']; ?>; display: inline-block; border-radius: 50%;"></span>
                                        <?php endif; ?>
                                        <?php echo escape($party['name']); ?>
                                    </div>
                                </td>
                                <td><?php echo $party['count']; ?></td>
                                <td><?php echo $party['percentage']; ?>%</td>
                            </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
                
                <script>
                    const partyDistributionData = <?php echo json_encode($party_distribution); ?>;
                </script>
                <?php endif; ?>
            </div>
        </div>
    </div>
    
    <!-- Parti Performans Skorları -->
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <span><i class="fas fa-chart-line me-2"></i> Parti Performans Skorları</span>
            </div>
            <div class="card-body">
                <?php
                // Partileri performans skorlarına göre al
                $party_scores_result = getData('political_parties', [
                    'order' => 'score.desc.nullslast',
                    'limit' => 5
                ]);
                $party_scores = $party_scores_result['data'];
                ?>
                
                <?php if (empty($party_scores)): ?>
                <p class="text-center">Henüz performans verisi bulunmuyor.</p>
                <?php else: ?>
                
                <div class="table-responsive">
                    <table class="table table-sm">
                        <thead>
                            <tr>
                                <th>Parti</th>
                                <th>Skor</th>
                                <th>Performans</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($party_scores as $party): ?>
                            <tr>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <?php if (!empty($party['logo_url'])): ?>
                                        <img src="<?php echo escape($party['logo_url']); ?>" alt="<?php echo escape($party['name']); ?>" class="me-2" style="width: 24px; height: 24px;">
                                        <?php else: ?>
                                        <i class="fas fa-flag me-2"></i>
                                        <?php endif; ?>
                                        <?php echo escape($party['name']); ?>
                                    </div>
                                </td>
                                <td>
                                    <strong><?php echo isset($party['score']) ? number_format(floatval($party['score']), 1) : 'N/A'; ?></strong>
                                </td>
                                <td>
                                    <?php 
                                    $score = isset($party['score']) ? floatval($party['score']) : 0;
                                    $scoreClass = 'bg-secondary';
                                    
                                    if ($score >= 80) $scoreClass = 'bg-success';
                                    elseif ($score >= 60) $scoreClass = 'bg-info';
                                    elseif ($score >= 40) $scoreClass = 'bg-warning';
                                    elseif ($score > 0) $scoreClass = 'bg-danger';
                                    ?>
                                    
                                    <div class="progress" style="height: 15px;">
                                        <div class="progress-bar <?php echo $scoreClass; ?>" role="progressbar" 
                                             style="width: <?php echo min(100, $score); ?>%" 
                                             aria-valuenow="<?php echo $score; ?>" 
                                             aria-valuemin="0" aria-valuemax="100">
                                            <?php echo number_format($score, 1); ?>
                                        </div>
                                    </div>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
                
                <div class="text-end mt-2">
                    <a href="index.php?page=parties" class="btn btn-sm btn-outline-primary">
                        <i class="fas fa-list me-1"></i> Tüm Partileri Görüntüle
                    </a>
                </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- En İyi İlçeler -->
<div class="row mt-4">
    <div class="col-md-12">
        <div class="card">
            <div class="card-header">
                <span><i class="fas fa-trophy me-2"></i> En İyi Performans Gösteren İlçeler</span>
            </div>
            <div class="card-body">
                <?php
                // En iyi performans gösteren ilçeleri çözüm oranlarına göre al
                $top_districts_result = getData('districts', [
                    'select' => 'id,name,city_id,solution_rate,total_complaints,solved_complaints,thanks_count,political_party_id',
                    'order' => 'solution_rate.desc.nullslast',
                    'limit' => 10
                ]);
                $top_districts = $top_districts_result['data'];
                
                // İlçelerin şehir ve parti bilgilerini al
                foreach ($top_districts as &$district) {
                    if (isset($district['city_id'])) {
                        $city_result = getDataById('cities', $district['city_id']);
                        $district['city_name'] = $city_result ? $city_result['name'] : 'Bilinmiyor';
                    } else {
                        $district['city_name'] = 'Bilinmiyor';
                    }
                    
                    if (isset($district['political_party_id'])) {
                        $party_result = getDataById('political_parties', $district['political_party_id']);
                        $district['party_name'] = $party_result ? $party_result['name'] : 'Bilinmiyor';
                    } else {
                        $district['party_name'] = 'Bilinmiyor';
                    }
                }
                unset($district); // İşaretçiyi kaldır
                ?>
                
                <?php if (empty($top_districts)): ?>
                <p class="text-center">Henüz ilçe performans verisi bulunmuyor.</p>
                <?php else: ?>
                <div class="table-responsive">
                    <table class="table table-striped">
                        <thead>
                            <tr>
                                <th>Sıra</th>
                                <th>İlçe</th>
                                <th>Şehir</th>
                                <th>Parti</th>
                                <th>Şikayet</th>
                                <th>Çözülen</th>
                                <th>Teşekkür</th>
                                <th>Çözüm Oranı</th>
                                <th>İşlemler</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($top_districts as $index => $district): ?>
                            <tr>
                                <td><?php echo $index + 1; ?></td>
                                <td><strong><?php echo escape($district['name']); ?></strong></td>
                                <td><?php echo escape($district['city_name']); ?></td>
                                <td><?php echo escape($district['party_name']); ?></td>
                                <td><?php echo isset($district['total_complaints']) ? intval($district['total_complaints']) : 0; ?></td>
                                <td><?php echo isset($district['solved_complaints']) ? intval($district['solved_complaints']) : 0; ?></td>
                                <td><?php echo isset($district['thanks_count']) ? intval($district['thanks_count']) : 0; ?></td>
                                <td>
                                    <?php 
                                    $solution_rate = isset($district['solution_rate']) ? floatval($district['solution_rate']) : 0;
                                    $rateClass = 'bg-secondary';
                                    
                                    if ($solution_rate >= 80) $rateClass = 'bg-success';
                                    elseif ($solution_rate >= 60) $rateClass = 'bg-info';
                                    elseif ($solution_rate >= 40) $rateClass = 'bg-warning';
                                    elseif ($solution_rate > 0) $rateClass = 'bg-danger';
                                    ?>
                                    
                                    <div class="progress" style="height: 15px;">
                                        <div class="progress-bar <?php echo $rateClass; ?>" role="progressbar" 
                                             style="width: <?php echo min(100, $solution_rate); ?>%" 
                                             aria-valuenow="<?php echo $solution_rate; ?>" 
                                             aria-valuemin="0" aria-valuemax="100">
                                            <?php echo number_format($solution_rate, 1); ?>%
                                        </div>
                                    </div>
                                </td>
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
                
                <div class="text-end mt-2">
                    <a href="index.php?page=districts" class="btn btn-sm btn-outline-primary">
                        <i class="fas fa-list me-1"></i> Tüm İlçeleri Görüntüle
                    </a>
                </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>