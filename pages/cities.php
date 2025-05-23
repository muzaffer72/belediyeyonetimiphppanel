<?php
// Check permission
if (!hasPermission('manage_cities')) {
    echo '<div class="alert alert-danger">Bu sayfaya erişim yetkiniz bulunmamaktadır.</div>';
    exit;
}

// Process form submissions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Add or update city
    if (isset($_POST['action']) && ($_POST['action'] === 'add' || $_POST['action'] === 'edit')) {
        $name = sanitize($_POST['name']);
        $isMetropolitan = isset($_POST['is_metropolitan']) ? 1 : 0;
        $politicalPartyId = !empty($_POST['political_party_id']) ? $_POST['political_party_id'] : null;
        $mayor = sanitize($_POST['mayor'] ?? '');
        $populationCount = sanitize($_POST['population_count'] ?? '');
        
        try {
            if ($_POST['action'] === 'add') {
                // Add new city
                $stmt = $pdo->prepare("
                    INSERT INTO cities 
                    (name, is_metropolitan, political_party_id, mayor, population_count, created_at)
                    VALUES (:name, :is_metropolitan, :political_party_id, :mayor, :population_count, NOW())
                ");
                
                $stmt->execute([
                    'name' => $name,
                    'is_metropolitan' => $isMetropolitan,
                    'political_party_id' => $politicalPartyId,
                    'mayor' => $mayor,
                    'population_count' => $populationCount
                ]);
                
                $_SESSION['success_message'] = "Şehir başarıyla eklendi.";
                
                // If metropolitan, create a default "Merkez" district
                if ($isMetropolitan) {
                    $cityId = $pdo->lastInsertId();
                    
                    $stmt = $pdo->prepare("
                        INSERT INTO districts 
                        (name, city_id, political_party_id, created_at)
                        VALUES ('Merkez', :city_id, :political_party_id, NOW())
                    ");
                    
                    $stmt->execute([
                        'city_id' => $cityId,
                        'political_party_id' => $politicalPartyId
                    ]);
                }
            } else {
                // Update existing city
                $cityId = $_POST['city_id'];
                
                $stmt = $pdo->prepare("
                    UPDATE cities 
                    SET name = :name,
                        is_metropolitan = :is_metropolitan,
                        political_party_id = :political_party_id,
                        mayor = :mayor,
                        population_count = :population_count,
                        updated_at = NOW()
                    WHERE id = :id
                ");
                
                $stmt->execute([
                    'name' => $name,
                    'is_metropolitan' => $isMetropolitan,
                    'political_party_id' => $politicalPartyId,
                    'mayor' => $mayor,
                    'population_count' => $populationCount,
                    'id' => $cityId
                ]);
                
                $_SESSION['success_message'] = "Şehir başarıyla güncellendi.";
            }
        } catch (PDOException $e) {
            $_SESSION['error_message'] = "İşlem sırasında bir hata oluştu: " . $e->getMessage();
        }
        
        // Redirect to refresh the page
        header('Location: index.php?page=cities');
        exit;
    }
    
    // Delete city
    if (isset($_POST['action']) && $_POST['action'] === 'delete' && isset($_POST['city_id'])) {
        $cityId = $_POST['city_id'];
        
        try {
            // Check if city has districts
            $stmt = $pdo->prepare("SELECT COUNT(*) FROM districts WHERE city_id = :city_id");
            $stmt->execute(['city_id' => $cityId]);
            $districtCount = $stmt->fetchColumn();
            
            if ($districtCount > 0) {
                $_SESSION['error_message'] = "Bu şehre bağlı ilçeler olduğu için silinemez. Önce ilçeleri silmelisiniz.";
            } else {
                // Delete the city
                $stmt = $pdo->prepare("DELETE FROM cities WHERE id = :id");
                $stmt->execute(['id' => $cityId]);
                
                $_SESSION['success_message'] = "Şehir başarıyla silindi.";
            }
        } catch (PDOException $e) {
            $_SESSION['error_message'] = "Silme işlemi sırasında bir hata oluştu: " . $e->getMessage();
        }
        
        // Redirect to refresh the page
        header('Location: index.php?page=cities');
        exit;
    }
}

// Get cities list with party info
$cities = [];
try {
    $stmt = $pdo->query("
        SELECT c.*, pp.name as party_name
        FROM cities c
        LEFT JOIN political_parties pp ON c.political_party_id = pp.id
        ORDER BY c.name
    ");
    $cities = $stmt->fetchAll();
} catch (PDOException $e) {
    echo '<div class="alert alert-danger">Şehir verileri yüklenirken bir hata oluştu: ' . $e->getMessage() . '</div>';
}

// Get political parties for dropdowns
$politicalParties = getPoliticalParties();
?>

<!-- Add/Edit City Modal -->
<div class="modal fade" id="cityModal" tabindex="-1" aria-labelledby="cityModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="cityModalLabel">Şehir Ekle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <form id="cityForm" action="index.php?page=cities" method="post">
                <div class="modal-body">
                    <input type="hidden" name="action" id="city-action" value="add">
                    <input type="hidden" name="city_id" id="city-id" value="">
                    
                    <div class="mb-3">
                        <label for="name" class="form-label">Şehir Adı</label>
                        <input type="text" class="form-control" id="name" name="name" required>
                    </div>
                    
                    <div class="mb-3 form-check">
                        <input type="checkbox" class="form-check-input" id="is_metropolitan" name="is_metropolitan">
                        <label class="form-check-label" for="is_metropolitan">Büyükşehir mi?</label>
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
                        <label for="mayor" class="form-label">Belediye Başkanı</label>
                        <input type="text" class="form-control" id="mayor" name="mayor">
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

<!-- Delete City Confirmation Modal -->
<div class="modal fade" id="deleteCityModal" tabindex="-1" aria-labelledby="deleteCityModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="deleteCityModalLabel">Şehri Sil</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <p>Bu şehri silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                <form action="index.php?page=cities" method="post">
                    <input type="hidden" name="action" value="delete">
                    <input type="hidden" name="city_id" id="delete-city-id" value="">
                    <button type="submit" class="btn btn-danger">Sil</button>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- Main Content -->
<div class="card shadow mb-4">
    <div class="card-header py-3 d-flex justify-content-between align-items-center">
        <h6 class="m-0 font-weight-bold text-primary">Şehirler</h6>
        <button type="button" class="btn btn-primary btn-sm" data-bs-toggle="modal" data-bs-target="#cityModal" onclick="resetCityForm()">
            <i class="fas fa-plus-circle me-1"></i>Yeni Şehir Ekle
        </button>
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-hover" id="citiesTable" width="100%" cellspacing="0">
                <thead>
                    <tr>
                        <th>Şehir Adı</th>
                        <th>Türü</th>
                        <th>Yönetici Parti</th>
                        <th>Belediye Başkanı</th>
                        <th>Nüfus</th>
                        <th>Çözüm Oranı</th>
                        <th>İlçe Sayısı</th>
                        <th>İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($cities as $city): 
                        // Get district count
                        try {
                            $stmt = $pdo->prepare("SELECT COUNT(*) FROM districts WHERE city_id = :city_id");
                            $stmt->execute(['city_id' => $city['id']]);
                            $districtCount = $stmt->fetchColumn();
                        } catch (PDOException $e) {
                            $districtCount = "Hata";
                        }
                    ?>
                    <tr>
                        <td><?php echo htmlspecialchars($city['name']); ?></td>
                        <td>
                            <?php if ($city['is_metropolitan']): ?>
                                <span class="badge bg-primary">Büyükşehir</span>
                            <?php else: ?>
                                <span class="badge bg-secondary">Normal</span>
                            <?php endif; ?>
                        </td>
                        <td><?php echo htmlspecialchars($city['party_name'] ?? 'Belirtilmemiş'); ?></td>
                        <td><?php echo htmlspecialchars($city['mayor'] ?? 'Belirtilmemiş'); ?></td>
                        <td><?php echo htmlspecialchars($city['population_count'] ?? 'Belirtilmemiş'); ?></td>
                        <td>
                            <?php 
                            $solutionRate = floatval($city['solution_rate'] ?? 0);
                            $colorClass = $solutionRate >= 75 ? 'bg-success' : ($solutionRate >= 50 ? 'bg-info' : ($solutionRate >= 25 ? 'bg-warning' : 'bg-danger'));
                            ?>
                            <div class="progress" style="height: 20px;">
                                <div class="progress-bar <?php echo $colorClass; ?>" role="progressbar" style="width: <?php echo min($solutionRate, 100); ?>%" aria-valuenow="<?php echo min($solutionRate, 100); ?>" aria-valuemin="0" aria-valuemax="100">
                                    <?php echo number_format($solutionRate, 1); ?>%
                                </div>
                            </div>
                        </td>
                        <td><?php echo $districtCount; ?></td>
                        <td>
                            <button type="button" class="btn btn-sm btn-primary me-1" onclick="editCity(<?php echo htmlspecialchars(json_encode($city)); ?>)">
                                <i class="fas fa-edit"></i>
                            </button>
                            <button type="button" class="btn btn-sm btn-danger" onclick="deleteCity('<?php echo $city['id']; ?>', '<?php echo htmlspecialchars($city['name']); ?>')" <?php echo $districtCount > 0 ? 'disabled' : ''; ?>>
                                <i class="fas fa-trash"></i>
                            </button>
                            <a href="index.php?page=districts&city_id=<?php echo $city['id']; ?>" class="btn btn-sm btn-info ms-1">
                                <i class="fas fa-map"></i> İlçeler
                            </a>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                    
                    <?php if (empty($cities)): ?>
                    <tr>
                        <td colspan="8" class="text-center">Henüz şehir kaydı bulunmamaktadır.</td>
                    </tr>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<script>
function resetCityForm() {
    document.getElementById('cityForm').reset();
    document.getElementById('city-action').value = 'add';
    document.getElementById('city-id').value = '';
    document.getElementById('cityModalLabel').innerText = 'Şehir Ekle';
}

function editCity(city) {
    document.getElementById('city-action').value = 'edit';
    document.getElementById('city-id').value = city.id;
    document.getElementById('name').value = city.name;
    document.getElementById('is_metropolitan').checked = city.is_metropolitan;
    document.getElementById('political_party_id').value = city.political_party_id || '';
    document.getElementById('mayor').value = city.mayor || '';
    document.getElementById('population_count').value = city.population_count || '';
    document.getElementById('cityModalLabel').innerText = 'Şehri Düzenle: ' + city.name;
    
    // Open the modal
    var modal = new bootstrap.Modal(document.getElementById('cityModal'));
    modal.show();
}

function deleteCity(cityId, cityName) {
    document.getElementById('delete-city-id').value = cityId;
    document.getElementById('deleteCityModalLabel').innerText = 'Şehri Sil: ' + cityName;
    
    // Open the confirmation modal
    var modal = new bootstrap.Modal(document.getElementById('deleteCityModal'));
    modal.show();
}
</script>