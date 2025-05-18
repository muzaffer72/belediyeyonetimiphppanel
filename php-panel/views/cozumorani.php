<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// Çözüm oranı verilerini al
$cozumorani_result = getData('cozumorani');
$cozumorani = $cozumorani_result['data'] ?? [];

// Şehir ve ilçe verilerini al
$cities_result = getData('cities');
$cities = $cities_result['data'] ?? [];

$districts_result = getData('districts');
$districts = $districts_result['data'] ?? [];

// Çözüm oranı tablosu var mı kontrol et
$hasTable = !empty($cozumorani);

// Parti verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'] ?? [];

// Çözüm oranı güncellemesi için form gönderimleri
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_solution_rates'])) {
    try {
        // Cron scriptini çalıştır
        include_once(__DIR__ . '/../cron/update_solution_rates.php');
        
        $_SESSION['message'] = 'Çözüm oranları ve parti puanları başarıyla güncellendi';
        $_SESSION['message_type'] = 'success';
    } catch (Exception $e) {
        $_SESSION['message'] = 'Çözüm oranları güncellenirken bir hata oluştu: ' . $e->getMessage();
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yenile (formun tekrar gönderilmesini önlemek için)
    if (!headers_sent()) {
        header('Location: index.php?page=cozumorani');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cozumorani";</script>';
        exit;
    }
}

// Çözüm oranı tablosunu oluştur
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['create_table'])) {
    try {
        // Tablo oluşturma scriptini çalıştır
        include_once(__DIR__ . '/../cron/create_cozumorani_table.php');
        
        $_SESSION['message'] = 'Çözüm oranları tablosu başarıyla oluşturuldu';
        $_SESSION['message_type'] = 'success';
    } catch (Exception $e) {
        $_SESSION['message'] = 'Tablo oluşturulurken bir hata oluştu: ' . $e->getMessage();
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yenile
    if (!headers_sent()) {
        header('Location: index.php?page=cozumorani');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cozumorani";</script>';
        exit;
    }
}
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Çözüm Oranları Yönetimi</h1>
    
    <div>
        <?php if ($hasTable): ?>
            <form method="post" action="" class="d-inline">
                <button type="submit" name="update_solution_rates" class="btn btn-primary">
                    <i class="fas fa-sync-alt me-1"></i> Çözüm Oranlarını Güncelle
                </button>
            </form>
        <?php else: ?>
            <form method="post" action="" class="d-inline">
                <button type="submit" name="create_table" class="btn btn-warning">
                    <i class="fas fa-table me-1"></i> Çözüm Oranları Tablosunu Oluştur
                </button>
            </form>
        <?php endif; ?>
        
        <a href="index.php?page=dashboard" class="btn btn-secondary ms-2">
            <i class="fas fa-arrow-left me-1"></i> Panele Dön
        </a>
    </div>
</div>

<!-- İşlem Mesajları -->
<?php if(isset($_SESSION['message'])): ?>
<div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
    <?php echo $_SESSION['message']; ?>
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>
<?php 
    unset($_SESSION['message']);
    unset($_SESSION['message_type']);
endif; 
?>

<!-- Cron Bilgileri -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-clock me-1"></i> Cron İşlemi Bilgisi
    </div>
    <div class="card-body">
        <p>Çözüm oranları ve parti puanları, paylaşılan şikayetlerin ve teşekkürlerin istatistiklerine göre hesaplanır. Bu hesaplama her gün otomatik olarak yapılabilir.</p>
        
        <h5>Cron URL'i:</h5>
        <div class="input-group mb-3">
            <input type="text" class="form-control" value="<?php echo SITE_URL; ?>/api/cron.php?job=update_solution_rates&api_key=MY_SECURE_CRON_API_KEY" id="cronUrl" readonly>
            <button class="btn btn-outline-secondary" type="button" onclick="copyToClipboard('cronUrl')">Kopyala</button>
        </div>
        
        <p class="text-muted small">Bu URL'i günlük olarak çalıştıracak bir cron görevi oluşturabilirsiniz. Örneğin: <code>0 0 * * * curl "<?php echo SITE_URL; ?>/api/cron.php?job=update_solution_rates&api_key=MY_SECURE_CRON_API_KEY"</code></p>
    </div>
</div>

<?php if ($hasTable): ?>
<!-- Şehirlerin Çözüm Oranları -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-city me-1"></i> Şehirlerin Çözüm Oranları
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-hover" id="cityRatesTable">
                <thead class="table-light">
                    <tr>
                        <th>Şehir</th>
                        <th>Toplam Şikayet</th>
                        <th>Çözülen Şikayet</th>
                        <th>Teşekkür Sayısı</th>
                        <th>Çözüm Oranı</th>
                        <th>Son Güncelleme</th>
                    </tr>
                </thead>
                <tbody>
                    <?php
                    $city_rates = array_filter($cozumorani, function($item) {
                        return $item['entity_type'] === 'city';
                    });
                    
                    if (empty($city_rates)):
                    ?>
                        <tr>
                            <td colspan="6" class="text-center">Henüz şehir çözüm oranı verisi bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($city_rates as $rate): ?>
                            <?php
                            // Şehir bilgilerini bul
                            $city_info = null;
                            foreach($cities as $city) {
                                if ($city['id'] === $rate['entity_id']) {
                                    $city_info = $city;
                                    break;
                                }
                            }
                            
                            // Parti bilgilerini bul
                            $party_info = null;
                            if ($city_info && isset($city_info['political_party_id'])) {
                                foreach($parties as $party) {
                                    if ($party['id'] === $city_info['political_party_id']) {
                                        $party_info = $party;
                                        break;
                                    }
                                }
                            }
                            ?>
                            <tr>
                                <td>
                                    <?php if ($city_info): ?>
                                        <div class="d-flex align-items-center">
                                            <?php if(isset($city_info['logo_url']) && !empty($city_info['logo_url'])): ?>
                                                <img src="<?php echo escape($city_info['logo_url']); ?>" alt="<?php echo escape($city_info['name']); ?>" class="me-2" style="height: 24px; width: auto;">
                                            <?php endif; ?>
                                            <a href="index.php?page=city_detail&id=<?php echo $city_info['id']; ?>">
                                                <?php echo escape($rate['name']); ?>
                                            </a>
                                            <?php if ($party_info): ?>
                                                <span class="badge bg-primary ms-2"><?php echo escape($party_info['name']); ?></span>
                                            <?php endif; ?>
                                        </div>
                                    <?php else: ?>
                                        <?php echo escape($rate['name']); ?>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo escape($rate['total_complaints']); ?></td>
                                <td><?php echo escape($rate['solved_complaints']); ?></td>
                                <td><?php echo escape($rate['thanks_count']); ?></td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <div class="progress flex-grow-1 me-2" style="height: 8px;">
                                            <div class="progress-bar <?php echo $rate['solution_rate'] >= 50 ? 'bg-success' : 'bg-warning'; ?>" role="progressbar" style="width: <?php echo $rate['solution_rate']; ?>%"></div>
                                        </div>
                                        <span class="badge <?php echo $rate['solution_rate'] >= 50 ? 'bg-success' : 'bg-warning'; ?>">
                                            %<?php echo number_format($rate['solution_rate'], 2); ?>
                                        </span>
                                    </div>
                                </td>
                                <td><?php echo date('d.m.Y H:i', strtotime($rate['last_updated'])); ?></td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<!-- İlçelerin Çözüm Oranları -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-map-marker-alt me-1"></i> İlçelerin Çözüm Oranları
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-hover" id="districtRatesTable">
                <thead class="table-light">
                    <tr>
                        <th>İlçe</th>
                        <th>Bağlı Olduğu Şehir</th>
                        <th>Toplam Şikayet</th>
                        <th>Çözülen Şikayet</th>
                        <th>Teşekkür Sayısı</th>
                        <th>Çözüm Oranı</th>
                        <th>Son Güncelleme</th>
                    </tr>
                </thead>
                <tbody>
                    <?php
                    $district_rates = array_filter($cozumorani, function($item) {
                        return $item['entity_type'] === 'district';
                    });
                    
                    if (empty($district_rates)):
                    ?>
                        <tr>
                            <td colspan="7" class="text-center">Henüz ilçe çözüm oranı verisi bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($district_rates as $rate): ?>
                            <?php
                            // İlçe bilgilerini bul
                            $district_info = null;
                            foreach($districts as $district) {
                                if ($district['id'] === $rate['entity_id']) {
                                    $district_info = $district;
                                    break;
                                }
                            }
                            
                            // Şehir bilgilerini bul
                            $city_info = null;
                            if ($district_info && isset($district_info['city_id'])) {
                                foreach($cities as $city) {
                                    if ($city['id'] === $district_info['city_id']) {
                                        $city_info = $city;
                                        break;
                                    }
                                }
                            }
                            
                            // Parti bilgilerini bul
                            $party_info = null;
                            if ($district_info && isset($district_info['political_party_id'])) {
                                foreach($parties as $party) {
                                    if ($party['id'] === $district_info['political_party_id']) {
                                        $party_info = $party;
                                        break;
                                    }
                                }
                            }
                            ?>
                            <tr>
                                <td>
                                    <?php if ($district_info): ?>
                                        <div class="d-flex align-items-center">
                                            <?php if(isset($district_info['logo_url']) && !empty($district_info['logo_url'])): ?>
                                                <img src="<?php echo escape($district_info['logo_url']); ?>" alt="<?php echo escape($district_info['name']); ?>" class="me-2" style="height: 24px; width: auto;">
                                            <?php endif; ?>
                                            <a href="index.php?page=district_detail&id=<?php echo $district_info['id']; ?>">
                                                <?php echo escape($rate['name']); ?>
                                            </a>
                                            <?php if ($party_info): ?>
                                                <span class="badge bg-primary ms-2"><?php echo escape($party_info['name']); ?></span>
                                            <?php endif; ?>
                                        </div>
                                    <?php else: ?>
                                        <?php echo escape($rate['name']); ?>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <?php if ($city_info): ?>
                                        <a href="index.php?page=city_detail&id=<?php echo $city_info['id']; ?>">
                                            <?php echo escape($city_info['name']); ?>
                                        </a>
                                    <?php else: ?>
                                        -
                                    <?php endif; ?>
                                </td>
                                <td><?php echo escape($rate['total_complaints']); ?></td>
                                <td><?php echo escape($rate['solved_complaints']); ?></td>
                                <td><?php echo escape($rate['thanks_count']); ?></td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <div class="progress flex-grow-1 me-2" style="height: 8px;">
                                            <div class="progress-bar <?php echo $rate['solution_rate'] >= 50 ? 'bg-success' : 'bg-warning'; ?>" role="progressbar" style="width: <?php echo $rate['solution_rate']; ?>%"></div>
                                        </div>
                                        <span class="badge <?php echo $rate['solution_rate'] >= 50 ? 'bg-success' : 'bg-warning'; ?>">
                                            %<?php echo number_format($rate['solution_rate'], 2); ?>
                                        </span>
                                    </div>
                                </td>
                                <td><?php echo date('d.m.Y H:i', strtotime($rate['last_updated'])); ?></td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<!-- Partilerin Puan Durumu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-chart-bar me-1"></i> Partilerin Puan Durumu
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-hover" id="partyScoresTable">
                <thead class="table-light">
                    <tr>
                        <th>Parti</th>
                        <th>Şehir Sayısı</th>
                        <th>İlçe Sayısı</th>
                        <th>Ortalama Çözüm Oranı</th>
                        <th>Puan (10 Üzerinden)</th>
                        <th>Son Güncelleme</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($parties)): ?>
                        <tr>
                            <td colspan="6" class="text-center">Henüz parti verisi bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($parties as $party): ?>
                            <?php
                            // Bu partiye ait şehir ve ilçe sayısını hesapla
                            $party_cities = array_filter($cities, function($city) use ($party) {
                                return isset($city['political_party_id']) && $city['political_party_id'] === $party['id'];
                            });
                            
                            $party_districts = array_filter($districts, function($district) use ($party) {
                                return isset($district['political_party_id']) && $district['political_party_id'] === $party['id'];
                            });
                            
                            // Bu partiye ait ortalama çözüm oranını hesapla
                            $total_rate = 0;
                            $entity_count = 0;
                            
                            foreach ($city_rates as $rate) {
                                foreach ($party_cities as $city) {
                                    if ($city['id'] === $rate['entity_id']) {
                                        $total_rate += $rate['solution_rate'];
                                        $entity_count++;
                                        break;
                                    }
                                }
                            }
                            
                            foreach ($district_rates as $rate) {
                                foreach ($party_districts as $district) {
                                    if ($district['id'] === $rate['entity_id']) {
                                        $total_rate += $rate['solution_rate'];
                                        $entity_count++;
                                        break;
                                    }
                                }
                            }
                            
                            $avg_rate = $entity_count > 0 ? $total_rate / $entity_count : 0;
                            ?>
                            <tr>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <?php if(isset($party['logo_url']) && !empty($party['logo_url'])): ?>
                                            <img src="<?php echo escape($party['logo_url']); ?>" alt="<?php echo escape($party['name']); ?>" class="me-2" style="height: 30px; width: auto;">
                                        <?php endif; ?>
                                        <a href="index.php?page=parties">
                                            <?php echo escape($party['name']); ?>
                                        </a>
                                    </div>
                                </td>
                                <td><?php echo count($party_cities); ?></td>
                                <td><?php echo count($party_districts); ?></td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <div class="progress flex-grow-1 me-2" style="height: 8px;">
                                            <div class="progress-bar <?php echo $avg_rate >= 50 ? 'bg-success' : 'bg-warning'; ?>" role="progressbar" style="width: <?php echo $avg_rate; ?>%"></div>
                                        </div>
                                        <span class="badge <?php echo $avg_rate >= 50 ? 'bg-success' : 'bg-warning'; ?>">
                                            %<?php echo number_format($avg_rate, 2); ?>
                                        </span>
                                    </div>
                                </td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        <div class="progress flex-grow-1 me-2" style="height: 8px;">
                                            <div class="progress-bar <?php echo $party['score'] >= 5 ? 'bg-success' : 'bg-warning'; ?>" role="progressbar" style="width: <?php echo $party['score'] * 10; ?>%"></div>
                                        </div>
                                        <span class="badge <?php echo $party['score'] >= 5 ? 'bg-success' : 'bg-warning'; ?>">
                                            <?php echo number_format($party['score'], 1); ?>
                                        </span>
                                    </div>
                                </td>
                                <td><?php echo isset($party['last_updated']) ? date('d.m.Y H:i', strtotime($party['last_updated'])) : '-'; ?></td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<?php else: ?>
<!-- Tablo Oluşturma Bilgisi -->
<div class="card mb-4">
    <div class="card-header bg-warning text-dark">
        <i class="fas fa-exclamation-triangle me-1"></i> Uyarı
    </div>
    <div class="card-body">
        <p>Çözüm oranları tablosu henüz oluşturulmamış. Bu tabloda şehir ve ilçelerin çözüm oranlarını takip edebilirsiniz.</p>
        <p>Tabloyu oluşturmak için yukarıdaki "Çözüm Oranları Tablosunu Oluştur" butonuna tıklayınız.</p>
    </div>
</div>
<?php endif; ?>

<script>
// URL kopyalama fonksiyonu
function copyToClipboard(elementId) {
    const element = document.getElementById(elementId);
    element.select();
    document.execCommand("copy");
    
    // Kopyalandı bildirimi
    alert("URL kopyalandı!");
}

// Tablolar için DataTables eklentisini etkinleştir
document.addEventListener('DOMContentLoaded', function() {
    if (typeof $.fn.DataTable !== 'undefined') {
        $('#cityRatesTable').DataTable({
            language: {
                url: '//cdn.datatables.net/plug-ins/1.10.21/i18n/Turkish.json'
            },
            order: [[4, 'desc']]
        });
        
        $('#districtRatesTable').DataTable({
            language: {
                url: '//cdn.datatables.net/plug-ins/1.10.21/i18n/Turkish.json'
            },
            order: [[5, 'desc']]
        });
        
        $('#partyScoresTable').DataTable({
            language: {
                url: '//cdn.datatables.net/plug-ins/1.10.21/i18n/Turkish.json'
            },
            order: [[4, 'desc']]
        });
    }
});
</script>