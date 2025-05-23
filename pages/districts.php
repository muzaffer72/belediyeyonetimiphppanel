<?php
// Check permission
if (!hasPermission('manage_districts')) {
    echo '<div class="alert alert-danger">Bu sayfaya erişim yetkiniz bulunmamaktadır.</div>';
    exit;
}

// Get selected city if specified
$selectedCityId = isset($_GET['city_id']) ? $_GET['city_id'] : null;

// Process form submissions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Add or update district
    if (isset($_POST['action']) && ($_POST['action'] === 'add' || $_POST['action'] === 'edit')) {
        $name = sanitize($_POST['name']);
        $cityId = $_POST['city_id'];
        $politicalPartyId = !empty($_POST['political_party_id']) ? $_POST['political_party_id'] : null;
        $mayorName = sanitize($_POST['mayor_name'] ?? '');
        $populationCount = sanitize($_POST['population_count'] ?? '');
        
        try {
            if ($_POST['action'] === 'add') {
                // Add new district
                $stmt = $pdo->prepare("
                    INSERT INTO districts 
                    (name, city_id, political_party_id, mayor_name, population_count, created_at)
                    VALUES (:name, :city_id, :political_party_id, :mayor_name, :population_count, NOW())
                ");
                
                $stmt->execute([
                    'name' => $name,
                    'city_id' => $cityId,
                    'political_party_id' => $politicalPartyId,
                    'mayor_name' => $mayorName,
                    'population_count' => $populationCount
                ]);
                
                $_SESSION['success_message'] = "İlçe başarıyla eklendi.";
            } else {
                // Update existing district
                $districtId = $_POST['district_id'];
                
                $stmt = $pdo->prepare("
                    UPDATE districts 
                    SET name = :name,
                        city_id = :city_id,
                        political_party_id = :political_party_id,
                        mayor_name = :mayor_name,
                        population_count = :population_count,
                        updated_at = NOW()
                    WHERE id = :id
                ");
                
                $stmt->execute([
                    'name' => $name,
                    'city_id' => $cityId,
                    'political_party_id' => $politicalPartyId,
                    'mayor_name' => $mayorName,
                    'population_count' => $populationCount,
                    'id' => $districtId
                ]);
                
                $_SESSION['success_message'] = "İlçe başarıyla güncellendi.";
            }
            
            // Update city stats after district change
            $pdo->prepare("SELECT party_stats_update_city(:city_id)")->execute(['city_id' => $cityId]);
            
            // Update party scores
            $pdo->query("SELECT party_stats_calculate_scores()");
            
        } catch (PDOException $e) {
            $_SESSION['error_message'] = "İşlem sırasında bir hata oluştu: " . $e->getMessage();
        }
        
        // Redirect to refresh the page
        header('Location: index.php?page=districts' . ($selectedCityId ? "&city_id=$selectedCityId" : ''));
        exit;
    }
    
    // Delete district
    if (isset($_POST['action']) && $_POST['action'] === 'delete' && isset($_POST['district_id'])) {
        $districtId = $_POST['district_id'];
        
        try {
            // Check if district has posts
            $stmt = $pdo->prepare("
                SELECT COUNT(*) FROM posts p
                JOIN districts d ON p.district = d.name
                WHERE d.id = :district_id
            ");
            $stmt->execute(['district_id' => $districtId]);
            $postCount = $stmt->fetchColumn();
            
            if ($postCount > 0) {
                $_SESSION['error_message'] = "Bu ilçeye ait gönderiler olduğu için silinemez.";
            } else {
                // Get city ID for later use
                $stmt = $pdo->prepare("SELECT city_id FROM districts WHERE id = :id");
                $stmt->execute(['id' => $districtId]);
                $cityId = $stmt->fetchColumn();
                
                // Delete the district
                $stmt = $pdo->prepare("DELETE FROM districts WHERE id = :id");
                $stmt->execute(['id' => $districtId]);
                
                // Update city stats
                if ($cityId) {
                    $pdo->prepare("SELECT party_stats_update_city(:city_id)")->execute(['city_id' => $cityId]);
                    
                    // Update party scores
                    $pdo->query("SELECT party_stats_calculate_scores()");
                }
                
                $_SESSION['success_message'] = "İlçe başarıyla silindi.";
            }
        } catch (PDOException $e) {
            $_SESSION['error_message'] = "Silme işlemi sırasında bir hata oluştu: " . $e->getMessage();
        }
        
        // Redirect to refresh the page
        header('Location: index.php?page=districts' . ($selectedCityId ? "&city_id=$selectedCityId" : ''));
        exit;
    }
}

// Get cities for dropdown
$cities = getCities();

// Get political parties for dropdown
$politicalParties = getPoliticalParties();

// Get districts with city and party info
$districts = [];
try {
    $query = "
        SELECT d.*, c.name as city_name, pp.name as party_name
        FROM districts d
        LEFT JOIN cities c ON d.city_id = c.id
        LEFT JOIN political_parties pp ON d.political_party_id = pp.id
    ";
    
    // Add filter if city is selected
    if ($selectedCityId) {
        $query .= " WHERE d.city_id = :city_id";
        $stmt = $pdo->prepare($query . " ORDER BY d.name");
        $stmt->execute(['city_id' => $selectedCityId]);
    } else {
        $stmt = $pdo->query($query . " ORDER BY c.name, d.name");
    }
    
    $districts = $stmt->fetchAll();
    
    // Get selected city name if specified
    $selectedCityName = '';
    if ($selectedCityId) {
        $stmt = $pdo->prepare("SELECT name FROM cities WHERE id = :id");
        $stmt->execute(['id' => $selectedCityId]);
        $selectedCityName = $stmt->fetchColumn();
    }
} catch (PDOException $e) {
    echo '<div class="alert alert-danger">İlçe verileri yüklenirken bir hata oluştu: ' . $e->getMessage() . '</div>';
}
?>

<!-- Add/Edit District Modal -->
<div class="modal fade" id="districtModal" tabindex="-1" aria-labelledby="districtModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="districtModalLabel">İlçe Ekle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <form id="districtForm" action="index.php?page=districts<?php echo $selectedCityId ? "&city_id=$selectedCityId" : ''; ?>" method="post">
                <div class="modal-body">
                    <input type="hidden" name="action" id="district-action" value="add">
                    <input type="hidden" name="district_id" id="district-id" value="">
                    
                    <div class="mb-3">
                        <label for="name" class="form-label">İlçe Adı</label>
                        <input type="text" class="form-control" id="name" name="name" required>
                    </div>
                    
                    <div class="mb-3">
                        <label for="city_id" class="form-label">Şehir</label>
                        <select class="form-select" id="city_id" name="city_id" required>
                            <option value="">Şehir Seçin</option>
                            <?php foreach ($cities as $city): ?>
                            <option value="<?php echo $city['id']; ?>" <?php echo ($selectedCityId == $city['id']) ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($city['name']); ?>
                                <?php echo $city['is_metropolitan'] ? ' (Büyükşehir)' : ''; ?>
                            </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="political_party_id" class="form-label">Yönetici Parti</label>
                        <select class="form-select" id="political_party_id" name="political_party_id">
                            <option value="">Parti Seçin</option>
                            <?php foreach ($politicalParties as $party): ?>
                            <option value="<?php echo $party['id']; ?>"><?php echo htmlspecialchars($party['name']); ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label for="mayor_name" class="form-label">Belediye Başkanı</label>
                        <input type="text" class="form-control" id="mayor_name" name="mayor_name">
                    </div>
                    
                    <div class="mb-3">
                        <label for="population_count" class="form-label">Nüfus</label>
                        <input type="text" class="form-control" id="population_count" name="population_count">
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <button type="submit" class="btn btn-primary">Kaydet</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Delete District Confirmation Modal -->
<div class="modal fade" id="deleteDistrictModal" tabindex="-1" aria-labelledby="deleteDistrictModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="deleteDistrictModalLabel">İlçeyi Sil</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <p>Bu ilçeyi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                <form action="index.php?page=districts<?php echo $selectedCityId ? "&city_id=$selectedCityId" : ''; ?>" method="post">
                    <input type="hidden" name="action" value="delete">
                    <input type="hidden" name="district_id" id="delete-district-id" value="">
                    <button type="submit" class="btn btn-danger">Sil</button>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- Main Content -->
<div class="card shadow mb-4">
    <div class="card-header py-3 d-flex justify-content-between align-items-center">
        <h6 class="m-0 font-weight-bold text-primary">
            <?php if ($selectedCityName): ?>
            <?php echo htmlspecialchars($selectedCityName); ?> İlçeleri
            <a href="index.php?page=districts" class="btn btn-sm btn-outline-secondary ms-2">
                <i class="fas fa-arrow-left me-1"></i>Tüm İlçeler
            </a>
            <?php else: ?>
            Tüm İlçeler
            <?php endif; ?>
        </h6>
        <button type="button" class="btn btn-primary btn-sm" data-bs-toggle="modal" data-bs-target="#districtModal" onclick="resetDistrictForm()">
            <i class="fas fa-plus-circle me-1"></i>Yeni İlçe Ekle
        </button>
    </div>
    <div class="card-body">
        <?php if (!$selectedCityId): ?>
        <div class="mb-3">
            <form method="get" action="index.php">
                <input type="hidden" name="page" value="districts">
                <div class="row g-2">
                    <div class="col-md-4">
                        <select name="city_id" class="form-select">
                            <option value="">Tüm Şehirler</option>
                            <?php foreach ($cities as $city): ?>
                            <option value="<?php echo $city['id']; ?>">
                                <?php echo htmlspecialchars($city['name']); ?>
                                <?php echo $city['is_metropolitan'] ? ' (Büyükşehir)' : ''; ?>
                            </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="col-auto">
                        <button type="submit" class="btn btn-primary">Filtrele</button>
                    </div>
                </div>
            </form>
        </div>
        <?php endif; ?>
        
        <div class="table-responsive">
            <table class="table table-bordered table-hover" id="districtsTable" width="100%" cellspacing="0">
                <thead>
                    <tr>
                        <?php if (!$selectedCityId): ?>
                        <th>Şehir</th>
                        <?php endif; ?>
                        <th>İlçe Adı</th>
                        <th>Yönetici Parti</th>
                        <th>Belediye Başkanı</th>
                        <th>Nüfus</th>
                        <th>Şikayet Sayısı</th>
                        <th>Çözülen Şikayet</th>
                        <th>Teşekkür</th>
                        <th>Çözüm Oranı</th>
                        <th>İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($districts as $district): ?>
                    <tr>
                        <?php if (!$selectedCityId): ?>
                        <td><?php echo htmlspecialchars($district['city_name']); ?></td>
                        <?php endif; ?>
                        <td><?php echo htmlspecialchars($district['name']); ?></td>
                        <td><?php echo htmlspecialchars($district['party_name'] ?? 'Belirtilmemiş'); ?></td>
                        <td><?php echo htmlspecialchars($district['mayor_name'] ?? 'Belirtilmemiş'); ?></td>
                        <td><?php echo htmlspecialchars($district['population_count'] ?? 'Belirtilmemiş'); ?></td>
                        <td><?php echo htmlspecialchars($district['total_complaints'] ?? '0'); ?></td>
                        <td><?php echo htmlspecialchars($district['solved_complaints'] ?? '0'); ?></td>
                        <td><?php echo htmlspecialchars($district['thanks_count'] ?? '0'); ?></td>
                        <td>
                            <?php 
                            $solutionRate = floatval($district['solution_rate'] ?? 0);
                            $colorClass = $solutionRate >= 75 ? 'bg-success' : ($solutionRate >= 50 ? 'bg-info' : ($solutionRate >= 25 ? 'bg-warning' : 'bg-danger'));
                            ?>
                            <div class="progress" style="height: 20px;">
                                <div class="progress-bar <?php echo $colorClass; ?>" role="progressbar" style="width: <?php echo min($solutionRate, 100); ?>%" aria-valuenow="<?php echo min($solutionRate, 100); ?>" aria-valuemin="0" aria-valuemax="100">
                                    <?php echo number_format($solutionRate, 1); ?>%
                                </div>
                            </div>
                        </td>
                        <td>
                            <button type="button" class="btn btn-sm btn-primary me-1" onclick="editDistrict(<?php echo htmlspecialchars(json_encode($district)); ?>)">
                                <i class="fas fa-edit"></i>
                            </button>
                            <button type="button" class="btn btn-sm btn-danger" onclick="deleteDistrict('<?php echo $district['id']; ?>', '<?php echo htmlspecialchars($district['name']); ?>')">
                                <i class="fas fa-trash"></i>
                            </button>
                            <a href="index.php?page=posts&district=<?php echo urlencode($district['name']); ?>" class="btn btn-sm btn-info ms-1">
                                <i class="fas fa-clipboard-list"></i> Gönderiler
                            </a>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                    
                    <?php if (empty($districts)): ?>
                    <tr>
                        <td colspan="<?php echo $selectedCityId ? '9' : '10'; ?>" class="text-center">Henüz ilçe kaydı bulunmamaktadır.</td>
                    </tr>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<script>
function resetDistrictForm() {
    document.getElementById('districtForm').reset();
    document.getElementById('district-action').value = 'add';
    document.getElementById('district-id').value = '';
    document.getElementById('districtModalLabel').innerText = 'İlçe Ekle';
    
    // If we're filtering by city, preselect that city
    <?php if ($selectedCityId): ?>
    document.getElementById('city_id').value = '<?php echo $selectedCityId; ?>';
    <?php endif; ?>
}

function editDistrict(district) {
    document.getElementById('district-action').value = 'edit';
    document.getElementById('district-id').value = district.id;
    document.getElementById('name').value = district.name;
    document.getElementById('city_id').value = district.city_id;
    document.getElementById('political_party_id').value = district.political_party_id || '';
    document.getElementById('mayor_name').value = district.mayor_name || '';
    document.getElementById('population_count').value = district.population_count || '';
    document.getElementById('districtModalLabel').innerText = 'İlçeyi Düzenle: ' + district.name;
    
    // Open the modal
    var modal = new bootstrap.Modal(document.getElementById('districtModal'));
    modal.show();
}

function deleteDistrict(districtId, districtName) {
    document.getElementById('delete-district-id').value = districtId;
    document.getElementById('deleteDistrictModalLabel').innerText = 'İlçeyi Sil: ' + districtName;
    
    // Open the confirmation modal
    var modal = new bootstrap.Modal(document.getElementById('deleteDistrictModal'));
    modal.show();
}
</script>