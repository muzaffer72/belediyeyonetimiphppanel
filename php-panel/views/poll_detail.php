<?php
// Anket detay sayfası
require_once(__DIR__ . '/../includes/functions.php');

if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['message'] = 'Geçersiz anket ID';
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=polls');
}

$poll_id = $_GET['id'];

// Anket bilgilerini getir
$poll_result = getDataById('polls', $poll_id);
if ($poll_result['error'] || !$poll_result['data']) {
    $_SESSION['message'] = 'Anket bulunamadı';
    $_SESSION['message_type'] = 'danger';
    redirect('index.php?page=polls');
}

$poll = $poll_result['data'];

// Anket seçeneklerini getir
$options_result = getData('poll_options', ['poll_id' => 'eq.' . $poll_id, 'order' => 'created_at']);
$poll_options = $options_result['data'] ?? [];

// Son oyları getir (kullanıcı bilgileriyle birlikte)
$recent_votes_result = getData('poll_votes', [
    'poll_id' => 'eq.' . $poll_id,
    'order' => 'created_at.desc',
    'limit' => 20
]);
$recent_votes = $recent_votes_result['data'] ?? [];

// Kullanıcı bilgilerini getir
foreach ($recent_votes as &$vote) {
    if ($vote['user_id']) {
        $user_result = getDataById('users', $vote['user_id']);
        $vote['user'] = $user_result['data'] ?? null;
    }
    
    // Seçenek bilgisini ekle
    foreach ($poll_options as $option) {
        if ($option['id'] === $vote['option_id']) {
            $vote['option_text'] = $option['option_text'];
            break;
        }
    }
}

// Şehir ve ilçe bilgilerini getir
$poll['city_name'] = null;
$poll['district_name'] = null;

if ($poll['city_id']) {
    $city_result = getDataById('cities', $poll['city_id']);
    $poll['city_name'] = $city_result['data']['name'] ?? null;
}

if ($poll['district_id']) {
    $district_result = getDataById('districts', $poll['district_id']);
    $poll['district_name'] = $district_result['data']['name'] ?? null;
}

// Oluşturan kullanıcı bilgisi
$creator = null;
if ($poll['created_by']) {
    $creator_result = getDataById('users', $poll['created_by']);
    $creator = $creator_result['data'] ?? null;
}

// Toplam oy sayısını gerçek verilerden hesapla
$total_votes = 0;
foreach ($poll_options as $option) {
    $votes_result = getData('poll_votes', [
        'option_id' => 'eq.' . $option['id'],
        'select' => 'count'
    ]);
    $vote_count = $votes_result['data'][0]['count'] ?? 0;
    $option['real_vote_count'] = $vote_count;
    $total_votes += $vote_count;
}
?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">📋 Anket Detayı</h1>
    <div>
        <a href="index.php?page=poll_statistics&poll_id=<?php echo $poll_id; ?>" class="btn btn-info me-2">
            <i class="fas fa-chart-bar me-1"></i> İstatistikler
        </a>
        <a href="index.php?page=poll_edit&id=<?php echo $poll_id; ?>" class="btn btn-warning me-2">
            <i class="fas fa-edit me-1"></i> Düzenle
        </a>
        <a href="index.php?page=polls" class="btn btn-secondary">
            <i class="fas fa-arrow-left me-1"></i> Anketlere Dön
        </a>
    </div>
</div>

<div class="row">
    <div class="col-md-8">
        <!-- Anket Bilgileri -->
        <div class="card mb-4">
            <div class="card-header">
                <div class="d-flex justify-content-between align-items-center">
                    <h5 class="mb-0"><?php echo escape($poll['title']); ?></h5>
                    <div>
                        <?php if ($poll['is_active']): ?>
                            <span class="badge bg-success">Aktif</span>
                        <?php else: ?>
                            <span class="badge bg-secondary">Pasif</span>
                        <?php endif; ?>
                        
                        <?php if ($poll['onecikar']): ?>
                            <span class="badge bg-warning text-dark">Öne Çıkan</span>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
            <div class="card-body">
                <?php if ($poll['mini_title']): ?>
                    <h6 class="text-muted mb-3"><?php echo escape($poll['mini_title']); ?></h6>
                <?php endif; ?>
                
                <p class="mb-4"><?php echo nl2br(escape($poll['description'])); ?></p>
                
                <div class="row">
                    <div class="col-md-6">
                        <strong>Seviye:</strong>
                        <?php
                        $level_labels = [
                            'country' => '<span class="badge bg-primary">Ülke Geneli</span>',
                            'city' => '<span class="badge bg-info">Şehir: ' . escape($poll['city_name'] ?? 'Bilinmiyor') . '</span>',
                            'district' => '<span class="badge bg-warning text-dark">İlçe: ' . escape($poll['district_name'] ?? 'Bilinmiyor') . '</span>'
                        ];
                        echo $level_labels[$poll['level']] ?? '<span class="badge bg-secondary">Bilinmiyor</span>';
                        ?>
                    </div>
                    <div class="col-md-6">
                        <strong>Toplam Oy:</strong> 
                        <span class="badge bg-success fs-6"><?php echo number_format($total_votes); ?></span>
                    </div>
                </div>
            </div>
        </div>

        <!-- Oy Dağılımı -->
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">📊 Oy Dağılımı</h5>
            </div>
            <div class="card-body">
                <?php if ($total_votes > 0): ?>
                    <?php 
                    $colors = ['primary', 'success', 'warning', 'info', 'danger', 'secondary'];
                    ?>
                    <?php foreach ($poll_options as $index => $option): ?>
                        <?php 
                        $vote_count = intval($option['real_vote_count'] ?? 0);
                        $percentage = $total_votes > 0 ? ($vote_count / $total_votes) * 100 : 0;
                        $color = $colors[$index % count($colors)];
                        ?>
                        <div class="mb-3">
                            <div class="d-flex justify-content-between mb-2">
                                <strong><?php echo escape($option['option_text']); ?></strong>
                                <span class="badge bg-<?php echo $color; ?>">
                                    <?php echo number_format($vote_count); ?> oy (<?php echo number_format($percentage, 1); ?>%)
                                </span>
                            </div>
                            <div class="progress" style="height: 25px;">
                                <div class="progress-bar bg-<?php echo $color; ?>" 
                                     style="width: <?php echo $percentage; ?>%"
                                     aria-valuenow="<?php echo $percentage; ?>" 
                                     aria-valuemin="0" 
                                     aria-valuemax="100">
                                    <?php echo number_format($percentage, 1); ?>%
                                </div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php else: ?>
                    <div class="text-center py-4">
                        <i class="fas fa-vote-yea fa-3x text-muted mb-3"></i>
                        <h5>Henüz oy kullanılmamış</h5>
                        <p class="text-muted">Bu anket için henüz hiç oy verilmemiş.</p>
                    </div>
                <?php endif; ?>
            </div>
        </div>

        <!-- Son Oylar -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">🗳️ Son Oylar</h5>
            </div>
            <div class="card-body">
                <?php if (!empty($recent_votes)): ?>
                    <div class="table-responsive">
                        <table class="table table-sm">
                            <thead>
                                <tr>
                                    <th>Kullanıcı</th>
                                    <th>Seçim</th>
                                    <th>Konum</th>
                                    <th>Tarih</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach (array_slice($recent_votes, 0, 10) as $vote): ?>
                                    <tr>
                                        <td>
                                            <?php if ($vote['user']): ?>
                                                <div class="d-flex align-items-center">
                                                    <?php if ($vote['user']['profile_image_url']): ?>
                                                        <img src="<?php echo escape($vote['user']['profile_image_url']); ?>" 
                                                             class="rounded-circle me-2" width="24" height="24">
                                                    <?php else: ?>
                                                        <div class="bg-secondary rounded-circle me-2 d-flex align-items-center justify-content-center" 
                                                             style="width: 24px; height: 24px; font-size: 12px; color: white;">
                                                            <?php echo strtoupper(substr($vote['user']['display_name'] ?? 'U', 0, 1)); ?>
                                                        </div>
                                                    <?php endif; ?>
                                                    <div>
                                                        <small><strong><?php echo escape($vote['user']['display_name'] ?? 'Kullanıcı'); ?></strong></small>
                                                        <?php if ($vote['user']['age']): ?>
                                                            <br><small class="text-muted"><?php echo $vote['user']['age']; ?> yaş, <?php echo escape($vote['user']['gender'] ?? ''); ?></small>
                                                        <?php endif; ?>
                                                    </div>
                                                </div>
                                            <?php else: ?>
                                                <small class="text-muted">Anonim Kullanıcı</small>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <span class="badge bg-info"><?php echo escape($vote['option_text'] ?? 'Bilinmiyor'); ?></span>
                                        </td>
                                        <td>
                                            <?php if ($vote['user'] && ($vote['user']['city'] || $vote['user']['district'])): ?>
                                                <small><?php echo escape($vote['user']['city'] ?? ''); ?><?php echo $vote['user']['district'] ? ' / ' . escape($vote['user']['district']) : ''; ?></small>
                                            <?php else: ?>
                                                <small class="text-muted">-</small>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <small><?php echo date('d.m.Y H:i', strtotime($vote['created_at'])); ?></small>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                    
                    <?php if (count($recent_votes) > 10): ?>
                        <div class="text-center mt-3">
                            <a href="index.php?page=poll_statistics&poll_id=<?php echo $poll_id; ?>" class="btn btn-outline-primary btn-sm">
                                Tüm Oyları Görüntüle
                            </a>
                        </div>
                    <?php endif; ?>
                <?php else: ?>
                    <div class="text-center py-3">
                        <i class="fas fa-inbox fa-2x text-muted mb-2"></i>
                        <p class="text-muted mb-0">Henüz oy kullanılmamış</p>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <div class="col-md-4">
        <!-- Anket Özeti -->
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="mb-0">📋 Anket Özeti</h5>
            </div>
            <div class="card-body">
                <table class="table table-sm">
                    <tr>
                        <th width="40%">ID:</th>
                        <td><code><?php echo escape($poll_id); ?></code></td>
                    </tr>
                    <tr>
                        <th>Oluşturan:</th>
                        <td><?php echo $creator ? escape($creator['display_name'] ?? $creator['username']) : 'Bilinmiyor'; ?></td>
                    </tr>
                    <tr>
                        <th>Oluşturulma:</th>
                        <td><?php echo date('d.m.Y H:i', strtotime($poll['created_at'])); ?></td>
                    </tr>
                    <tr>
                        <th>Başlangıç:</th>
                        <td><?php echo date('d.m.Y H:i', strtotime($poll['start_date'])); ?></td>
                    </tr>
                    <tr>
                        <th>Bitiş:</th>
                        <td><?php echo date('d.m.Y H:i', strtotime($poll['end_date'])); ?></td>
                    </tr>
                    <tr>
                        <th>Seçenek Sayısı:</th>
                        <td><?php echo count($poll_options); ?></td>
                    </tr>
                    <tr>
                        <th>Toplam Oy:</th>
                        <td><strong><?php echo number_format($total_votes); ?></strong></td>
                    </tr>
                </table>
            </div>
        </div>

        <!-- Hızlı İşlemler -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">⚡ Hızlı İşlemler</h5>
            </div>
            <div class="card-body">
                <div class="d-grid gap-2">
                    <a href="index.php?page=poll_edit&id=<?php echo $poll_id; ?>" class="btn btn-outline-warning btn-sm">
                        <i class="fas fa-edit me-1"></i> Anketi Düzenle
                    </a>
                    
                    <a href="index.php?page=poll_statistics&poll_id=<?php echo $poll_id; ?>" class="btn btn-outline-info btn-sm">
                        <i class="fas fa-chart-bar me-1"></i> Detaylı İstatistikler
                    </a>
                    
                    <a href="index.php?page=polls&toggle=<?php echo $poll_id; ?>" 
                       class="btn btn-outline-<?php echo $poll['is_active'] ? 'warning' : 'success'; ?> btn-sm">
                        <i class="fas fa-<?php echo $poll['is_active'] ? 'pause' : 'play'; ?> me-1"></i>
                        <?php echo $poll['is_active'] ? 'Duraklat' : 'Aktifleştir'; ?>
                    </a>
                    
                    <button type="button" class="btn btn-outline-danger btn-sm" 
                            onclick="confirmDelete('<?php echo $poll_id; ?>', '<?php echo escape($poll['title']); ?>')">
                        <i class="fas fa-trash me-1"></i> Anketi Sil
                    </button>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
function confirmDelete(pollId, pollTitle) {
    if (confirm('Bu anketi silmek istediğinizden emin misiniz?\n\nAnket: ' + pollTitle + '\n\nBu işlem geri alınamaz!')) {
        window.location.href = 'index.php?page=polls&delete=' + pollId;
    }
}
</script>

<style>
.progress {
    background-color: #e9ecef;
}
.progress-bar {
    transition: width 0.6s ease;
}
</style>