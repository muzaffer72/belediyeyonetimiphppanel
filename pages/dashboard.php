<?php
// Get dashboard statistics
$stats = getDashboardStats();
?>

<div class="row mb-4">
    <!-- Total Posts -->
    <div class="col-md-3 mb-4">
        <div class="card border-left-primary shadow h-100 py-2">
            <div class="card-body">
                <div class="row no-gutters align-items-center">
                    <div class="col mr-2">
                        <div class="text-xs font-weight-bold text-primary text-uppercase mb-1">
                            Toplam Gönderi</div>
                        <div class="h5 mb-0 font-weight-bold text-gray-800"><?php echo number_format($stats['total_posts']); ?></div>
                    </div>
                    <div class="col-auto">
                        <i class="fas fa-clipboard-list fa-2x text-gray-300"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Total Complaints -->
    <div class="col-md-3 mb-4">
        <div class="card border-left-danger shadow h-100 py-2">
            <div class="card-body">
                <div class="row no-gutters align-items-center">
                    <div class="col mr-2">
                        <div class="text-xs font-weight-bold text-danger text-uppercase mb-1">
                            Toplam Şikayet</div>
                        <div class="h5 mb-0 font-weight-bold text-gray-800"><?php echo number_format($stats['total_complaints']); ?></div>
                    </div>
                    <div class="col-auto">
                        <i class="fas fa-exclamation-circle fa-2x text-gray-300"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Resolved Complaints -->
    <div class="col-md-3 mb-4">
        <div class="card border-left-success shadow h-100 py-2">
            <div class="card-body">
                <div class="row no-gutters align-items-center">
                    <div class="col mr-2">
                        <div class="text-xs font-weight-bold text-success text-uppercase mb-1">
                            Çözülen Şikayetler</div>
                        <div class="h5 mb-0 font-weight-bold text-gray-800"><?php echo number_format($stats['resolved_complaints']); ?></div>
                    </div>
                    <div class="col-auto">
                        <i class="fas fa-check-circle fa-2x text-gray-300"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Thanks Posts -->
    <div class="col-md-3 mb-4">
        <div class="card border-left-info shadow h-100 py-2">
            <div class="card-body">
                <div class="row no-gutters align-items-center">
                    <div class="col mr-2">
                        <div class="text-xs font-weight-bold text-info text-uppercase mb-1">
                            Teşekkür Gönderileri</div>
                        <div class="h5 mb-0 font-weight-bold text-gray-800"><?php echo number_format($stats['thanks_posts']); ?></div>
                    </div>
                    <div class="col-auto">
                        <i class="fas fa-thumbs-up fa-2x text-gray-300"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="row mb-4">
    <!-- Resolution Rate -->
    <div class="col-md-6 mb-4">
        <div class="card shadow mb-4">
            <div class="card-header py-3 d-flex flex-row align-items-center justify-content-between">
                <h6 class="m-0 font-weight-bold text-primary">Şikayet Çözüm Oranı</h6>
            </div>
            <div class="card-body">
                <div class="chart-pie pt-4 pb-2">
                    <canvas id="resolutionRateChart"></canvas>
                </div>
                <div class="mt-4 text-center small">
                    <span class="mr-2">
                        <i class="fas fa-circle text-success"></i> Çözülen Şikayetler (<?php echo $stats['resolved_complaints']; ?>)
                    </span>
                    <span class="mr-2">
                        <i class="fas fa-circle text-danger"></i> Bekleyen Şikayetler (<?php echo $stats['total_complaints'] - $stats['resolved_complaints']; ?>)
                    </span>
                </div>
            </div>
        </div>
    </div>

    <!-- Recent Activity -->
    <div class="col-md-6 mb-4">
        <div class="card shadow mb-4">
            <div class="card-header py-3">
                <h6 class="m-0 font-weight-bold text-primary">Son Aktiviteler</h6>
            </div>
            <div class="card-body">
                <h4 class="small font-weight-bold">Yeni Kullanıcılar <span class="float-right">+<?php echo intval($stats['total_users'] * 0.05); ?></span></h4>
                <div class="progress mb-4">
                    <div class="progress-bar bg-info" role="progressbar" style="width: 20%" aria-valuenow="20" aria-valuemin="0" aria-valuemax="100"></div>
                </div>
                <h4 class="small font-weight-bold">Yeni Gönderiler <span class="float-right"><?php echo $stats['recent_posts']; ?></span></h4>
                <div class="progress mb-4">
                    <div class="progress-bar bg-primary" role="progressbar" style="width: 40%" aria-valuenow="40" aria-valuemin="0" aria-valuemax="100"></div>
                </div>
                <h4 class="small font-weight-bold">Çözülen Şikayetler <span class="float-right"><?php echo number_format($stats['resolution_rate'], 1); ?>%</span></h4>
                <div class="progress mb-4">
                    <div class="progress-bar bg-success" role="progressbar" style="width: <?php echo min($stats['resolution_rate'], 100); ?>%" aria-valuenow="<?php echo min($stats['resolution_rate'], 100); ?>" aria-valuemin="0" aria-valuemax="100"></div>
                </div>
                <h4 class="small font-weight-bold">Teşekkür Oranı <span class="float-right"><?php echo number_format(($stats['thanks_posts'] * 100) / max(1, $stats['total_posts']), 1); ?>%</span></h4>
                <div class="progress">
                    <div class="progress-bar bg-warning" role="progressbar" style="width: <?php echo min(($stats['thanks_posts'] * 100) / max(1, $stats['total_posts']), 100); ?>%" aria-valuenow="<?php echo min(($stats['thanks_posts'] * 100) / max(1, $stats['total_posts']), 100); ?>" aria-valuemin="0" aria-valuemax="100"></div>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <!-- Best Performing Districts -->
    <div class="col-md-6 mb-4">
        <div class="card shadow mb-4">
            <div class="card-header py-3">
                <h6 class="m-0 font-weight-bold text-primary">En İyi Performans Gösteren İlçeler</h6>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-bordered" width="100%" cellspacing="0">
                        <thead>
                            <tr>
                                <th>İlçe</th>
                                <th>Şehir</th>
                                <th>Çözüm Oranı</th>
                                <th>Parti</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($stats['best_districts'] as $district): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($district['name']); ?></td>
                                <td><?php echo htmlspecialchars($district['city_name']); ?></td>
                                <td>
                                    <div class="progress" style="height: 20px;">
                                        <div class="progress-bar bg-success" role="progressbar" style="width: <?php echo min(floatval($district['solution_rate']), 100); ?>%" aria-valuenow="<?php echo min(floatval($district['solution_rate']), 100); ?>" aria-valuemin="0" aria-valuemax="100">
                                            <?php echo number_format(floatval($district['solution_rate']), 1); ?>%
                                        </div>
                                    </div>
                                </td>
                                <td><?php echo htmlspecialchars($district['party_name'] ?? 'Belirtilmemiş'); ?></td>
                            </tr>
                            <?php endforeach; ?>
                            
                            <?php if (empty($stats['best_districts'])): ?>
                            <tr>
                                <td colspan="4" class="text-center">Henüz veri bulunmamaktadır.</td>
                            </tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <!-- Political Party Scores -->
    <div class="col-md-6 mb-4">
        <div class="card shadow mb-4">
            <div class="card-header py-3">
                <h6 class="m-0 font-weight-bold text-primary">Parti Performans Skorları</h6>
            </div>
            <div class="card-body">
                <div class="chart-bar">
                    <canvas id="partyScoresChart"></canvas>
                </div>
                <hr>
                <small class="text-muted">Son güncelleme: <?php echo !empty($stats['party_scores']) ? formatDate($stats['party_scores'][0]['last_updated'] ?? date('Y-m-d H:i:s'), true) : 'Belirtilmemiş'; ?></small>
            </div>
        </div>
    </div>
</div>

<script>
// Resolution Rate Chart
var resolutionCtx = document.getElementById("resolutionRateChart");
var resolutionChart = new Chart(resolutionCtx, {
    type: 'doughnut',
    data: {
        labels: ["Çözülen Şikayetler", "Bekleyen Şikayetler"],
        datasets: [{
            data: [
                <?php echo $stats['resolved_complaints']; ?>, 
                <?php echo max(0, $stats['total_complaints'] - $stats['resolved_complaints']); ?>
            ],
            backgroundColor: ['#4e73df', '#e74a3b'],
            hoverBackgroundColor: ['#2e59d9', '#be2617'],
            hoverBorderColor: "rgba(234, 236, 244, 1)",
        }],
    },
    options: {
        maintainAspectRatio: false,
        tooltips: {
            backgroundColor: "rgb(255,255,255)",
            bodyFontColor: "#858796",
            borderColor: '#dddfeb',
            borderWidth: 1,
            xPadding: 15,
            yPadding: 15,
            displayColors: false,
            caretPadding: 10,
        },
        legend: {
            display: false
        },
        cutoutPercentage: 80,
    },
});

// Party Scores Chart
var partyCtx = document.getElementById("partyScoresChart");
var partyScoresChart = new Chart(partyCtx, {
    type: 'horizontalBar',
    data: {
        labels: [
            <?php 
            $partyNames = array_map(function($party) {
                return "'" . htmlspecialchars($party['name']) . "'";
            }, $stats['party_scores']);
            echo implode(', ', $partyNames);
            ?>
        ],
        datasets: [{
            label: "Skor",
            backgroundColor: "#4e73df",
            hoverBackgroundColor: "#2e59d9",
            borderColor: "#4e73df",
            data: [
                <?php 
                $partyScores = array_map(function($party) {
                    return floatval($party['score']);
                }, $stats['party_scores']);
                echo implode(', ', $partyScores);
                ?>
            ],
        }],
    },
    options: {
        maintainAspectRatio: false,
        layout: {
            padding: {
                left: 10,
                right: 25,
                top: 25,
                bottom: 0
            }
        },
        scales: {
            xAxes: [{
                ticks: {
                    min: 0,
                    max: 100,
                    maxTicksLimit: 5,
                    padding: 10,
                },
                gridLines: {
                    color: "rgb(234, 236, 244)",
                    zeroLineColor: "rgb(234, 236, 244)",
                    drawBorder: false,
                    borderDash: [2],
                    zeroLineBorderDash: [2]
                }
            }],
            yAxes: [{
                gridLines: {
                    display: false,
                    drawBorder: false
                },
                ticks: {
                    padding: 20
                }
            }],
        },
        legend: {
            display: false
        },
        tooltips: {
            backgroundColor: "rgb(255,255,255)",
            bodyFontColor: "#858796",
            titleMarginBottom: 10,
            titleFontColor: '#6e707e',
            titleFontSize: 14,
            borderColor: '#dddfeb',
            borderWidth: 1,
            xPadding: 15,
            yPadding: 15,
            displayColors: false,
            intersect: false,
            mode: 'index',
            caretPadding: 10,
            callbacks: {
                label: function(tooltipItem, chart) {
                    var datasetLabel = chart.datasets[tooltipItem.datasetIndex].label || '';
                    return datasetLabel + ': ' + tooltipItem.xLabel.toFixed(1);
                }
            }
        }
    }
});
</script>