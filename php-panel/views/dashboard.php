<?php
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
    <div class="col-md-12">
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
</div>