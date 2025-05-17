<?php
// İstatistikleri al
$stats = getDashboardStats();

// Son aktiviteleri al
$activities = getRecentActivities(10);

// Gönderi kategorilerinin dağılımını al
$categories_distribution = getPostCategoriesDistribution();

// Siyasi parti dağılımını al
$party_distribution = getPoliticalPartyDistribution();
?>

<!-- Başlık ve Açıklama -->
<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h1 class="h3 mb-0">Dashboard</h1>
        <p class="text-muted">Bimer Belediye Yönetim Paneli</p>
    </div>
    <div class="text-end">
        <span class="badge bg-primary"><?php echo date('d.m.Y'); ?></span>
    </div>
</div>

<!-- İstatistik Kartları -->
<div class="row mb-4">
    <!-- Toplam Şehir Kartı -->
    <div class="col-xl-3 col-md-6">
        <div class="card border-start border-primary border-4">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="text-muted fw-normal mt-0">Toplam Şehir</h5>
                        <h2 class="my-2"><?php echo $stats['total_cities']; ?></h2>
                        <p class="mb-0 text-muted">
                            <a href="index.php?page=cities" class="text-decoration-none">Şehirleri Görüntüle <i class="fas fa-arrow-right ms-1"></i></a>
                        </p>
                    </div>
                    <div class="text-primary">
                        <i class="fas fa-city fa-3x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Aktif Kullanıcı Kartı -->
    <div class="col-xl-3 col-md-6">
        <div class="card border-start border-success border-4">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="text-muted fw-normal mt-0">Aktif Kullanıcı</h5>
                        <h2 class="my-2"><?php echo $stats['active_users']; ?></h2>
                        <p class="mb-0 text-muted">
                            <a href="index.php?page=users" class="text-decoration-none">Kullanıcıları Görüntüle <i class="fas fa-arrow-right ms-1"></i></a>
                        </p>
                    </div>
                    <div class="text-success">
                        <i class="fas fa-users fa-3x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Toplam Gönderi Kartı -->
    <div class="col-xl-3 col-md-6">
        <div class="card border-start border-info border-4">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="text-muted fw-normal mt-0">Toplam Gönderi</h5>
                        <h2 class="my-2"><?php echo $stats['total_posts']; ?></h2>
                        <p class="mb-0 text-muted">
                            <a href="index.php?page=posts" class="text-decoration-none">Gönderileri Görüntüle <i class="fas fa-arrow-right ms-1"></i></a>
                        </p>
                    </div>
                    <div class="text-info">
                        <i class="fas fa-newspaper fa-3x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Bekleyen Şikayet Kartı -->
    <div class="col-xl-3 col-md-6">
        <div class="card border-start border-warning border-4">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="text-muted fw-normal mt-0">Bekleyen Şikayet</h5>
                        <h2 class="my-2"><?php echo $stats['pending_complaints']; ?></h2>
                        <p class="mb-0 text-muted">
                            <a href="index.php?page=posts&type=complaint&resolved=false" class="text-decoration-none">Şikayetleri Görüntüle <i class="fas fa-arrow-right ms-1"></i></a>
                        </p>
                    </div>
                    <div class="text-warning">
                        <i class="fas fa-exclamation-circle fa-3x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Grafik ve Aktivite Kısımları -->
<div class="row">
    <!-- Sol Kısım: Grafikler -->
    <div class="col-xl-8">
        <!-- Gönderi Kategorileri Grafiği -->
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex justify-content-between align-items-center">
                    <h5 class="mb-0">Gönderi Kategorileri Dağılımı</h5>
                    <a href="index.php?page=posts" class="btn btn-sm btn-primary">Tümünü Görüntüle</a>
                </div>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table">
                        <thead>
                            <tr>
                                <th style="width: 40px;">#</th>
                                <th>Kategori</th>
                                <th>Sayı</th>
                                <th>Yüzde</th>
                                <th>Grafik</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach($categories_distribution as $index => $category): ?>
                                <tr>
                                    <td>
                                        <i class="fas <?php echo $category['icon']; ?>" style="color: <?php echo $category['color']; ?>"></i>
                                    </td>
                                    <td><?php echo $category['name']; ?></td>
                                    <td><?php echo $category['count']; ?></td>
                                    <td><?php echo $category['percentage']; ?>%</td>
                                    <td style="width: 40%;">
                                        <div class="progress">
                                            <div class="progress-bar" role="progressbar" 
                                                 style="width: <?php echo $category['percentage']; ?>%; background-color: <?php echo $category['color']; ?>" 
                                                 aria-valuenow="<?php echo $category['percentage']; ?>" 
                                                 aria-valuemin="0" aria-valuemax="100">
                                                <?php echo $category['percentage']; ?>%
                                            </div>
                                        </div>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        
        <!-- Siyasi Parti Dağılımı -->
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex justify-content-between align-items-center">
                    <h5 class="mb-0">Siyasi Parti Dağılımı</h5>
                    <a href="index.php?page=parties" class="btn btn-sm btn-primary">Tümünü Görüntüle</a>
                </div>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table">
                        <thead>
                            <tr>
                                <th style="width: 60px;">Logo</th>
                                <th>Parti</th>
                                <th>Yüzde</th>
                                <th>Grafik</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach($party_distribution as $party): ?>
                                <tr>
                                    <td>
                                        <?php if(!empty($party['logo'])): ?>
                                            <img src="<?php echo $party['logo']; ?>" alt="<?php echo $party['name']; ?>" width="40" height="40" class="img-thumbnail">
                                        <?php else: ?>
                                            <i class="fas fa-flag fa-2x"></i>
                                        <?php endif; ?>
                                    </td>
                                    <td><?php echo $party['name']; ?></td>
                                    <td><?php echo $party['percentage']; ?>%</td>
                                    <td style="width: 40%;">
                                        <div class="progress">
                                            <div class="progress-bar" role="progressbar" 
                                                 style="width: <?php echo $party['percentage']; ?>%; background-color: <?php echo $party['color']; ?>" 
                                                 aria-valuenow="<?php echo $party['percentage']; ?>" 
                                                 aria-valuemin="0" aria-valuemax="100">
                                                <?php echo $party['percentage']; ?>%
                                            </div>
                                        </div>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Sağ Kısım: Son Aktiviteler -->
    <div class="col-xl-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Son Aktiviteler</h5>
            </div>
            <div class="card-body p-0">
                <div class="list-group list-group-flush">
                    <?php if(empty($activities)): ?>
                        <div class="list-group-item py-3">
                            <p class="text-muted text-center mb-0">Henüz aktivite bulunmuyor.</p>
                        </div>
                    <?php else: ?>
                        <?php foreach($activities as $activity): ?>
                            <div class="list-group-item py-3">
                                <div class="d-flex">
                                    <div class="me-3">
                                        <?php if(!empty($activity['userAvatar'])): ?>
                                            <img src="<?php echo $activity['userAvatar']; ?>" alt="<?php echo $activity['username']; ?>" width="40" height="40" class="rounded-circle">
                                        <?php else: ?>
                                            <div class="avatar-circle">
                                                <span class="initials"><?php echo mb_substr($activity['username'], 0, 1, 'UTF-8'); ?></span>
                                            </div>
                                        <?php endif; ?>
                                    </div>
                                    <div>
                                        <p class="mb-1">
                                            <strong><?php echo escape($activity['username']); ?></strong> 
                                            <?php echo escape($activity['action']); ?>
                                            <?php if(!empty($activity['target'])): ?>
                                                <strong>"<?php echo escape($activity['target']); ?>"</strong>
                                            <?php endif; ?>
                                        </p>
                                        <small class="text-muted">
                                            <?php echo formatDate($activity['timestamp'], 'd.m.Y H:i'); ?>
                                        </small>
                                    </div>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </div>
                
                <div class="text-center p-3">
                    <a href="<?php echo $activity['type'] === 'post' ? 'index.php?page=posts' : 'index.php?page=comments'; ?>" class="btn btn-outline-primary btn-sm">
                        Tümünü Görüntüle
                    </a>
                </div>
            </div>
        </div>
    </div>
</div>

<style>
.avatar-circle {
    width: 40px;
    height: 40px;
    background-color: #0d6efd;
    text-align: center;
    border-radius: 50%;
    -webkit-border-radius: 50%;
    -moz-border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
}

.initials {
    position: relative;
    font-size: 20px;
    line-height: 40px;
    color: #fff;
    font-weight: bold;
}
</style>