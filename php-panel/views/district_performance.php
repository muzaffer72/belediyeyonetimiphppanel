<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz ilçe ID\'si';
    $_SESSION['message_type'] = 'danger';
    safeRedirect('index.php?page=districts');
}

// İlçe bilgilerini al
$district_id = $_GET['id'];
$district = getDataById('districts', $district_id);

if (!$district) {
    $_SESSION['message'] = 'İlçe bulunamadı';
    $_SESSION['message_type'] = 'danger';
    safeRedirect('index.php?page=districts');
}

// Bağlı olduğu şehri bul
$city = null;
if (isset($district['city_id'])) {
    $city = getDataById('cities', $district['city_id']);
}

// Parti verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'];

// Parti bilgisini bul
$party_info = null;
if(isset($district['political_party_id']) && !empty($district['political_party_id'])) {
    foreach($parties as $party) {
        if($party['id'] == $district['political_party_id']) {
            $party_info = $party;
            break;
        }
    }
}

// İlçenin bağlı olduğu il adını al
$city_name = $city ? $city['name'] : '';

// İlçe performans verilerini al
$district_solution_rate = floatval($district['solution_rate'] ?? 0);
$total_complaints = intval($district['total_complaints'] ?? 0);
$solved_complaints = intval($district['solved_complaints'] ?? 0);
$thanks_count = intval($district['thanks_count'] ?? 0);

// İstatistiksel verileri oluştur
$last_six_months = [];
$current_month = date('n');
$current_year = date('Y');

for($i = 5; $i >= 0; $i--) {
    $month = $current_month - $i;
    $year = $current_year;
    
    if($month <= 0) {
        $month += 12;
        $year--;
    }
    
    $month_name = date('F', mktime(0, 0, 0, $month, 1, $year));
    $last_six_months[] = [
        'month' => $month_name,
        'complaints' => rand(20, 100), // Örnek veri, gerçek veritabanı sorgularıyla değiştirilmeli
        'solved' => rand(10, 90),      // Örnek veri, gerçek veritabanı sorgularıyla değiştirilmeli
        'thanks' => rand(5, 30)        // Örnek veri, gerçek veritabanı sorgularıyla değiştirilmeli
    ];
}

// Benzer ilçelerle karşılaştırma
// Aynı şehirdeki diğer ilçeleri al
$similar_districts = [];
if (!empty($city)) {
    $districts_result = getData('districts', ['city_id' => 'eq.' . $city['id']]);
    $all_districts = $districts_result['data'];
    
    // Bu ilçe dışındaki ilçeleri filtrele
    foreach ($all_districts as $d) {
        if ($d['id'] != $district_id) {
            $similar_districts[] = $d;
        }
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3"><?php echo escape($district['name']); ?> İlçesi Performans Analizi</h1>
    
    <div>
        <a href="index.php?page=district_detail&id=<?php echo $district_id; ?>" class="btn btn-primary me-2">
            <i class="fas fa-info-circle me-1"></i> İlçe Detayları
        </a>
        <a href="index.php?page=districts" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> İlçelere Dön
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
                        <h6 class="mb-0">Çözüm Oranı</h6>
                        <h2 class="mb-0"><?php echo number_format($district_solution_rate, 1); ?>%</h2>
                    </div>
                    <div>
                        <i class="fas fa-chart-pie fa-2x"></i>
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
                        <h2 class="mb-0"><?php echo $total_complaints; ?></h2>
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
                        <h2 class="mb-0"><?php echo $solved_complaints; ?></h2>
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
                        <h2 class="mb-0"><?php echo $thanks_count; ?></h2>
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
    <!-- Çözüm Oranı Grafiği -->
    <div class="col-md-6 mb-4">
        <div class="card h-100">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-chart-pie me-2"></i> Çözüm Oranı Analizi</h5>
            </div>
            <div class="card-body">
                <div class="text-center mb-4">
                    <div class="position-relative" style="width: 200px; height: 200px; margin: 0 auto;">
                        <div class="position-absolute top-50 start-50 translate-middle text-center">
                            <h1 class="mb-0"><?php echo number_format($district_solution_rate, 1); ?>%</h1>
                            <p class="mb-0 text-muted">Çözüm Oranı</p>
                        </div>
                        <canvas id="solutionRateChart" width="200" height="200"></canvas>
                    </div>
                </div>
                
                <div class="row text-center">
                    <div class="col-md-6">
                        <div class="d-flex flex-column">
                            <span class="text-muted">Toplam Şikayet</span>
                            <span class="h4"><?php echo $total_complaints; ?></span>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="d-flex flex-column">
                            <span class="text-muted">Çözülen Şikayet</span>
                            <span class="h4"><?php echo $solved_complaints; ?></span>
                        </div>
                    </div>
                </div>
                
                <div class="mt-4">
                    <h6 class="mb-3">Performans Değerlendirmesi</h6>
                    <?php
                    $performance_class = '';
                    $performance_icon = '';
                    $performance_message = '';
                    
                    if ($district_solution_rate >= 80) {
                        $performance_class = 'text-success';
                        $performance_icon = 'fa-smile';
                        $performance_message = 'Mükemmel performans! İlçe yönetimi vatandaş sorunlarını çözmede çok başarılı.';
                    } elseif ($district_solution_rate >= 60) {
                        $performance_class = 'text-info';
                        $performance_icon = 'fa-smile';
                        $performance_message = 'İyi performans. İlçe yönetimi vatandaş sorunlarını çözme konusunda istikrarlı.';
                    } elseif ($district_solution_rate >= 40) {
                        $performance_class = 'text-warning';
                        $performance_icon = 'fa-meh';
                        $performance_message = 'Orta düzey performans. İyileştirme alanları mevcut.';
                    } else {
                        $performance_class = 'text-danger';
                        $performance_icon = 'fa-frown';
                        $performance_message = 'Düşük performans. İlçe yönetiminin sorun çözme süreçlerini gözden geçirmesi gerekiyor.';
                    }
                    ?>
                    <div class="d-flex">
                        <div class="me-3">
                            <i class="far <?php echo $performance_icon; ?> fa-2x <?php echo $performance_class; ?>"></i>
                        </div>
                        <div>
                            <p class="mb-0 <?php echo $performance_class; ?>"><?php echo $performance_message; ?></p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Aylık Trend Grafiği -->
    <div class="col-md-6 mb-4">
        <div class="card h-100">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-chart-line me-2"></i> Aylık Trend Analizi</h5>
            </div>
            <div class="card-body">
                <canvas id="monthlyTrendChart" height="280"></canvas>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <!-- Parti Performansı -->
    <?php if($party_info): ?>
    <div class="col-md-6 mb-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">
                    <i class="fas fa-vote-yea me-2"></i> 
                    <?php echo escape($party_info['name']); ?> Parti Performansı
                </h5>
            </div>
            <div class="card-body">
                <div class="d-flex align-items-center mb-4">
                    <?php if(!empty($party_info['logo_url'])): ?>
                        <img src="<?php echo escape($party_info['logo_url']); ?>" alt="<?php echo escape($party_info['name']); ?>" class="me-3" style="height: 50px; width: auto;">
                    <?php endif; ?>
                    <div>
                        <h4 class="mb-0"><?php echo escape($party_info['name']); ?></h4>
                        <p class="mb-0 text-muted"><?php echo escape($district['name']); ?> İlçesi Yönetimi</p>
                    </div>
                </div>
                
                <div class="mb-4">
                    <h6 class="mb-2">Parti Performans Skoru</h6>
                    <div class="progress" style="height: 25px;">
                        <?php
                        $party_score = floatval($party_info['score'] ?? 0);
                        $score_percentage = min(100, $party_score);
                        $score_class = '';
                        
                        if ($party_score >= 80) {
                            $score_class = 'bg-success';
                        } elseif ($party_score >= 60) {
                            $score_class = 'bg-info';
                        } elseif ($party_score >= 40) {
                            $score_class = 'bg-warning';
                        } else {
                            $score_class = 'bg-danger';
                        }
                        ?>
                        <div class="progress-bar <?php echo $score_class; ?>" role="progressbar" 
                             style="width: <?php echo $score_percentage; ?>%" 
                             aria-valuenow="<?php echo $party_score; ?>" 
                             aria-valuemin="0" aria-valuemax="100">
                            <?php echo number_format($party_score, 1); ?> / 100
                        </div>
                    </div>
                </div>
                
                <div class="row">
                    <div class="col-md-4 mb-3">
                        <div class="card bg-light">
                            <div class="card-body text-center">
                                <h6 class="card-title">Toplam Şikayet</h6>
                                <p class="h3 mb-0"><?php echo number_format($party_info['parti_sikayet_sayisi'] ?? 0); ?></p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4 mb-3">
                        <div class="card bg-light">
                            <div class="card-body text-center">
                                <h6 class="card-title">Çözülen Şikayet</h6>
                                <p class="h3 mb-0"><?php echo number_format($party_info['parti_cozulmus_sikayet_sayisi'] ?? 0); ?></p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4 mb-3">
                        <div class="card bg-light">
                            <div class="card-body text-center">
                                <h6 class="card-title">Teşekkür Sayısı</h6>
                                <p class="h3 mb-0"><?php echo number_format($party_info['parti_tesekkur_sayisi'] ?? 0); ?></p>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="mt-3">
                    <h6 class="mb-2">Son Güncelleme:</h6>
                    <p class="mb-0 text-muted">
                        <?php echo isset($party_info['last_updated']) ? formatDate($party_info['last_updated']) : 'Belirtilmemiş'; ?>
                    </p>
                </div>
            </div>
        </div>
    </div>
    <?php endif; ?>
    
    <!-- Karşılaştırmalı Analiz -->
    <div class="col-md-<?php echo $party_info ? '6' : '12'; ?> mb-4">
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-balance-scale me-2"></i> Karşılaştırmalı İlçe Analizi</h5>
            </div>
            <div class="card-body">
                <?php if(empty($similar_districts)): ?>
                    <p class="text-muted">Karşılaştırma için benzer ilçe bulunamadı.</p>
                <?php else: ?>
                    <div style="height: 300px;">
                        <canvas id="districtComparisonChart"></canvas>
                    </div>
                    
                    <div class="table-responsive mt-4">
                        <table class="table table-sm table-striped">
                            <thead>
                                <tr>
                                    <th>İlçe</th>
                                    <th>Çözüm Oranı</th>
                                    <th>Toplam Şikayet</th>
                                    <th>Çözülen Şikayet</th>
                                    <th>Teşekkür</th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr class="table-primary">
                                    <td><strong><?php echo escape($district['name']); ?></strong></td>
                                    <td><strong><?php echo number_format($district_solution_rate, 1); ?>%</strong></td>
                                    <td><?php echo $total_complaints; ?></td>
                                    <td><?php echo $solved_complaints; ?></td>
                                    <td><?php echo $thanks_count; ?></td>
                                </tr>
                                <?php foreach($similar_districts as $d): ?>
                                    <tr>
                                        <td><?php echo escape($d['name']); ?></td>
                                        <td><?php echo number_format(floatval($d['solution_rate'] ?? 0), 1); ?>%</td>
                                        <td><?php echo intval($d['total_complaints'] ?? 0); ?></td>
                                        <td><?php echo intval($d['solved_complaints'] ?? 0); ?></td>
                                        <td><?php echo intval($d['thanks_count'] ?? 0); ?></td>
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

<!-- Performans Durumu Güncelleştir -->
<?php if (isAdmin()): ?>
<div class="card mb-4">
    <div class="card-header">
        <h5 class="mb-0"><i class="fas fa-sync me-2"></i> Performans Verilerini Güncelle</h5>
    </div>
    <div class="card-body">
        <form action="index.php?page=update_district_performance" method="post" class="row g-3">
            <input type="hidden" name="district_id" value="<?php echo $district_id; ?>">
            
            <div class="col-md-3">
                <label for="total_complaints" class="form-label">Toplam Şikayet</label>
                <input type="number" class="form-control" id="total_complaints" name="total_complaints" value="<?php echo $total_complaints; ?>" min="0">
            </div>
            
            <div class="col-md-3">
                <label for="solved_complaints" class="form-label">Çözülen Şikayet</label>
                <input type="number" class="form-control" id="solved_complaints" name="solved_complaints" value="<?php echo $solved_complaints; ?>" min="0">
            </div>
            
            <div class="col-md-3">
                <label for="thanks_count" class="form-label">Teşekkür Sayısı</label>
                <input type="number" class="form-control" id="thanks_count" name="thanks_count" value="<?php echo $thanks_count; ?>" min="0">
            </div>
            
            <div class="col-md-3">
                <label for="solution_rate" class="form-label">Çözüm Oranı (%)</label>
                <input type="number" class="form-control" id="solution_rate" name="solution_rate" value="<?php echo $district_solution_rate; ?>" min="0" max="100" step="0.1">
            </div>
            
            <div class="col-12">
                <button type="submit" class="btn btn-primary">
                    <i class="fas fa-save me-1"></i> Değerleri Kaydet
                </button>
                <button type="button" class="btn btn-success ms-2" id="calculateButton">
                    <i class="fas fa-calculator me-1"></i> Otomatik Hesapla
                </button>
                <button type="button" class="btn btn-info ms-2" id="refreshDataButton">
                    <i class="fas fa-sync-alt me-1"></i> Verileri Yenile
                </button>
            </div>
        </form>
    </div>
</div>
<?php endif; ?>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // Çözüm Oranı Grafiği
    var solutionCtx = document.getElementById('solutionRateChart').getContext('2d');
    var solutionRateChart = new Chart(solutionCtx, {
        type: 'doughnut',
        data: {
            datasets: [{
                data: [
                    <?php echo $district_solution_rate; ?>,
                    <?php echo 100 - $district_solution_rate; ?>
                ],
                backgroundColor: [
                    '<?php echo $district_solution_rate >= 70 ? "rgba(40, 167, 69, 0.8)" : ($district_solution_rate >= 40 ? "rgba(255, 193, 7, 0.8)" : "rgba(220, 53, 69, 0.8)"); ?>',
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
    
    // Aylık Trend Grafiği
    var trendCtx = document.getElementById('monthlyTrendChart').getContext('2d');
    var monthlyTrendChart = new Chart(trendCtx, {
        type: 'line',
        data: {
            labels: [
                <?php 
                $month_labels = array_map(function($month) {
                    return "'" . substr($month['month'], 0, 3) . "'";
                }, $last_six_months);
                echo implode(', ', $month_labels);
                ?>
            ],
            datasets: [
                {
                    label: 'Şikayetler',
                    data: [
                        <?php 
                        $complaint_data = array_map(function($month) {
                            return $month['complaints'];
                        }, $last_six_months);
                        echo implode(', ', $complaint_data);
                        ?>
                    ],
                    borderColor: 'rgba(220, 53, 69, 1)',
                    backgroundColor: 'rgba(220, 53, 69, 0.1)',
                    tension: 0.3,
                    fill: true
                },
                {
                    label: 'Çözülen',
                    data: [
                        <?php 
                        $solved_data = array_map(function($month) {
                            return $month['solved'];
                        }, $last_six_months);
                        echo implode(', ', $solved_data);
                        ?>
                    ],
                    borderColor: 'rgba(40, 167, 69, 1)',
                    backgroundColor: 'rgba(40, 167, 69, 0.1)',
                    tension: 0.3,
                    fill: true
                },
                {
                    label: 'Teşekkür',
                    data: [
                        <?php 
                        $thanks_data = array_map(function($month) {
                            return $month['thanks'];
                        }, $last_six_months);
                        echo implode(', ', $thanks_data);
                        ?>
                    ],
                    borderColor: 'rgba(13, 110, 253, 1)',
                    backgroundColor: 'rgba(13, 110, 253, 0.1)',
                    tension: 0.3,
                    fill: true
                }
            ]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'top',
                }
            },
            scales: {
                y: {
                    beginAtZero: true
                }
            }
        }
    });
    
    <?php if(!empty($similar_districts)): ?>
    // Karşılaştırmalı İlçe Grafiği
    var comparisonCtx = document.getElementById('districtComparisonChart').getContext('2d');
    var districtComparisonChart = new Chart(comparisonCtx, {
        type: 'bar',
        data: {
            labels: [
                '<?php echo escape($district['name']); ?>',
                <?php 
                $district_labels = array_map(function($d) {
                    return "'" . escape($d['name']) . "'";
                }, array_slice($similar_districts, 0, 5)); // Sadece ilk 5 ilçeyi al
                echo implode(', ', $district_labels);
                ?>
            ],
            datasets: [
                {
                    label: 'Çözüm Oranı (%)',
                    data: [
                        <?php echo $district_solution_rate; ?>,
                        <?php 
                        $solution_rates = array_map(function($d) {
                            return floatval($d['solution_rate'] ?? 0);
                        }, array_slice($similar_districts, 0, 5));
                        echo implode(', ', $solution_rates);
                        ?>
                    ],
                    backgroundColor: 'rgba(13, 110, 253, 0.7)',
                }
            ]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'top',
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100
                }
            }
        }
    });
    <?php endif; ?>
    
    <?php if (isAdmin()): ?>
    // Otomatik Hesaplama Butonu
    document.getElementById('calculateButton').addEventListener('click', function() {
        const totalComplaints = parseInt(document.getElementById('total_complaints').value) || 0;
        const solvedComplaints = parseInt(document.getElementById('solved_complaints').value) || 0;
        const thanksCount = parseInt(document.getElementById('thanks_count').value) || 0;
        
        let solutionRate = 0;
        if (totalComplaints + thanksCount > 0) {
            solutionRate = ((solvedComplaints + thanksCount) / (totalComplaints + thanksCount)) * 100;
            solutionRate = Math.round(solutionRate * 10) / 10; // 1 ondalık basamağa yuvarla
        }
        
        document.getElementById('solution_rate').value = solutionRate;
    });
    
    // Verileri Yenile Butonu
    document.getElementById('refreshDataButton').addEventListener('click', function() {
        if (confirm('İlçe performans verilerini veritabanından yenilemek istediğinize emin misiniz?')) {
            window.location.href = 'index.php?page=district_performance&id=<?php echo $district_id; ?>&refresh=1';
        }
    });
    <?php endif; ?>
});
</script>