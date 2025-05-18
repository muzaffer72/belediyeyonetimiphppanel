<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');
// Şehirler verilerini al
$cities_result = getData('cities');
$cities = $cities_result['data'];

// Parti verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'];

// Yeni şehir ekle formu gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['add_city'])) {
    // Form verilerini al
    $name = trim($_POST['name'] ?? '');
    $email = trim($_POST['email'] ?? '');
    $mayor_name = trim($_POST['mayor_name'] ?? '');
    $political_party_id = trim($_POST['political_party_id'] ?? '');
    $population = trim($_POST['population'] ?? '');
    $logo_url = trim($_POST['logo_url'] ?? '');
    
    // Basit doğrulama
    $errors = [];
    if (empty($name)) {
        $errors[] = 'Şehir adı gereklidir';
    }
    
    // Hata yoksa şehri ekle
    if (empty($errors)) {
        $new_city = [
            'name' => $name,
            'email' => $email,
            'mayor_name' => $mayor_name,
            'political_party_id' => $political_party_id,
            'population' => $population,
            'logo_url' => $logo_url
        ];
        
        $response = addData('cities', $new_city);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'Şehir başarıyla eklendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile (formun tekrar gönderilmesini önlemek için)
            if (!headers_sent()) {
        header('Location: index.php?page=cities');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cities";</script>';
        exit;
    }
        } else {
            $_SESSION['message'] = 'Şehir eklenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// Şehir sil
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $city_id = $_GET['delete'];
    $response = deleteData('cities', $city_id);
    
    if (!$response['error']) {
        $_SESSION['message'] = 'Şehir başarıyla silindi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'Şehir silinirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=cities');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=cities";</script>';
        exit;
    }
}
?>

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

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">Şehirler Yönetimi</h1>
    
    <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addCityModal">
        <i class="fas fa-plus me-1"></i> Yeni Şehir Ekle
    </button>
</div>

<!-- Şehirler Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-table me-1"></i>
        Şehirler Listesi
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-striped table-hover">
                <thead>
                    <tr>
                        <th style="width: 80px;">Logo</th>
                        <th>Şehir Adı</th>
                        <th>Belediye Başkanı</th>
                        <th>Parti</th>
                        <th>Nüfus</th>
                        <th>Email</th>
                        <th style="width: 150px;">İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if(empty($cities)): ?>
                        <tr>
                            <td colspan="7" class="text-center">Henüz şehir kaydı bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($cities as $city): ?>
                            <tr>
                                <td class="text-center">
                                    <?php if(isset($city['logo_url']) && !empty($city['logo_url'])): ?>
                                        <img src="<?php echo $city['logo_url']; ?>" alt="<?php echo isset($city['name']) ? $city['name'] : ''; ?> Logo" width="50" height="50" class="img-thumbnail">
                                    <?php else: ?>
                                        <i class="fas fa-city fa-2x text-secondary"></i>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($city['name']) ? escape($city['name']) : ''; ?></td>
                                <td><?php echo isset($city['mayor_name']) ? escape($city['mayor_name']) : ''; ?></td>
                                <td>
                                    <?php if(isset($city['political_party_id']) && !empty($city['political_party_id'])): ?>
                                        <?php 
                                        // Parti bilgilerini getir
                                        $party_info = null;
                                        foreach($parties as $party) {
                                            if($party['id'] == $city['political_party_id']) {
                                                $party_info = $party;
                                                break;
                                            }
                                        }
                                        
                                        if($party_info): 
                                        ?>
                                        <div class="d-flex align-items-center">
                                            <?php if(!empty($party_info['logo_url'])): ?>
                                                <img src="<?php echo escape($party_info['logo_url']); ?>" alt="<?php echo escape($party_info['name']); ?>" class="me-2" style="height: 20px; width: auto;">
                                            <?php endif; ?>
                                            <span class="badge bg-primary"><?php echo escape($party_info['name']); ?></span>
                                        </div>
                                        <?php else: ?>
                                            <small class="text-muted">ID: <?php echo escape($city['political_party_id']); ?></small>
                                        <?php endif; ?>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($city['population']) ? escape($city['population']) : ''; ?></td>
                                <td><?php echo isset($city['email']) ? escape($city['email']) : ''; ?></td>
                                <td>
                                    <div class="btn-group btn-group-sm">
                                        <a href="index.php?page=city_detail&id=<?php echo $city['id']; ?>" class="btn btn-info" title="Görüntüle">
                                            <i class="fas fa-eye"></i>
                                        </a>
                                        <a href="index.php?page=city_edit&id=<?php echo $city['id']; ?>" class="btn btn-warning" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <a href="javascript:void(0);" class="btn btn-danger" 
                                           onclick="if(confirm('Bu şehri silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=cities&delete=<?php echo $city['id']; ?>';" 
                                           title="Sil">
                                            <i class="fas fa-trash"></i>
                                        </a>
                                    </div>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<!-- Yeni Şehir Ekle Modal -->
<div class="modal fade" id="addCityModal" tabindex="-1" aria-labelledby="addCityModalLabel" aria-hidden="true">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="addCityModalLabel">Yeni Şehir Ekle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="post" action="index.php?page=cities">
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="name" class="form-label">Şehir Adı <span class="text-danger">*</span></label>
                            <input type="text" class="form-control" id="name" name="name" required>
                        </div>
                        <div class="col-md-6">
                            <label for="email" class="form-label">Email</label>
                            <input type="email" class="form-control" id="email" name="email">
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="mayor_name" class="form-label">Belediye Başkanı</label>
                            <input type="text" class="form-control" id="mayor_name" name="mayor_name">
                        </div>
                        <div class="col-md-6">
                            <label for="political_party_id" class="form-label">Parti</label>
                            <select class="form-select" id="political_party_id" name="political_party_id">
                                <option value="">Seçiniz</option>
                                <?php foreach($parties as $party): ?>
                                    <option value="<?php echo $party['id']; ?>"><?php echo $party['name']; ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="population" class="form-label">Nüfus</label>
                            <input type="text" class="form-control" id="population" name="population">
                        </div>
                        <div class="col-md-6">
                            <label for="logo_url" class="form-label">Logo URL</label>
                            <input type="url" class="form-control" id="logo_url" name="logo_url">
                        </div>
                    </div>
                    
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                        <button type="submit" name="add_city" class="btn btn-primary">Kaydet</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>