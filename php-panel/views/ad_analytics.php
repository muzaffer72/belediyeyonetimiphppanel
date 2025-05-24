<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// ID kontrolü
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz reklam ID\'si';
    $_SESSION['message_type'] = 'danger';
    safeRedirect('index.php?page=advertisements');
}

// Reklam bilgilerini al
$ad_id = $_GET['id'];
$ad_result = getDataById('sponsored_ads', $ad_id);

// Dönen sonucu kontrol et
if (!$ad_result || $ad_result['error'] || !isset($ad_result['data'])) {
    $_SESSION['message'] = 'Reklam bulunamadı: ' . ($ad_result['message'] ?? 'Bilinmeyen hata');
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=advertisements');
    exit;
}

// Reklam verisini al
$ad = $ad_result['data'];

// Reklamın etkileşimlerini al
$interactions_result = getData('ad_interactions', [
    'ad_id' => 'eq.' . $ad_id,
    'order' => 'created_at.desc'
]);
$interactions = $interactions_result['data'];

// Etkileşim tipine göre gruplandır
$impressions = array_filter($interactions, function($interaction) {
    return $interaction['interaction_type'] === 'impression';
});

$clicks = array_filter($interactions, function($interaction) {
    return $interaction['interaction_type'] === 'click';
});

// Günlük etkileşimleri hesapla
$daily_stats = [];
$date_range = 14; // Son 14 günün istatistiklerini göster

for ($i = $date_range - 1; $i >= 0; $i--) {
    $date = date('Y-m-d', strtotime("-$i days"));
    $daily_stats[$date] = [
        'date' => $date,
        'impressions' => 0,
        'clicks' => 0,
        'ctr' => 0
    ];
}

// Etkileşimleri günlere göre topla
foreach ($interactions as $interaction) {
    $interaction_date = date('Y-m-d', strtotime($interaction['created_at']));
    
    // Son 14 gün içinde mi?
    if (isset($daily_stats[$interaction_date])) {
        if ($interaction['interaction_type'] === 'impression') {
            $daily_stats[$interaction_date]['impressions']++;
        } elseif ($interaction['interaction_type'] === 'click') {
            $daily_stats[$interaction_date]['clicks']++;
        }
    }
}

// CTR hesapla
foreach ($daily_stats as &$day) {
    if ($day['impressions'] > 0) {
        $day['ctr'] = ($day['clicks'] / $day['impressions']) * 100;
    }
}
unset($day);

// Toplam özet istatistikler
$total_impressions = count($impressions);
$total_clicks = count($clicks);
$total_ctr = $total_impressions > 0 ? ($total_clicks / $total_impressions) * 100 : 0;

// Kullanıcı bazlı analiz
$user_interactions = [];
foreach ($interactions as $interaction) {
    $user_id = $interaction['user_id'] ?? 'anonymous';
    
    if (!isset($user_interactions[$user_id])) {
        $user_interactions[$user_id] = [
            'user_id' => $user_id,
            'impressions' => 0,
            'clicks' => 0,
            'ctr' => 0
        ];
    }
    
    if ($interaction['interaction_type'] === 'impression') {
        $user_interactions[$user_id]['impressions']++;
    } elseif ($interaction['interaction_type'] === 'click') {
        $user_interactions[$user_id]['clicks']++;
    }
}

// Kullanıcı CTR hesapla ve sırala
foreach ($user_interactions as &$user) {
    if ($user['impressions'] > 0) {
        $user['ctr'] = ($user['clicks'] / $user['impressions']) * 100;
    }
}
unset($user);

// CTR'ye göre azalan sırada sırala
usort($user_interactions, function($a, $b) {
    return $b['ctr'] <=> $a['ctr'];
});

// İlk 10 kullanıcıyı al
$top_users = array_slice($user_interactions, 0, 10);

// Kullanıcı detaylarını getir
foreach ($top_users as &$user) {
    if ($user['user_id'] !== 'anonymous') {
        $user_data = getDataById('users', $user['user_id']);
        if ($user_data) {
            $user['username'] = $user_data['username'] ?? 'N/A';
            $user['name'] = $user_data['name'] ?? 'N/A';
        } else {
            $user['username'] = 'Silinmiş Kullanıcı';
            $user['name'] = 'Silinmiş Kullanıcı';
        }
    } else {
        $user['username'] = 'Anonim';
        $user['name'] = 'Anonim';
    }
}
unset($user);

?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">Reklam Analitikleri: <?php echo escape($ad['title']); ?></h1>
    
    <div>
        <a href="index.php?page=ad_detail&id=<?php echo $ad_id; ?>" class="btn btn-info me-2">
            <i class="fas fa-eye me-1"></i> Reklam Detayları
        </a>
        <a href="index.php?page=advertisements" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Reklamlara Dön
        </a>
    </div>
</div>

<!-- Reklam Özeti -->
<div class="card mb-4">
    <div class="card-header">
        <h5 class="mb-0">Reklam Özeti</h5>
    </div>
    <div class="card-body">
        <div class="row">
            <div class="col-md-6">
                <table class="table">
                    <tr>
                        <th style="width: 150px;">Başlık:</th>
                        <td><?php echo escape($ad['title'] ?? 'Başlık Belirtilmemiş'); ?></td>
                    </tr>
                    <tr>
                        <th>Kampanya Süresi:</th>
                        <td>
                            <?php
                            // Tarih alanları boş olabilir, o yüzden kontrol edelim
                            $start_date_str = isset($ad['start_date']) && !empty($ad['start_date']) ? $ad['start_date'] : null;
                            $end_date_str = isset($ad['end_date']) && !empty($ad['end_date']) ? $ad['end_date'] : null;
                            
                            if ($start_date_str) {
                                $start_date = date('d.m.Y', strtotime($start_date_str));
                            } else {
                                $start_date = 'Belirtilmemiş';
                            }
                            
                            if ($end_date_str) {
                                $end_date = date('d.m.Y', strtotime($end_date_str));
                            } else {
                                $end_date = 'Belirtilmemiş';
                            }
                            
                            echo $start_date . ' - ' . $end_date;
                            
                            // Kalan süreyi göster
                            $now = time();
                            
                            if ($end_date_str) {
                                $end = strtotime($end_date_str);
                                
                                if ($end > $now) {
                                    $diff = $end - $now;
                                    $days = floor($diff / (60 * 60 * 24));
                                    echo ' <span class="badge bg-info">' . $days . ' gün kaldı</span>';
                                } else {
                                    echo ' <span class="badge bg-secondary">Süresi Dolmuş</span>';
                                }
                            } else {
                                echo ' <span class="badge bg-warning">Tanımlanmamış</span>';
                            }
                            ?>
                        </td>
                    </tr>
                    <tr>
                        <th>Durum:</th>
                        <td>
                            <?php
                            $status = isset($ad['status']) ? $ad['status'] : '';
                            
                            if ($status === 'active'): ?>
                                <span class="badge bg-success">Aktif</span>
                            <?php elseif ($status === 'paused'): ?>
                                <span class="badge bg-warning text-dark">Duraklatıldı</span>
                            <?php else: ?>
                                <span class="badge bg-secondary">Pasif</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <tr>
                        <th>Kapsam:</th>
                        <td>
                            <?php
                            $ad_display_scope = isset($ad['ad_display_scope']) ? $ad['ad_display_scope'] : '';
                            
                            switch ($ad_display_scope) {
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
                                default:
                                    echo '<span class="badge bg-success">Tüm Kullanıcılar</span>';
                            }
                            ?>
                        </td>
                    </tr>
                </table>
            </div>
            <div class="col-md-6">
                <?php if (!empty($ad['image_urls']) && is_array($ad['image_urls']) && !empty($ad['image_urls'][0])): ?>
                    <div class="text-center">
                        <img src="<?php echo escape($ad['image_urls'][0]); ?>" alt="Reklam Görseli" style="max-height: 150px; max-width: 100%;" class="img-thumbnail">
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- Performans Metrikleri -->
<div class="row mb-4">
    <div class="col-md-4">
        <div class="card bg-primary text-white h-100">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0">Toplam Gösterim</h6>
                        <h2 class="mb-0"><?php echo number_format($total_impressions); ?></h2>
                    </div>
                    <div>
                        <i class="fas fa-eye fa-3x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <div class="card bg-success text-white h-100">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0">Toplam Tıklama</h6>
                        <h2 class="mb-0"><?php echo number_format($total_clicks); ?></h2>
                    </div>
                    <div>
                        <i class="fas fa-mouse-pointer fa-3x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <div class="card bg-info text-white h-100">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0">Tıklama Oranı (CTR)</h6>
                        <h2 class="mb-0"><?php echo number_format($total_ctr, 2); ?>%</h2>
                    </div>
                    <div>
                        <i class="fas fa-percentage fa-3x"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Grafik ve Tablo -->
<div class="row">
    <!-- Günlük Performans Grafiği -->
    <div class="col-md-8 mb-4">
        <div class="card h-100">
            <div class="card-header">
                <h5 class="mb-0">Son 14 Gün Performansı</h5>
            </div>
            <div class="card-body">
                <canvas id="performanceChart" height="300"></canvas>
            </div>
        </div>
    </div>
    
    <!-- Genel İstatistikler -->
    <div class="col-md-4 mb-4">
        <div class="card h-100">
            <div class="card-header">
                <h5 class="mb-0">Genel İstatistikler</h5>
            </div>
            <div class="card-body">
                <div class="mb-4">
                    <h6>Ortalama Günlük Gösterim</h6>
                    <?php
                    $avg_impressions = 0;
                    $active_days = 0;
                    
                    foreach ($daily_stats as $day) {
                        if ($day['impressions'] > 0) {
                            $avg_impressions += $day['impressions'];
                            $active_days++;
                        }
                    }
                    
                    $avg_impressions = $active_days > 0 ? $avg_impressions / $active_days : 0;
                    ?>
                    <h3><?php echo number_format($avg_impressions, 1); ?></h3>
                </div>
                
                <div class="mb-4">
                    <h6>Ortalama Günlük Tıklama</h6>
                    <?php
                    $avg_clicks = 0;
                    $active_days = 0;
                    
                    foreach ($daily_stats as $day) {
                        if ($day['impressions'] > 0) {
                            $avg_clicks += $day['clicks'];
                            $active_days++;
                        }
                    }
                    
                    $avg_clicks = $active_days > 0 ? $avg_clicks / $active_days : 0;
                    ?>
                    <h3><?php echo number_format($avg_clicks, 1); ?></h3>
                </div>
                
                <div>
                    <h6>En Yüksek Günlük Performans</h6>
                    <?php
                    $best_day = null;
                    $best_day_ctr = 0;
                    
                    foreach ($daily_stats as $date => $day) {
                        if ($day['impressions'] >= 5 && $day['ctr'] > $best_day_ctr) {
                            $best_day = $date;
                            $best_day_ctr = $day['ctr'];
                        }
                    }
                    
                    if ($best_day): 
                        $best_day_formatted = date('d.m.Y', strtotime($best_day));
                    ?>
                        <div class="d-flex justify-content-between">
                            <span><?php echo $best_day_formatted; ?></span>
                            <span class="badge bg-success">CTR: <?php echo number_format($best_day_ctr, 2); ?>%</span>
                        </div>
                        <div class="mt-2">
                            <small>
                                <i class="fas fa-eye me-1"></i> <?php echo number_format($daily_stats[$best_day]['impressions']); ?> gösterim
                            </small>
                            <br>
                            <small>
                                <i class="fas fa-mouse-pointer me-1"></i> <?php echo number_format($daily_stats[$best_day]['clicks']); ?> tıklama
                            </small>
                        </div>
                    <?php else: ?>
                        <p class="text-muted">Yeterli veri yok</p>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Kullanıcı Bazlı Analiz -->
<div class="card mb-4">
    <div class="card-header">
        <h5 class="mb-0">En Etkileşimli Kullanıcılar</h5>
    </div>
    <div class="card-body">
        <?php if (empty($top_users)): ?>
            <p class="text-center text-muted">Henüz kullanıcı etkileşimi bulunmuyor.</p>
        <?php else: ?>
            <div class="table-responsive">
                <table class="table table-striped">
                    <thead>
                        <tr>
                            <th>Kullanıcı Adı</th>
                            <th>E-posta</th>
                            <th>Gösterimler</th>
                            <th>Tıklamalar</th>
                            <th>CTR</th>
                            <th>Son Etkileşim</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($top_users as $user): 
                            // Bu kullanıcının son etkileşimini bul
                            $last_interaction = null;
                            foreach ($interactions as $interaction) {
                                if (($interaction['user_id'] ?? 'anonymous') === $user['user_id']) {
                                    $last_interaction = $interaction;
                                    break;
                                }
                            }
                            
                            // E-posta bilgisini getir
                            $user_email = 'N/A';
                            if ($user['user_id'] !== 'anonymous') {
                                // Kullanıcı detaylarını getir
                                $user_details = getDataById('users', $user['user_id']);
                                if ($user_details && isset($user_details['data']) && isset($user_details['data']['email'])) {
                                    $user_email = $user_details['data']['email'];
                                }
                            }
                        ?>
                            <tr>
                                <td>
                                    <?php if ($user['user_id'] === 'anonymous'): ?>
                                        <span class="text-muted">Anonim Kullanıcılar</span>
                                    <?php else: ?>
                                        <strong><?php echo escape($user['username']); ?></strong>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <?php if ($user['user_id'] === 'anonymous'): ?>
                                        <span class="text-muted">-</span>
                                    <?php else: ?>
                                        <a href="mailto:<?php echo escape($user_email); ?>"><?php echo escape($user_email); ?></a>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo number_format($user['impressions']); ?></td>
                                <td><?php echo number_format($user['clicks']); ?></td>
                                <td>
                                    <div class="progress" style="height: 10px;">
                                        <div class="progress-bar bg-success" role="progressbar" 
                                             style="width: <?php echo min(100, $user['ctr']); ?>%" 
                                             aria-valuenow="<?php echo $user['ctr']; ?>" 
                                             aria-valuemin="0" aria-valuemax="100">
                                        </div>
                                    </div>
                                    <small><?php echo number_format($user['ctr'], 2); ?>%</small>
                                </td>
                                <td>
                                    <?php 
                                    if ($last_interaction) {
                                        echo date('d.m.Y H:i', strtotime($last_interaction['created_at']));
                                        
                                        if ($last_interaction['interaction_type'] === 'impression') {
                                            echo ' <span class="badge bg-primary">Gösterim</span>';
                                        } elseif ($last_interaction['interaction_type'] === 'click') {
                                            echo ' <span class="badge bg-success">Tıklama</span>';
                                        }
                                    } else {
                                        echo '-';
                                    }
                                    ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
    </div>
</div>

<!-- İşlemler -->
<div class="d-flex justify-content-between">
    <a href="index.php?page=advertisements" class="btn btn-secondary">
        <i class="fas fa-arrow-left me-1"></i> Reklamlara Dön
    </a>
    <div>
        <a href="index.php?page=ad_edit&id=<?php echo $ad_id; ?>" class="btn btn-warning me-2">
            <i class="fas fa-edit me-1"></i> Reklamı Düzenle
        </a>
        <a href="index.php?page=ad_analytics&id=<?php echo $ad_id; ?>&export=csv" class="btn btn-primary">
            <i class="fas fa-download me-1"></i> Raporu İndir
        </a>
    </div>
</div>

<script>
    document.addEventListener('DOMContentLoaded', function() {
        // Performans Grafiği
        var performanceCtx = document.getElementById('performanceChart').getContext('2d');
        var performanceChart = new Chart(performanceCtx, {
            type: 'line',
            data: {
                labels: [
                    <?php 
                    $date_labels = [];
                    foreach ($daily_stats as $date => $stats) {
                        $date_labels[] = "'" . date('d.m', strtotime($date)) . "'";
                    }
                    echo implode(', ', $date_labels);
                    ?>
                ],
                datasets: [
                    {
                        label: 'Gösterimler',
                        data: [
                            <?php 
                            $impressions_data = [];
                            foreach ($daily_stats as $stats) {
                                $impressions_data[] = $stats['impressions'];
                            }
                            echo implode(', ', $impressions_data);
                            ?>
                        ],
                        borderColor: 'rgba(13, 110, 253, 1)',
                        backgroundColor: 'rgba(13, 110, 253, 0.1)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4
                    },
                    {
                        label: 'Tıklamalar',
                        data: [
                            <?php 
                            $clicks_data = [];
                            foreach ($daily_stats as $stats) {
                                $clicks_data[] = $stats['clicks'];
                            }
                            echo implode(', ', $clicks_data);
                            ?>
                        ],
                        borderColor: 'rgba(40, 167, 69, 1)',
                        backgroundColor: 'rgba(40, 167, 69, 0.1)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4
                    },
                    {
                        label: 'CTR (%)',
                        data: [
                            <?php 
                            $ctr_data = [];
                            foreach ($daily_stats as $stats) {
                                $ctr_data[] = number_format($stats['ctr'], 2);
                            }
                            echo implode(', ', $ctr_data);
                            ?>
                        ],
                        borderColor: 'rgba(220, 53, 69, 1)',
                        backgroundColor: 'rgba(220, 53, 69, 0.1)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                interaction: {
                    mode: 'index',
                    intersect: false,
                },
                plugins: {
                    title: {
                        display: true,
                        text: 'Reklam Performansı'
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                let label = context.dataset.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.dataset.label === 'CTR (%)') {
                                    label += context.parsed.y + '%';
                                } else {
                                    label += context.parsed.y;
                                }
                                return label;
                            }
                        }
                    }
                },
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: {
                            display: true,
                            text: 'Gösterim ve Tıklama Sayısı'
                        }
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        title: {
                            display: true,
                            text: 'CTR (%)'
                        },
                        min: 0,
                        max: 100,
                        grid: {
                            drawOnChartArea: false
                        }
                    }
                }
            }
        });
    });
</script>