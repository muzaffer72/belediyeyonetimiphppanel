<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz parti ID\'si';
    $_SESSION['message_type'] = 'danger';
    safeRedirect('index.php?page=parties');
}

// Parti bilgilerini al
$party_id = $_GET['id'];
$party = getDataById('political_parties', $party_id);

if (!$party) {
    $_SESSION['message'] = 'Parti bulunamadı';
    $_SESSION['message_type'] = 'danger';
    safeRedirect('index.php?page=parties');
}

// Veritabanından bu partinin yönettiği ilçeleri al
$districts_result = getData('districts', ['political_party_id' => 'eq.' . $party_id]);
$party_districts = $districts_result['data'];

// Veritabanından bu partinin yönettiği şehirleri al
$cities_result = getData('cities', ['political_party_id' => 'eq.' . $party_id]);
$party_cities = $cities_result['data'];

// Parti performans verileri
$party_score = floatval($party['score'] ?? 0);
$total_complaints = intval($party['parti_sikayet_sayisi'] ?? 0);
$solved_complaints = intval($party['parti_cozulmus_sikayet_sayisi'] ?? 0);
$thanks_count = intval($party['parti_tesekkur_sayisi'] ?? 0);

// Parti renklerini ayarla (varsayılan değerler)
$party_color = '#007bff'; // Varsayılan mavi
$party_secondary_color = '#6610f2'; // Varsayılan mor

// Parti adına göre farklı renk atamaları
if (stripos($party['name'], 'cumhuriyet') !== false) {
    $party_color = '#e30613'; // Kırmızı
    $party_secondary_color = '#d9534f';
} elseif (stripos($party['name'], 'adalet') !== false) {
    $party_color = '#f8a300'; // Turuncu
    $party_secondary_color = '#fd7e14';
} elseif (stripos($party['name'], 'millet') !== false) {
    $party_color = '#003f72'; // Lacivert
    $party_secondary_color = '#0056b3';
} elseif (stripos($party['name'], 'demokrat') !== false) {
    $party_color = '#2a3f8e'; // Koyu mavi
    $party_secondary_color = '#0d6efd';
} elseif (stripos($party['name'], 'yeşil') !== false || stripos($party['name'], 'yesil') !== false) {
    $party_color = '#28a745'; // Yeşil
    $party_secondary_color = '#20c997';
}

// Çözüm oranını hesapla
$solution_rate = 0;
if ($total_complaints + $thanks_count > 0) {
    $solution_rate = (($solved_complaints + $thanks_count) / ($total_complaints + $thanks_count)) * 100;
}

// En iyi performans gösteren 5 ilçe
$top_districts = [];
foreach ($party_districts as $district) {
    $top_districts[] = [
        'name' => $district['name'],
        'solution_rate' => floatval($district['solution_rate'] ?? 0),
        'city_id' => $district['city_id']
    ];
}

// Çözüm oranına göre sırala
usort($top_districts, function($a, $b) {
    return $b['solution_rate'] <=> $a['solution_rate'];
});

// Sadece ilk 5 ilçeyi al
$top_districts = array_slice($top_districts, 0, 5);

// İlçelerin şehir isimlerini al
foreach ($top_districts as &$district) {
    $city = getDataById('cities', $district['city_id']);
    $district['city_name'] = $city ? $city['name'] : 'Bilinmiyor';
}
unset($district); // referansı temizle

// Diğer partileri al ve karşılaştırma için hazırla
$all_parties_result = getData('political_parties', ['id' => 'neq.' . $party_id]);
$other_parties = $all_parties_result['data'];

// Skora göre sırala
usort($other_parties, function($a, $b) {
    return floatval($b['score'] ?? 0) <=> floatval($a['score'] ?? 0);
});

// Sadece ilk 5 partiyi al (karşılaştırma için)
$compare_parties = array_slice($other_parties, 0, 5);
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3"><?php echo escape($party['name']); ?> Performans Analizi</h1>
    
    <div>
        <a href="index.php?page=parties" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Partiler Listesine Dön
        </a>
    </div>
</div>

<!-- Performans Özeti -->
<div class="row mb-4">
    <div class="col-md-3 mb-3">
        <div class="card bg-primary text-white h-100">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0">Parti Performans Skoru</h6>
                        <h2 class="mb-0"><?php echo number_format($party_score, 1); ?></h2>
                    </div>
                    <div>
                        <i class="fas fa-star fa-2x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-3 mb-3">
        <div class="card bg-danger text-white h-100">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0">Toplam Şikayet</h6>
                        <h2 class="mb-0"><?php echo number_format($total_complaints); ?></h2>
                    </div>
                    <div>
                        <i class="fas fa-exclamation-circle fa-2x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-3 mb-3">
        <div class="card bg-success text-white h-100">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0">Çözülen Şikayet</h6>
                        <h2 class="mb-0"><?php echo number_format($solved_complaints); ?></h2>
                    </div>
                    <div>
                        <i class="fas fa-check-circle fa-2x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-3 mb-3">
        <div class="card bg-info text-white h-100">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0">Teşekkür Sayısı</h6>
                        <h2 class="mb-0"><?php echo number_format($thanks_count); ?></h2>
                    </div>
                    <div>
                        <i class="fas fa-thumbs-up fa-2x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <!-- Parti Bilgileri ve Genel Değerlendirme -->
    <div class="col-md-4 mb-4">
        <div class="card h-100">
            <div class="card-header" style="background-color: <?php echo $party_color; ?>; color: white;">
                <div class="d-flex align-items-center">
                    <?php if(isset($party['logo_url']) && !empty($party['logo_url'])): ?>
                        <img src="<?php echo escape($party['logo_url']); ?>" alt="<?php echo escape($party['name']); ?> Logo" height="40" class="me-2">
                    <?php else: ?>
                        <i class="fas fa-flag me-2"></i>
                    <?php endif; ?>
                    <h5 class="mb-0"><?php echo escape($party['name']); ?></h5>
                </div>
            </div>
            <div class="card-body">
                <div class="text-center mb-4">
                    <div class="position-relative" style="width: 150px; height: 150px; margin: 0 auto;">
                        <div class="position-absolute top-50 start-50 translate-middle text-center">
                            <h1 class="mb-0" style="color: <?php echo $party_color; ?>;"><?php echo number_format($party_score, 1); ?></h1>
                            <p class="mb-0 text-muted">Performans Puanı</p>
                        </div>
                        <canvas id="partyScoreChart" width="150" height="150"></canvas>
                    </div>
                </div>
                
                <div class="row text-center mb-4">
                    <div class="col-md-6 mb-3">
                        <div class="card bg-light">
                            <div class="card-body p-2">
                                <h6 class="card-title mb-1">Yönetilen Şehir</h6>
                                <p class="h4 mb-0"><?php echo count($party_cities); ?></p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-6 mb-3">
                        <div class="card bg-light">
                            <div class="card-body p-2">
                                <h6 class="card-title mb-1">Yönetilen İlçe</h6>
                                <p class="h4 mb-0"><?php echo count($party_districts); ?></p>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div>
                    <h6 class="mb-3">Performans Değerlendirmesi</h6>
                    <?php
                    $performance_class = '';
                    $performance_icon = '';
                    $performance_message = '';
                    
                    if ($party_score >= 80) {
                        $performance_class = 'text-success';
                        $performance_icon = 'fa-star';
                        $performance_message = 'Üstün performans! Bu parti vatandaş sorunlarının çözümünde çok başarılı.';
                    } elseif ($party_score >= 60) {
                        $performance_class = 'text-info';
                        $performance_icon = 'fa-thumbs-up';
                        $performance_message = 'İyi performans. Parti yönetimi vatandaş sorunlarına karşı duyarlı.';
                    } elseif ($party_score >= 40) {
                        $performance_class = 'text-warning';
                        $performance_icon = 'fa-meh';
                        $performance_message = 'Orta düzey performans. İyileştirme alanları mevcut.';
                    } else {
                        $performance_class = 'text-danger';
                        $performance_icon = 'fa-thumbs-down';
                        $performance_message = 'Düşük performans. Vatandaş sorunlarına çözüm üretme konusunda yetersiz.';
                    }
                    ?>
                    <div class="d-flex">
                        <div class="me-3">
                            <i class="fas <?php echo $performance_icon; ?> fa-2x <?php echo $performance_class; ?>"></i>
                        </div>
                        <div>
                            <p class="mb-0 <?php echo $performance_class; ?>"><?php echo $performance_message; ?></p>
                        </div>
                    </div>
                </div>
                
                <div class="mt-4">
                    <h6 class="mb-2">Son Güncelleme:</h6>
                    <p class="mb-0 text-muted">
                        <?php 
                        if (isset($party['last_updated'])) {
                            echo date('d.m.Y H:i', strtotime($party['last_updated']));
                        } else {
                            echo 'Belirtilmemiş';
                        }
                        ?>
                    </p>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Çözüm Oranı ve Şikayet Analizi -->
    <div class="col-md-4 mb-4">
        <div class="card h-100">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-chart-pie me-2"></i> Şikayet Çözüm Analizi</h5>
            </div>
            <div class="card-body">
                <div class="text-center mb-4">
                    <div style="height: 200px;">
                        <canvas id="solutionAnalysisChart"></canvas>
                    </div>
                </div>
                
                <div class="progress mb-3" style="height: 25px;">
                    <div class="progress-bar bg-success" role="progressbar" 
                         style="width: <?php echo min(100, $solution_rate); ?>%" 
                         aria-valuenow="<?php echo $solution_rate; ?>" 
                         aria-valuemin="0" aria-valuemax="100">
                        <?php echo number_format($solution_rate, 1); ?>% Çözüm Oranı
                    </div>
                </div>
                
                <div class="row text-center mb-4">
                    <div class="col-6">
                        <div class="d-flex flex-column">
                            <span class="text-muted">Toplam Şikayet</span>
                            <span class="h4"><?php echo number_format($total_complaints); ?></span>
                        </div>
                    </div>
                    <div class="col-6">
                        <div class="d-flex flex-column">
                            <span class="text-muted">Çözülen Şikayet</span>
                            <span class="h4"><?php echo number_format($solved_complaints); ?></span>
                        </div>
                    </div>
                </div>
                
                <div class="mt-3">
                    <h6 class="mb-3">Teşekkür-Şikayet Oranı</h6>
                    <div class="progress" style="height: 25px;">
                        <?php
                        $thanks_percentage = 0;
                        if ($total_complaints + $thanks_count > 0) {
                            $thanks_percentage = ($thanks_count / ($total_complaints + $thanks_count)) * 100;
                        }
                        ?>
                        <div class="progress-bar bg-info" role="progressbar" 
                             style="width: <?php echo min(100, $thanks_percentage); ?>%" 
                             aria-valuenow="<?php echo $thanks_percentage; ?>" 
                             aria-valuemin="0" aria-valuemax="100">
                            <?php echo number_format($thanks_percentage, 1); ?>% Teşekkür
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- En İyi Performans Gösteren İlçeler -->
    <div class="col-md-4 mb-4">
        <div class="card h-100">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-trophy me-2"></i> En İyi İlçeler</h5>
            </div>
            <div class="card-body">
                <?php if (empty($top_districts)): ?>
                    <p class="text-muted">Bu partinin yönettiği ilçe bulunamadı.</p>
                <?php else: ?>
                    <div style="height: 250px;">
                        <canvas id="topDistrictsChart"></canvas>
                    </div>
                    
                    <div class="table-responsive mt-3">
                        <table class="table table-sm">
                            <thead>
                                <tr>
                                    <th>İlçe</th>
                                    <th>Şehir</th>
                                    <th>Çözüm Oranı</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($top_districts as $idx => $district): ?>
                                <tr>
                                    <td>
                                        <?php if ($idx < 3): ?>
                                            <i class="fas fa-medal me-1 text-<?php echo $idx === 0 ? 'warning' : ($idx === 1 ? 'secondary' : 'danger'); ?>"></i>
                                        <?php endif; ?>
                                        <?php echo escape($district['name']); ?>
                                    </td>
                                    <td><?php echo escape($district['city_name']); ?></td>
                                    <td>
                                        <div class="progress" style="height: 10px;">
                                            <div class="progress-bar bg-success" role="progressbar" 
                                                 style="width: <?php echo min(100, $district['solution_rate']); ?>%" 
                                                 aria-valuenow="<?php echo $district['solution_rate']; ?>" 
                                                 aria-valuemin="0" aria-valuemax="100">
                                            </div>
                                        </div>
                                        <span class="small"><?php echo number_format($district['solution_rate'], 1); ?>%</span>
                                    </td>
                                </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <!-- Partiler Arası Karşılaştırma -->
    <div class="col-md-6 mb-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-balance-scale me-2"></i> Parti Karşılaştırması</h5>
            </div>
            <div class="card-body">
                <?php if (empty($compare_parties)): ?>
                    <p class="text-muted">Karşılaştırma için başka parti bulunamadı.</p>
                <?php else: ?>
                    <div style="height: 300px;">
                        <canvas id="partyComparisonChart"></canvas>
                    </div>
                    
                    <div class="table-responsive mt-4">
                        <table class="table table-sm table-striped">
                            <thead>
                                <tr>
                                    <th>Parti</th>
                                    <th>Puan</th>
                                    <th>Çözüm Oranı</th>
                                    <th>Şikayet</th>
                                    <th>Teşekkür</th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr class="table-primary">
                                    <td><strong><?php echo escape($party['name']); ?></strong></td>
                                    <td><strong><?php echo number_format($party_score, 1); ?></strong></td>
                                    <td><?php echo number_format($solution_rate, 1); ?>%</td>
                                    <td><?php echo number_format($total_complaints); ?></td>
                                    <td><?php echo number_format($thanks_count); ?></td>
                                </tr>
                                <?php foreach($compare_parties as $p): ?>
                                    <?php 
                                    $p_solution_rate = 0;
                                    $p_total = intval($p['parti_sikayet_sayisi'] ?? 0);
                                    $p_solved = intval($p['parti_cozulmus_sikayet_sayisi'] ?? 0);
                                    $p_thanks = intval($p['parti_tesekkur_sayisi'] ?? 0);
                                    
                                    if ($p_total + $p_thanks > 0) {
                                        $p_solution_rate = (($p_solved + $p_thanks) / ($p_total + $p_thanks)) * 100;
                                    }
                                    ?>
                                    <tr>
                                        <td><?php echo escape($p['name']); ?></td>
                                        <td><?php echo number_format(floatval($p['score'] ?? 0), 1); ?></td>
                                        <td><?php echo number_format($p_solution_rate, 1); ?>%</td>
                                        <td><?php echo number_format($p_total); ?></td>
                                        <td><?php echo number_format($p_thanks); ?></td>
                                    </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
    
    <!-- Yönetilen Şehirler ve İlçeler -->
    <div class="col-md-6 mb-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-city me-2"></i> Yönetilen Bölgeler</h5>
            </div>
            <div class="card-body">
                <ul class="nav nav-tabs" id="regionsTab" role="tablist">
                    <li class="nav-item" role="presentation">
                        <button class="nav-link active" id="cities-tab" data-bs-toggle="tab" data-bs-target="#cities" type="button" role="tab" aria-controls="cities" aria-selected="true">
                            <i class="fas fa-city me-1"></i> Şehirler (<?php echo count($party_cities); ?>)
                        </button>
                    </li>
                    <li class="nav-item" role="presentation">
                        <button class="nav-link" id="districts-tab" data-bs-toggle="tab" data-bs-target="#districts" type="button" role="tab" aria-controls="districts" aria-selected="false">
                            <i class="fas fa-map-marker-alt me-1"></i> İlçeler (<?php echo count($party_districts); ?>)
                        </button>
                    </li>
                </ul>
                <div class="tab-content p-3" id="regionsTabContent">
                    <!-- Şehirler Tab -->
                    <div class="tab-pane fade show active" id="cities" role="tabpanel" aria-labelledby="cities-tab">
                        <?php if (empty($party_cities)): ?>
                            <p class="text-muted">Bu parti tarafından yönetilen şehir bulunamadı.</p>
                        <?php else: ?>
                            <div class="table-responsive">
                                <table class="table table-striped table-hover">
                                    <thead>
                                        <tr>
                                            <th>Şehir</th>
                                            <th>Tür</th>
                                            <th>Çözüm Oranı</th>
                                            <th>Belediye Başkanı</th>
                                            <th>İşlemler</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php foreach ($party_cities as $city): ?>
                                        <tr>
                                            <td><?php echo escape($city['name']); ?></td>
                                            <td>
                                                <?php if (isset($city['is_metropolitan']) && $city['is_metropolitan']): ?>
                                                    <span class="badge bg-primary">Büyükşehir</span>
                                                <?php else: ?>
                                                    <span class="badge bg-secondary">Normal</span>
                                                <?php endif; ?>
                                            </td>
                                            <td>
                                                <div class="progress" style="height: 10px;">
                                                    <div class="progress-bar bg-success" role="progressbar" 
                                                         style="width: <?php echo min(100, floatval($city['solution_rate'] ?? 0)); ?>%" 
                                                         aria-valuenow="<?php echo floatval($city['solution_rate'] ?? 0); ?>" 
                                                         aria-valuemin="0" aria-valuemax="100">
                                                    </div>
                                                </div>
                                                <span class="small"><?php echo number_format(floatval($city['solution_rate'] ?? 0), 1); ?>%</span>
                                            </td>
                                            <td><?php echo escape($city['mayor'] ?? 'Belirtilmemiş'); ?></td>
                                            <td>
                                                <a href="index.php?page=city_detail&id=<?php echo $city['id']; ?>" class="btn btn-sm btn-info">
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
                    
                    <!-- İlçeler Tab -->
                    <div class="tab-pane fade" id="districts" role="tabpanel" aria-labelledby="districts-tab">
                        <?php if (empty($party_districts)): ?>
                            <p class="text-muted">Bu parti tarafından yönetilen ilçe bulunamadı.</p>
                        <?php else: ?>
                            <div class="table-responsive">
                                <table class="table table-striped table-hover">
                                    <thead>
                                        <tr>
                                            <th>İlçe</th>
                                            <th>Şehir</th>
                                            <th>Çözüm Oranı</th>
                                            <th>Belediye Başkanı</th>
                                            <th>İşlemler</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php foreach ($party_districts as $district): 
                                            $city_name = '';
                                            if (isset($district['city_id'])) {
                                                $city = getDataById('cities', $district['city_id']);
                                                if ($city) {
                                                    $city_name = $city['name'];
                                                }
                                            }
                                        ?>
                                        <tr>
                                            <td><?php echo escape($district['name']); ?></td>
                                            <td><?php echo escape($city_name); ?></td>
                                            <td>
                                                <div class="progress" style="height: 10px;">
                                                    <div class="progress-bar bg-success" role="progressbar" 
                                                         style="width: <?php echo min(100, floatval($district['solution_rate'] ?? 0)); ?>%" 
                                                         aria-valuenow="<?php echo floatval($district['solution_rate'] ?? 0); ?>" 
                                                         aria-valuemin="0" aria-valuemax="100">
                                                    </div>
                                                </div>
                                                <span class="small"><?php echo number_format(floatval($district['solution_rate'] ?? 0), 1); ?>%</span>
                                            </td>
                                            <td><?php echo escape($district['mayor_name'] ?? 'Belirtilmemiş'); ?></td>
                                            <td>
                                                <a href="index.php?page=district_detail&id=<?php echo $district['id']; ?>" class="btn btn-sm btn-info">
                                                    <i class="fas fa-eye"></i>
                                                </a>
                                                <a href="index.php?page=district_performance&id=<?php echo $district['id']; ?>" class="btn btn-sm btn-primary">
                                                    <i class="fas fa-chart-line"></i>
                                                </a>
                                            </td>
                                        </tr>
                                        <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Performans Verilerini Güncelle (Admin) -->
<?php if (isAdmin()): ?>
<div class="card mb-4">
    <div class="card-header">
        <h5 class="mb-0"><i class="fas fa-sync me-2"></i> Parti Performans Verilerini Güncelle</h5>
    </div>
    <div class="card-body">
        <form action="index.php?page=update_party_performance" method="post" class="row g-3">
            <input type="hidden" name="party_id" value="<?php echo $party_id; ?>">
            
            <div class="col-md-3">
                <label for="party_score" class="form-label">Performans Puanı</label>
                <input type="number" class="form-control" id="party_score" name="party_score" value="<?php echo $party_score; ?>" min="0" max="100" step="0.1">
            </div>
            
            <div class="col-md-3">
                <label for="parti_sikayet_sayisi" class="form-label">Toplam Şikayet</label>
                <input type="number" class="form-control" id="parti_sikayet_sayisi" name="parti_sikayet_sayisi" value="<?php echo $total_complaints; ?>" min="0">
            </div>
            
            <div class="col-md-3">
                <label for="parti_cozulmus_sikayet_sayisi" class="form-label">Çözülen Şikayet</label>
                <input type="number" class="form-control" id="parti_cozulmus_sikayet_sayisi" name="parti_cozulmus_sikayet_sayisi" value="<?php echo $solved_complaints; ?>" min="0">
            </div>
            
            <div class="col-md-3">
                <label for="parti_tesekkur_sayisi" class="form-label">Teşekkür Sayısı</label>
                <input type="number" class="form-control" id="parti_tesekkur_sayisi" name="parti_tesekkur_sayisi" value="<?php echo $thanks_count; ?>" min="0">
            </div>
            
            <div class="col-12">
                <button type="submit" class="btn btn-primary">
                    <i class="fas fa-save me-1"></i> Değerleri Kaydet
                </button>
                <button type="button" class="btn btn-success ms-2" id="calculateScoreButton">
                    <i class="fas fa-calculator me-1"></i> Skoru Hesapla
                </button>
                <button type="button" class="btn btn-info ms-2" id="refreshPartDataButton">
                    <i class="fas fa-sync-alt me-1"></i> Veritabanından Yenile
                </button>
                <button type="button" class="btn btn-warning ms-2" id="recalculateAllButton">
                    <i class="fas fa-database me-1"></i> Tüm Parti Skorlarını Yeniden Hesapla
                </button>
            </div>
        </form>
    </div>
</div>
<?php endif; ?>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Parti Puanı Grafiği
    var scoreCtx = document.getElementById('partyScoreChart').getContext('2d');
    var partyScoreChart = new Chart(scoreCtx, {
        type: 'doughnut',
        data: {
            datasets: [{
                data: [
                    <?php echo $party_score; ?>,
                    <?php echo 100 - $party_score; ?>
                ],
                backgroundColor: [
                    '<?php echo $party_color; ?>',
                    'rgba(233, 236, 239, 0.5)'
                ],
                borderWidth: 0
            }]
        },
        options: {
            cutout: '80%',
            responsive: true,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    enabled: false
                }
            }
        }
    });
    
    // Şikayet Çözüm Analizi Grafiği
    var solutionCtx = document.getElementById('solutionAnalysisChart').getContext('2d');
    var solutionAnalysisChart = new Chart(solutionCtx, {
        type: 'bar',
        data: {
            labels: ['Şikayetler', 'Çözülenler', 'Teşekkürler'],
            datasets: [{
                label: 'Sayı',
                data: [
                    <?php echo $total_complaints; ?>,
                    <?php echo $solved_complaints; ?>,
                    <?php echo $thanks_count; ?>
                ],
                backgroundColor: [
                    'rgba(220, 53, 69, 0.7)',
                    'rgba(40, 167, 69, 0.7)',
                    'rgba(13, 202, 240, 0.7)'
                ],
                borderColor: [
                    'rgba(220, 53, 69, 1)',
                    'rgba(40, 167, 69, 1)',
                    'rgba(13, 202, 240, 1)'
                ],
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            scales: {
                y: {
                    beginAtZero: true
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
    
    <?php if(!empty($top_districts)): ?>
    // En İyi İlçeler Grafiği
    var topDistrictsCtx = document.getElementById('topDistrictsChart').getContext('2d');
    var topDistrictsChart = new Chart(topDistrictsCtx, {
        type: 'horizontalBar',
        data: {
            labels: [
                <?php 
                $district_labels = array_map(function($d) {
                    return "'" . escape($d['name']) . "'";
                }, $top_districts);
                echo implode(', ', $district_labels);
                ?>
            ],
            datasets: [{
                label: 'Çözüm Oranı (%)',
                data: [
                    <?php 
                    $district_rates = array_map(function($d) {
                        return $d['solution_rate'];
                    }, $top_districts);
                    echo implode(', ', $district_rates);
                    ?>
                ],
                backgroundColor: '<?php echo $party_color; ?>',
                borderWidth: 0
            }]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            scales: {
                x: {
                    beginAtZero: true,
                    max: 100
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
    <?php endif; ?>
    
    <?php if(!empty($compare_parties)): ?>
    // Parti Karşılaştırma Grafiği
    var comparisonCtx = document.getElementById('partyComparisonChart').getContext('2d');
    var partyComparisonChart = new Chart(comparisonCtx, {
        type: 'bar',
        data: {
            labels: [
                '<?php echo escape($party['name']); ?>',
                <?php 
                $party_labels = array_map(function($p) {
                    return "'" . escape($p['name']) . "'";
                }, $compare_parties);
                echo implode(', ', $party_labels);
                ?>
            ],
            datasets: [{
                label: 'Performans Puanı',
                data: [
                    <?php echo $party_score; ?>,
                    <?php 
                    $party_scores = array_map(function($p) {
                        return floatval($p['score'] ?? 0);
                    }, $compare_parties);
                    echo implode(', ', $party_scores);
                    ?>
                ],
                backgroundColor: [
                    '<?php echo $party_color; ?>',
                    <?php 
                    $colors = array_fill(0, count($compare_parties), "'rgba(108, 117, 125, 0.7)'");
                    echo implode(', ', $colors);
                    ?>
                ],
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
    <?php endif; ?>
    
    <?php if (isAdmin()): ?>
    // Skoru Hesapla Butonu
    document.getElementById('calculateScoreButton').addEventListener('click', function() {
        const totalComplaints = parseInt(document.getElementById('parti_sikayet_sayisi').value) || 0;
        const solvedComplaints = parseInt(document.getElementById('parti_cozulmus_sikayet_sayisi').value) || 0;
        const thanksCount = parseInt(document.getElementById('parti_tesekkur_sayisi').value) || 0;
        
        let solutionRate = 0;
        if (totalComplaints + thanksCount > 0) {
            solutionRate = ((solvedComplaints + thanksCount) / (totalComplaints + thanksCount)) * 100;
        }
        
        // Çözüm oranını puanlamada kullan
        let score = solutionRate;
        
        // Puan 100'den büyük olamaz
        score = Math.min(score, 100);
        
        // 1 ondalık basamağa yuvarla
        score = Math.round(score * 10) / 10;
        
        document.getElementById('party_score').value = score;
    });
    
    // Verileri Yenile Butonu
    document.getElementById('refreshPartDataButton').addEventListener('click', function() {
        if (confirm('Parti performans verilerini veritabanından yenilemek istediğinize emin misiniz?')) {
            window.location.href = 'index.php?page=party_performance&id=<?php echo $party_id; ?>&refresh=1';
        }
    });
    
    // Tüm Skorları Yeniden Hesapla Butonu
    document.getElementById('recalculateAllButton').addEventListener('click', function() {
        if (confirm('Tüm partilerin performans skorlarını yeniden hesaplamak istediğinize emin misiniz? Bu işlem uzun sürebilir.')) {
            window.location.href = 'index.php?page=update_party_scoring&recalculate=1&return=party_performance&party_id=<?php echo $party_id; ?>';
        }
    });
    <?php endif; ?>
});
</script>