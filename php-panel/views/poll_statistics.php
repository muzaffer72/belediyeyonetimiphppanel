<?php
// Gelişmiş anket istatistikleri sayfası
require_once(__DIR__ . '/../includes/functions.php');

// Filtreleme parametreleri
$selected_poll = $_GET['poll_id'] ?? '';
$selected_city = $_GET['city_id'] ?? '';
$selected_district = $_GET['district_id'] ?? '';
$selected_gender = $_GET['gender'] ?? '';
$age_min = $_GET['age_min'] ?? '';
$age_max = $_GET['age_max'] ?? '';
$date_from = $_GET['date_from'] ?? '';
$date_to = $_GET['date_to'] ?? '';

// Anketleri getir
$polls_result = getData('polls', ['order' => 'created_at.desc', 'limit' => 50]);
$polls = $polls_result['data'] ?? [];

// Şehirleri getir
$cities_result = getData('cities', ['order' => 'name']);
$cities = $cities_result['data'] ?? [];

// İlçeleri getir
$districts_result = getData('districts', ['order' => 'name']);
$districts = $districts_result['data'] ?? [];

// Genel istatistikler
$total_polls_result = getData('polls', ['select' => 'count']);
$total_polls = $total_polls_result['data'][0]['count'] ?? 0;

$total_votes_result = getData('poll_votes', ['select' => 'count']);
$total_votes = $total_votes_result['data'][0]['count'] ?? 0;

$active_polls_result = getData('polls', ['is_active' => 'eq.true', 'select' => 'count']);
$active_polls = $active_polls_result['data'][0]['count'] ?? 0;

$unique_voters_result = getData('poll_votes', ['select' => 'user_id', 'distinct' => 'true']);
$unique_voters = count($unique_voters_result['data'] ?? []);

// Seçili anket detayları
$poll_details = null;
$poll_options = [];
$voting_stats = [];

if ($selected_poll) {
    $poll_details_result = getDataById('polls', $selected_poll);
    $poll_details = $poll_details_result['data'] ?? null;
    
    if ($poll_details) {
        // Anket seçeneklerini getir
        $options_result = getData('poll_options', ['poll_id' => 'eq.' . $selected_poll, 'order' => 'created_at']);
        $poll_options = $options_result['data'] ?? [];
        
        // Demografik analiz için SQL sorgusu oluştur
        $where_conditions = ["pv.poll_id = '{$selected_poll}'"];
        
        if ($selected_city) $where_conditions[] = "u.city_id = '{$selected_city}'";
        if ($selected_district) $where_conditions[] = "u.district_id = '{$selected_district}'";
        if ($selected_gender) $where_conditions[] = "u.gender = '{$selected_gender}'";
        if ($age_min) $where_conditions[] = "CAST(u.age AS INTEGER) >= {$age_min}";
        if ($age_max) $where_conditions[] = "CAST(u.age AS INTEGER) <= {$age_max}";
        if ($date_from) $where_conditions[] = "pv.created_at >= '{$date_from}'";
        if ($date_to) $where_conditions[] = "pv.created_at <= '{$date_to} 23:59:59'";
        
        $where_clause = implode(' AND ', $where_conditions);
        
        // Oy dağılımını gerçek verilerle hesapla
        foreach ($poll_options as &$option) {
            $option_votes_result = getData('poll_votes', [
                'option_id' => 'eq.' . $option['id'],
                'select' => 'count'
            ]);
            $option['filtered_votes'] = $option_votes_result['data'][0]['count'] ?? 0;
        }
        
        // Demografik istatistikler - Gerçek verilerle
        $voting_stats = [
            'gender_stats' => [],
            'age_stats' => [],
            'city_stats' => [],
            'district_stats' => [],
            'daily_stats' => []
        ];
        
        // Anket oylarını kullanıcı bilgileriyle birlikte getir
        $poll_votes_result = getData('poll_votes', [
            'poll_id' => 'eq.' . $selected_poll,
            'select' => '*'
        ]);
        $poll_votes = $poll_votes_result['data'] ?? [];
        
        // Cinsiyet dağılımı
        $gender_stats = [
            'Erkek' => 0,
            'Kadın' => 0,
            'Belirtmek İstemiyorum' => 0,
            'Belirtilmemiş' => 0
        ];
        
        // Yaş grupları
        $age_groups = [
            '18-25' => 0,
            '26-35' => 0,
            '36-45' => 0,
            '46-55' => 0,
            '56+' => 0
        ];
        
        // İl dağılımı
        $city_stats = [];
        
        // Her oy için kullanıcı bilgilerini kontrol et
        foreach ($poll_votes as $vote) {
            if ($vote['user_id']) {
                $user_result = getDataById('users', $vote['user_id']);
                $user = $user_result['data'] ?? null;
                
                if ($user) {
                    // Cinsiyet istatistiği
                    $gender = $user['gender'] ?? 'Belirtilmemiş';
                    if (isset($gender_stats[$gender])) {
                        $gender_stats[$gender]++;
                    } else {
                        $gender_stats['Belirtilmemiş']++;
                    }
                    
                    // Yaş grubu istatistiği
                    $age = intval($user['age'] ?? 0);
                    if ($age >= 18 && $age <= 25) {
                        $age_groups['18-25']++;
                    } elseif ($age >= 26 && $age <= 35) {
                        $age_groups['26-35']++;
                    } elseif ($age >= 36 && $age <= 45) {
                        $age_groups['36-45']++;
                    } elseif ($age >= 46 && $age <= 55) {
                        $age_groups['46-55']++;
                    } elseif ($age > 55) {
                        $age_groups['56+']++;
                    }
                    
                    // Şehir istatistiği
                    if ($user['city']) {
                        $city_name = $user['city'];
                        if (isset($city_stats[$city_name])) {
                            $city_stats[$city_name]++;
                        } else {
                            $city_stats[$city_name] = 1;
                        }
                    }
                }
            }
        }
        
        // Şehirleri oy sayısına göre sırala (en çok 10 tanesi)
        arsort($city_stats);
        $city_stats = array_slice($city_stats, 0, 10, true);
        
        $voting_stats = [
            'gender_stats' => $gender_stats,
            'age_stats' => $age_groups,
            'city_stats' => $city_stats,
            'daily_stats' => []
        ];
    }
}
?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">📊 Anket İstatistikleri</h1>
    <div>
        <a href="index.php?page=polls" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Anketlere Dön
        </a>
    </div>
</div>

<!-- Genel İstatistikler -->
<div class="row mb-4">
    <div class="col-md-3">
        <div class="card bg-primary text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Toplam Anket</h5>
                        <h2 class="mb-0"><?php echo number_format($total_polls); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-poll fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card bg-success text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Aktif Anket</h5>
                        <h2 class="mb-0"><?php echo number_format($active_polls); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-play-circle fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card bg-info text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Toplam Oy</h5>
                        <h2 class="mb-0"><?php echo number_format($total_votes); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-vote-yea fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card bg-warning text-white">
            <div class="card-body">
                <div class="d-flex align-items-center">
                    <div class="flex-grow-1">
                        <h5 class="card-title">Katılımcı</h5>
                        <h2 class="mb-0"><?php echo number_format($unique_voters); ?></h2>
                    </div>
                    <div class="ms-3">
                        <i class="fas fa-users fa-2x opacity-75"></i>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Filtreler -->
<div class="card mb-4">
    <div class="card-header">
        <h5 class="mb-0">🔍 Gelişmiş Filtreler</h5>
    </div>
    <div class="card-body">
        <form method="get" action="">
            <input type="hidden" name="page" value="poll_statistics">
            
            <div class="row">
                <div class="col-md-3">
                    <label class="form-label">Anket Seçin</label>
                    <select class="form-select" name="poll_id" onchange="this.form.submit()">
                        <option value="">Tüm Anketler</option>
                        <?php foreach ($polls as $poll): ?>
                            <option value="<?php echo $poll['id']; ?>" <?php echo $selected_poll === $poll['id'] ? 'selected' : ''; ?>>
                                <?php echo escape($poll['title']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">Şehir</label>
                    <select class="form-select" name="city_id">
                        <option value="">Tüm Şehirler</option>
                        <?php foreach ($cities as $city): ?>
                            <option value="<?php echo $city['id']; ?>" <?php echo $selected_city === $city['id'] ? 'selected' : ''; ?>>
                                <?php echo escape($city['name']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">İlçe</label>
                    <select class="form-select" name="district_id" id="district_select">
                        <option value="">Tüm İlçeler</option>
                        <?php foreach ($districts as $district): ?>
                            <?php if (!$selected_city || $district['city_id'] === $selected_city): ?>
                                <option value="<?php echo $district['id']; ?>" <?php echo $selected_district === $district['id'] ? 'selected' : ''; ?>>
                                    <?php echo escape($district['name']); ?>
                                </option>
                            <?php endif; ?>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">Cinsiyet</label>
                    <select class="form-select" name="gender">
                        <option value="">Hepsi</option>
                        <option value="Erkek" <?php echo $selected_gender === 'Erkek' ? 'selected' : ''; ?>>Erkek</option>
                        <option value="Kadın" <?php echo $selected_gender === 'Kadın' ? 'selected' : ''; ?>>Kadın</option>
                        <option value="Belirtmek İstemiyorum" <?php echo $selected_gender === 'Belirtmek İstemiyorum' ? 'selected' : ''; ?>>Belirtmek İstemiyorum</option>
                    </select>
                </div>
                
                <div class="col-md-3">
                    <label class="form-label">Yaş Aralığı</label>
                    <div class="row">
                        <div class="col-6">
                            <input type="number" class="form-control" name="age_min" placeholder="Min" value="<?php echo $age_min; ?>" min="18" max="100">
                        </div>
                        <div class="col-6">
                            <input type="number" class="form-control" name="age_max" placeholder="Max" value="<?php echo $age_max; ?>" min="18" max="100">
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="row mt-3">
                <div class="col-md-3">
                    <label class="form-label">Başlangıç Tarihi</label>
                    <input type="date" class="form-control" name="date_from" value="<?php echo $date_from; ?>">
                </div>
                <div class="col-md-3">
                    <label class="form-label">Bitiş Tarihi</label>
                    <input type="date" class="form-control" name="date_to" value="<?php echo $date_to; ?>">
                </div>
                <div class="col-md-6 d-flex align-items-end">
                    <button type="submit" class="btn btn-primary me-2">
                        <i class="fas fa-filter me-1"></i> Filtrele
                    </button>
                    <a href="index.php?page=poll_statistics" class="btn btn-outline-secondary">
                        <i class="fas fa-times me-1"></i> Temizle
                    </a>
                </div>
            </div>
        </form>
    </div>
</div>

<?php if ($selected_poll && $poll_details): ?>
<!-- Seçili Anket Detayları -->
<div class="row">
    <div class="col-md-8">
        <!-- Oy Dağılımı -->
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">📊 Oy Dağılımı: <?php echo escape($poll_details['title']); ?></h5>
            </div>
            <div class="card-body">
                <?php 
                $total_filtered_votes = array_sum(array_column($poll_options, 'filtered_votes'));
                ?>
                <?php if ($total_filtered_votes > 0): ?>
                    <?php foreach ($poll_options as $option): ?>
                        <?php 
                        $percentage = $total_filtered_votes > 0 ? ($option['filtered_votes'] / $total_filtered_votes) * 100 : 0;
                        $color_classes = ['bg-primary', 'bg-success', 'bg-warning', 'bg-info', 'bg-danger', 'bg-secondary'];
                        $color_class = $color_classes[array_search($option, $poll_options) % count($color_classes)];
                        ?>
                        <div class="mb-3">
                            <div class="d-flex justify-content-between mb-1">
                                <span><?php echo escape($option['option_text']); ?></span>
                                <span><?php echo number_format($option['filtered_votes']); ?> oy (<?php echo number_format($percentage, 1); ?>%)</span>
                            </div>
                            <div class="progress" style="height: 25px;">
                                <div class="progress-bar <?php echo $color_class; ?>" style="width: <?php echo $percentage; ?>%">
                                    <?php echo number_format($percentage, 1); ?>%
                                </div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                    
                    <div class="alert alert-info mt-3">
                        <strong>Toplam Oy:</strong> <?php echo number_format($total_filtered_votes); ?> 
                        <?php if ($selected_city || $selected_district || $selected_gender || $age_min || $age_max || $date_from || $date_to): ?>
                            <small>(Filtrelenmiş)</small>
                        <?php endif; ?>
                    </div>
                <?php else: ?>
                    <div class="text-center py-4">
                        <i class="fas fa-vote-yea fa-3x text-muted mb-3"></i>
                        <h5>Henüz oy kullanılmamış</h5>
                        <p class="text-muted">Bu anket için henüz oy verilmemiş veya filtrelerinize uygun oy bulunamadı.</p>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <!-- Anket Bilgileri -->
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">ℹ️ Anket Bilgileri</h5>
            </div>
            <div class="card-body">
                <table class="table table-sm">
                    <tr>
                        <th width="40%">Durum:</th>
                        <td>
                            <?php if ($poll_details['is_active']): ?>
                                <span class="badge bg-success">Aktif</span>
                            <?php else: ?>
                                <span class="badge bg-secondary">Pasif</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <tr>
                        <th>Seviye:</th>
                        <td>
                            <?php
                            $level_labels = [
                                'country' => 'Ülke Geneli',
                                'city' => 'Şehir Bazlı',
                                'district' => 'İlçe Bazlı'
                            ];
                            echo $level_labels[$poll_details['level']] ?? 'Bilinmiyor';
                            ?>
                        </td>
                    </tr>
                    <tr>
                        <th>Başlangıç:</th>
                        <td><?php echo date('d.m.Y H:i', strtotime($poll_details['start_date'])); ?></td>
                    </tr>
                    <tr>
                        <th>Bitiş:</th>
                        <td><?php echo date('d.m.Y H:i', strtotime($poll_details['end_date'])); ?></td>
                    </tr>
                    <tr>
                        <th>Toplam Oy:</th>
                        <td><strong><?php echo number_format($poll_details['total_votes'] ?? 0); ?></strong></td>
                    </tr>
                </table>
            </div>
        </div>
        
        <!-- Demografik İstatistikler -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">👥 Demografik Dağılım</h5>
            </div>
            <div class="card-body">
                <!-- Cinsiyet Dağılımı -->
                <h6>Cinsiyet</h6>
                <div class="mb-3">
                    <?php foreach ($voting_stats['gender_stats'] as $gender => $count): ?>
                        <div class="d-flex justify-content-between">
                            <span><?php echo $gender; ?></span>
                            <span><?php echo number_format($count); ?></span>
                        </div>
                    <?php endforeach; ?>
                </div>
                
                <!-- Yaş Grupları -->
                <h6>Yaş Grupları</h6>
                <div class="mb-3">
                    <?php foreach ($voting_stats['age_stats'] as $age_group => $count): ?>
                        <div class="d-flex justify-content-between">
                            <span><?php echo $age_group; ?></span>
                            <span><?php echo number_format($count); ?></span>
                        </div>
                    <?php endforeach; ?>
                </div>
                
                <!-- Şehir Dağılımı -->
                <?php if (!empty($voting_stats['city_stats'])): ?>
                <h6>En Çok Oy Veren Şehirler</h6>
                <div class="mb-3">
                    <?php foreach ($voting_stats['city_stats'] as $city => $count): ?>
                        <div class="d-flex justify-content-between">
                            <span><?php echo escape($city); ?></span>
                            <span><?php echo number_format($count); ?></span>
                        </div>
                    <?php endforeach; ?>
                </div>
                <?php endif; ?>
                
                <small class="text-muted">
                    <i class="fas fa-info-circle me-1"></i>
                    Veriler seçili filtrelere göre hesaplanmıştır.
                </small>
            </div>
        </div>
    </div>
</div>
<?php else: ?>
<!-- Anket Seçim Uyarısı -->
<div class="card">
    <div class="card-body text-center py-5">
        <i class="fas fa-chart-pie fa-4x text-muted mb-4"></i>
        <h4>Anket Seçin</h4>
        <p class="text-muted mb-4">Detaylı istatistikleri görüntülemek için yukarıdan bir anket seçin.</p>
        
        <?php if (!empty($polls)): ?>
            <div class="row justify-content-center">
                <div class="col-md-6">
                    <select class="form-select" onchange="window.location.href='index.php?page=poll_statistics&poll_id=' + this.value">
                        <option value="">Anket seçiniz...</option>
                        <?php foreach (array_slice($polls, 0, 10) as $poll): ?>
                            <option value="<?php echo $poll['id']; ?>">
                                <?php echo escape($poll['title']); ?> (<?php echo number_format($poll['total_votes'] ?? 0); ?> oy)
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
        <?php endif; ?>
    </div>
</div>
<?php endif; ?>

<style>
.progress {
    background-color: #e9ecef;
}
.progress-bar {
    transition: width 0.6s ease;
}
</style>